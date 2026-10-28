package com.sundr.myapp

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonArray
import com.sundr.myapp.data.MeasurementConfig
import com.sundr.myapp.data.ReadingRepository
import com.sundr.myapp.data.Vital
import com.sundr.myapp.events.NewReadingEvent
import com.oudmon.ble.base.bluetooth.BleOperateManager
import com.oudmon.ble.base.communication.ICommandResponse
import com.oudmon.ble.base.communication.entity.BleStepDetails
import com.oudmon.ble.base.communication.rsp.BaseRspCmd
import com.oudmon.ble.base.communication.rsp.StartHeartRateRsp
import kotlinx.coroutines.launch
import org.greenrobot.eventbus.EventBus
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.ConcurrentHashMap

// Continuously round-robins Steps -> HR -> SpO2 -> Stress -> BP -> HRV -> Temperature
// with a configurable cooldown between full cycles (see
// MeasurementConfig.getCycleCooldownMs/setCycleCooldownMs, default 3 min), persisting every
// reading to Room and publishing a NewReadingEvent for future analyzer modules. Driven by
// BleConnectionService.onCreate()/onDestroy() — never runs standalone.
//
// Manual ("Measure Now") measurements from BlePlugin preempt this loop: BlePlugin sets
// MeasurementCoordinator.manualRequestPending before it starts trying to acquire the ring,
// and this loop polls that flag both between vitals (walkSequence) and while a vital is
// actively in flight (watchForPreempt) so it can abort quickly instead of running to its
// own (up to 90s, for HRV) timeout. See watchForPreempt's kdoc for the timing budget.
//
// Adaptive timeouts: per-vital timeouts track a rolling average of actual response times
// so the BLE radio is only held open as long as needed. The cycle cooldown also adapts —
// when all vitals are normal (no FallRiskAnalyzer anomalies), the cooldown stretches to
// reduce radio duty cycle; when anomalies are detected, it snaps back to the default.
object MeasurementLoopManager {
    private const val TAG = "MeasurementLoop"
    private const val DISCONNECTED_RECHECK_MS = 8_000L
    private const val WORKOUT_RECHECK_MS = 15_000L
    // After the ring confirms its bind, wait this long before the first cycle so Dart's
    // post-connect setTime / HR-interval / battery commands go out ahead of the first vital.
    private const val POST_BIND_SETTLE_MS = 3_000L
    // If bindReady never arrives (user dismissed the pairing dialog, old firmware), start
    // anyway after this long — same budget as BleProvider._waitForBindReady().
    private const val BIND_WAIT_TIMEOUT_MS = 15_000L

    // Fixed ceiling timeouts — the adaptive system uses actual response time + headroom,
    // but these hard caps prevent a stuck ring from blocking the loop indefinitely.
    private const val MEASURE_TIMEOUT_MS = 60_000L
    private const val HRV_MEASURE_TIMEOUT_MS = 90_000L
    private const val TEMP_MEASURE_TIMEOUT_MS = 90_000L

    // Adaptive timeout parameters. Each vital tracks a rolling average of actual response
    // times; the adaptive timeout is max(avg * 1.5, MIN_TIMEOUT_MS). This lets the loop
    // finish fast when the ring responds quickly (typical: 5–15 s) while still tolerating
    // slow HRV/Temp readings that can legitimately take 60 s+.
    private const val MIN_TIMEOUT_MS = 15_000L
    private const val TIMEOUT_HEADROOM_FACTOR = 1.5
    private const val ROLLING_WINDOW = 5

    // Adaptive cooldown between full measurement cycles. When the FallRiskAnalyzer reports
    // no anomalies for several consecutive cycles, the cooldown stretches to reduce BLE
    // radio duty cycle. An anomaly immediately resets to the default (fast) cooldown.
    private const val FAST_COOLDOWN_MS = 180_000L   // 3 min — default, anomaly mode
    private const val SLOW_COOLDOWN_MS = 900_000L   // 15 min — healthy mode
    private const val NORMALCY_CONFIRM_CYCLES = 2   // consecutive normal cycles before slowing down

    // Gap enforced after sending a "stop" command (success or timeout) before the next
    // vital's "start" command goes out. Without this, back-to-back start-stop-start
    // commands with no settle time can leave the ring's firmware stuck mid-measurement
    // (observed in testing: continuous LED blink, no further one-click measurement
    // possible until the ring was power-cycled).
    private const val POST_STOP_SETTLE_MS = 2_000L
    private const val OWNER = "loop"
    // How often watchForPreempt checks manualRequestPending while a vital is in flight.
    // Kept short relative to BlePlugin's manual acquire retry window (currently up to 4s)
    // so the stop-command + POST_STOP_SETTLE_MS below comfortably finishes before that
    // window closes: worst case is POLL + POST_STOP_SETTLE_MS (~2.2s), well under 4s.
    private const val PREEMPT_POLL_MS = 200L

    // Rolling actual-response-time tracker per vital. Keyed by Vital.name. Each entry is a
    // circular buffer of the last ROLLING_WINDOW measurement durations (ms).
    private val responseTimes = ConcurrentHashMap<String, MutableList<Long>>()
    private var consecutiveNormalCycles = 0

    private val sequence = listOf(
        Vital.STEPS, Vital.HEART_RATE, Vital.SPO2, Vital.STRESS, Vital.BLOOD_PRESSURE,
        Vital.HRV, Vital.TEMPERATURE
    )

    private val gson = Gson()
    private val handler = Handler(Looper.getMainLooper())
    private var started = false
    private val runningCycle = AtomicBoolean(false)
    // Set between the GATT connect and the ring's bind confirmation (0 = not waiting).
    // Measurement commands sent in that window are ignored by the ring, so every vital ran to
    // its timeout and the first real reading only came a full cooldown later.
    @Volatile private var bindWaitUntilMs = 0L
    private lateinit var repository: ReadingRepository

    // ── Adaptive timeout helpers ────────────────────────────────────────────

    /** Record an actual measurement duration (ms) for the given vital. */
    private fun recordResponseTime(vital: String, durationMs: Long) {
        val list = responseTimes.getOrPut(vital) { mutableListOf() }
        synchronized(list) {
            list.add(durationMs)
            if (list.size > ROLLING_WINDOW) list.removeAt(0)
        }
    }

    /**
     * Compute an adaptive timeout for [vital]: the rolling average of past response times
     * × [TIMEOUT_HEADROOM_FACTOR], clamped between [MIN_TIMEOUT_MS] and the fixed ceiling
     * ([MEASURE_TIMEOUT_MS] or the vital-specific override). Falls back to the fixed ceiling
     * when no history exists yet.
     */
    private fun adaptiveTimeout(vital: String, ceilingMs: Long = MEASURE_TIMEOUT_MS): Long {
        val list = responseTimes[vital] ?: return ceilingMs
        val avg = synchronized(list) {
            if (list.isEmpty()) return ceilingMs
            list.sum().toDouble() / list.size
        }
        val adaptive = (avg * TIMEOUT_HEADROOM_FACTOR).toLong()
        return adaptive.coerceIn(MIN_TIMEOUT_MS, ceilingMs)
    }

    /** Check whether the FallRiskAnalyzer considers current vitals anomalous. */
    private fun isAnomalyDetected(): Boolean {
        return try {
            com.sundr.myapp.analysis.FallRiskAnalyzer.currentTier() in
                setOf("HIGH", "CRITICAL", "OVERRIDE")
        } catch (_: Exception) {
            false
        }
    }

    private val cycleRunnable = Runnable { runCycleIfPossible() }

    fun start(context: Context) {
        if (started) return
        started = true
        val appContext = context.applicationContext
        MeasurementConfig.init(appContext)
        repository = ReadingRepository.getInstance(appContext)
        scheduleNext(2_000L)
    }

    fun stop() {
        started = false
        handler.removeCallbacks(cycleRunnable)
    }

    // Hooked from BlePlugin.onServiceDiscovered(). The ring is linked but not yet bound, so
    // hold the loop until onRingReady() (or the bind timeout) instead of measuring now.
    fun onRingConnected() {
        bindWaitUntilMs = System.currentTimeMillis() + BIND_WAIT_TIMEOUT_MS
        runningCycle.set(false)
        if (started) scheduleNext(BIND_WAIT_TIMEOUT_MS)
    }

    // Hooked from BlePlugin.sendBindSuccessWithRetry() (the "bindReady" event): the ring now
    // accepts measurement commands, so start the first cycle right away.
    fun onRingReady() {
        bindWaitUntilMs = 0L
        if (!started) return
        runningCycle.set(false)
        scheduleNext(POST_BIND_SETTLE_MS)
    }

    fun onRingDisconnected() {
        bindWaitUntilMs = 0L
        runningCycle.set(false)
    }

    /**
     * "Measure now" from the Home ring card: start a full cycle right away instead of
     * waiting out the cooldown. Never interrupts a cycle that is already running; the
     * usual checks in runCycleIfPossible (workout, manual measurement, SDK guard) still
     * apply. Returns what happened, for the button's message.
     */
    fun requestCycleNow(): String {
        if (!started || !MeasurementConfig.isMasterEnabled()) return "unavailable"
        if (!com.sundr.myapp.sdk.BleSdkLifecycle.isConnected()) return "disconnected"
        if (bindWaitUntilMs > System.currentTimeMillis()) return "pairing"
        if (runningCycle.get()) return "running"
        scheduleNext(0L)
        return "started"
    }

    private fun scheduleNext(delayMs: Long) {
        handler.removeCallbacks(cycleRunnable)
        handler.postDelayed(cycleRunnable, delayMs)
    }

    private fun runCycleIfPossible() {
        if (!started || !MeasurementConfig.isMasterEnabled()) {
            scheduleNext(DISCONNECTED_RECHECK_MS)
            return
        }
        if (com.sundr.myapp.sdk.SdkGuard.isOpen()) {
            scheduleNext(DISCONNECTED_RECHECK_MS)
            return
        }
        val connected = com.sundr.myapp.sdk.BleSdkLifecycle.isConnected()
        if (!connected) {
            scheduleNext(DISCONNECTED_RECHECK_MS)
            return
        }
        val bindWaitMs = bindWaitUntilMs - System.currentTimeMillis()
        if (bindWaitMs > 0) {
            scheduleNext(bindWaitMs)
            return
        }
        if (MeasurementCoordinator.isWorkoutActive) {
            scheduleNext(WORKOUT_RECHECK_MS)
            return
        }
        val currentHolder = MeasurementCoordinator.currentOwner()
        if (MeasurementCoordinator.manualRequestPending || (currentHolder != null && currentHolder != OWNER)) {
            scheduleNext(WORKOUT_RECHECK_MS)
            return
        }
        if (!runningCycle.compareAndSet(false, true)) {
            scheduleNext(DISCONNECTED_RECHECK_MS)
            return
        }

        repository.ioScope.launch {
            try {
                val cycleId = repository.startCycle()
                handler.post { walkSequence(cycleId, 0) }
            } catch (e: Exception) {
                Log.e(TAG, "startCycle failed", e)
                runningCycle.set(false)
                scheduleNext(DISCONNECTED_RECHECK_MS)
            }
        }
    }

    private fun walkSequence(cycleId: Long, index: Int) {
        if (index >= sequence.size) {
            finishCycle(cycleId, "COMPLETED", null)
            return
        }
        val connected = com.sundr.myapp.sdk.BleSdkLifecycle.isConnected()
        if (!connected) {
            // Deliberately restart at HEART_RATE on the next cycle rather than resuming here.
            logAttempt(sequence[index].name, "auto_cycle", cycleId, "aborted_disconnect", "ring disconnected before vital")
            finishCycle(cycleId, "ABORTED_DISCONNECT", sequence[index].name)
            return
        }
        if (MeasurementCoordinator.isWorkoutActive) {
            logAttempt(sequence[index].name, "auto_cycle", cycleId, "skipped_workout", "workout active")
            finishCycle(cycleId, "SKIPPED_WORKOUT", sequence[index].name)
            return
        }
        if (MeasurementCoordinator.manualRequestPending) {
            // Manual "Measure Now" wants the ring — yield instead of starting the next vital.
            // We deliberately don't try to resume mid-sequence; the next cycle starts fresh
            // from the top (same as the disconnect-abort path above).
            Log.d(TAG, "walkSequence: yielding to manual before ${sequence[index].name}")
            logAttempt(sequence[index].name, "auto_cycle", cycleId, "yielded", "manualRequestPending")
            finishCycle(cycleId, "YIELDED_TO_MANUAL", sequence[index].name)
            return
        }
        val vital = sequence[index]
        if (!MeasurementConfig.isEnabled(vital)) {
            logAttempt(vital.name, "auto_cycle", cycleId, "skipped_disabled", "vital disabled in config")
            walkSequence(cycleId, index + 1)
            return
        }
        val attemptIdHolder = longArrayOf(-1L)
        repository.ioScope.launch {
            try {
                attemptIdHolder[0] = repository.startAttempt(vital.name, "auto_cycle", cycleId)
            } catch (_: Exception) {}
        }
        measure(vital, cycleId) {
            if (attemptIdHolder[0] > 0) {
                repository.ioScope.launch {
                    try {
                        // HR now finishes its attempt explicitly (success + extractor tag,
                        // or failed_no_data). If still RUNNING here, no reading was
                        // persisted — record failure instead of the old false-success that
                        // hid empty HR charts. Other vitals keep legacy success marking
                        // until they get explicit finish paths of their own.
                        val existing = repository.attemptsForCycle(cycleId).find { it.vital == vital.name && it.status == "RUNNING" }
                        if (existing != null) {
                            if (vital == Vital.HEART_RATE) {
                                repository.finishAttempt(existing.id, "failed_no_data", "no reading persisted before onDone", null)
                            } else {
                                repository.finishAttempt(existing.id, "success", null, null)
                            }
                        }
                    } catch (_: Exception) {}
                }
            }
            walkSequence(cycleId, index + 1)
        }
    }

    private fun logAttempt(vital: String, source: String, cycleId: Long, status: String, error: String?) {
        repository.ioScope.launch {
            try {
                val id = repository.startAttempt(vital, source, cycleId)
                repository.finishAttempt(id, status, error, null)
            } catch (_: Exception) {}
        }
    }

    private fun finishCycle(cycleId: Long, status: String, abortedAtVital: String?) {
        repository.ioScope.launch {
            repository.completeCycle(cycleId, status, abortedAtVital)
        }
        runningCycle.set(false)
        // After yielding to manual measurement, come back sooner than the full cooldown so
        // the loop resumes promptly once manual measurement is done, instead of the user
        // seeing a full cooldown-length gap in the auto cycle.
        val delay = when {
            status == "YIELDED_TO_MANUAL" -> WORKOUT_RECHECK_MS
            // Retry as soon as the ring is back rather than sitting out a full cooldown.
            status == "ABORTED_DISCONNECT" -> DISCONNECTED_RECHECK_MS
            status != "COMPLETED" -> MeasurementConfig.getCycleCooldownMs()
            isAnomalyDetected() -> {
                consecutiveNormalCycles = 0
                MeasurementConfig.getCycleCooldownMs().coerceAtMost(FAST_COOLDOWN_MS)
            }
            else -> {
                consecutiveNormalCycles++
                if (consecutiveNormalCycles >= NORMALCY_CONFIRM_CYCLES) {
                    MeasurementConfig.getCycleCooldownMs().coerceAtLeast(SLOW_COOLDOWN_MS)
                } else {
                    MeasurementConfig.getCycleCooldownMs()
                }
            }
        }
        scheduleNext(delay)
    }

    // ── Per-vital measurement, mirroring BlePlugin's proven wait-for-nonzero pattern ──

    private fun measure(vital: Vital, cycleId: Long, onDone: () -> Unit) {
        try {
            when (vital) {
                Vital.HEART_RATE -> measureHeartRate(cycleId, onDone)
                Vital.SPO2 -> measureSpo2(cycleId, onDone)
                Vital.STRESS -> measureStress(cycleId, onDone)
                Vital.BLOOD_PRESSURE -> measureBloodPressure(cycleId, onDone)
                Vital.STEPS -> measureSteps(cycleId, onDone)
                Vital.HRV -> measureHrv(cycleId, onDone)
                Vital.TEMPERATURE -> measureTemperature(cycleId, onDone)
            }
        } catch (e: Exception) {
            Log.e(TAG, "measure($vital) failed", e)
            try {
                MeasurementCoordinator.release(OWNER)
            } catch (_: Exception) {
            }
            onDone()
        }
    }

    // Polls every PREEMPT_POLL_MS while a vital is in flight; if manual measurement has
    // requested the ring (MeasurementCoordinator.manualRequestPending), fires `onPreempted`
    // immediately instead of waiting for the vital's own timeout (up to 90s for HRV).
    // Stops polling once `done` is true (vital finished/errored/timed out on its own) —
    // callers pass the same AtomicBoolean they use to gate their own completion.
    private fun watchForPreempt(done: AtomicBoolean, onPreempted: () -> Unit) {
        handler.postDelayed({
            if (done.get()) return@postDelayed
            if (MeasurementCoordinator.manualRequestPending) {
                Log.d(TAG, "watchForPreempt: manualRequestPending detected, yielding mid-vital")
                if (done.compareAndSet(false, true)) onPreempted()
            } else {
                watchForPreempt(done, onPreempted)
            }
        }, PREEMPT_POLL_MS)
    }

    private fun measureHeartRate(cycleId: Long, onDone: () -> Unit) {
        if (!MeasurementCoordinator.tryAcquire(OWNER)) { onDone(); return }
        val done = AtomicBoolean(false)
        val startTimeMs = System.currentTimeMillis()
        // Sends the stop command, then waits POST_STOP_SETTLE_MS before releasing the
        // coordinator lock and moving on — see POST_STOP_SETTLE_MS doc comment for why.
        fun finishWithStop() {
            try { BleOperateManager.getInstance().manualModeHeart(null, true) } catch (_: Exception) {}
            handler.postDelayed({
                MeasurementCoordinator.release(OWNER)
                onDone()
            }, POST_STOP_SETTLE_MS)
        }
        fun finishNoStop() {
            MeasurementCoordinator.release(OWNER)
            onDone()
        }
        watchForPreempt(done) { finishWithStop() }

        // The ring streams intermediate StartHeartRateRsp frames while measuring, and early
        // warm-up frames are often spuriously high (motion artifact / partial PPG). Accepting
        // the first non-zero callback biased daily averages high. Instead: collect plausible
        // candidates, persist once two consecutive readings agree (median), or fall back to
        // the median of what we have when the measurement times out.
        //
        // Extraction must also be frame-type aware. Per SDK StartHeartRateRsp.acceptData:
        //   type 12 = vital frame      -> heart == value == data[2] (HR)
        //   type 13 = HR + raw PPG     -> heartRate = data[3]
        //   type 14 = SpO2 + raw PPG   -> bloodOxygen = data[3], heartRate stays 0
        //   other   = BP/temperature   -> value is an unrelated byte (can be huge)
        // All manual-mode commands share one response slot in the SDK singleton, so a frame
        // belonging to another vital can be delivered to this callback; reading getValue()
        // from such a frame persisted SpO2 (~95-100) or junk bytes as bpm.
        // BLE callbacks may arrive off the main thread while the timeout below fires on it,
        // so all access to samples is guarded by its own monitor.
        // QRing comparison: firmware interval blob is already pre-averaged; phone-side
        // polling is warm-up prone, so we relax the 8 bpm agreement to 12 bpm and use
        // lower-median (not upper-median) to avoid biasing toward early warm-up 87.
        //
        // Legacy fallback (pre-Aug24 mechanism): strict extraction above can yield zero
        // candidates when firmware sends HR in an unexpected frame while getHeartRate()==0
        // and type!=12. As a second tier we also collect legacy candidates
        // (getHeartRate else getValue, still range-gated to 30-220) and use their median
        // only when strict produced nothing. Tagged source=auto_cycle_fallback so the
        // Measurement Log distinguishes them.
        val samples = mutableListOf<Int>()
        val legacySamples = mutableListOf<Int>()
        val sampleLock = Any()
        fun extractBpm(rsp: StartHeartRateRsp): Int? {
            if (rsp.getHeartRate() > 0) return rsp.getHeartRate()
            if (rsp.type.toInt() == 12) return rsp.value
            return null
        }
        fun extractLegacyBpm(rsp: StartHeartRateRsp): Int? {
            val v = if (rsp.getHeartRate() > 0) rsp.getHeartRate() else rsp.getValue()
            if (v > 0 && com.sundr.myapp.data.VitalRanges.isValidBpm(v)) return v
            return null
        }
        try {
            BleOperateManager.getInstance().manualModeHeart(
                ICommandResponse<StartHeartRateRsp> { rsp ->
                    if (done.get()) return@ICommandResponse
                    // Ring-reported errors (not worn, weak signal) must not count as
                    // candidates — skip immediately instead of waiting for timeout.
                    val frameErr: Int = try { rsp.getErrCode().toInt() } catch (_: Exception) { 0 }
                    if (frameErr != 0) {
                        Log.w(TAG, "measureHeartRate: ring errCode=$frameErr, skipping frame")
                        return@ICommandResponse
                    }
                    // Don't bail out on rsp.status != RESULT_OK here — a manual heart rate
                    // measurement sends several intermediate callbacks while still measuring,
                    // and not all of them report RESULT_OK. Just wait for a genuine value;
                    // MEASURE_TIMEOUT_MS below handles the case where none ever comes.
                    val candidate = extractBpm(rsp)
                    val legacyCandidate = extractLegacyBpm(rsp)
                    Log.d(TAG, "measureHeartRate: status=${rsp.status} heartRate=${rsp.getHeartRate()} value=${rsp.getValue()} candidate=$candidate legacy=$legacyCandidate")
                    if (legacyCandidate != null) {
                        synchronized(sampleLock) {
                            if (!done.get()) legacySamples.add(legacyCandidate)
                        }
                    }
                    if (candidate != null && com.sundr.myapp.data.VitalRanges.isValidBpm(candidate)) {
                        var accepted: Int? = null
                        synchronized(sampleLock) {
                            if (done.get()) return@ICommandResponse
                            samples.add(candidate)
                            if (samples.size >= 2) {
                                val prev = samples[samples.size - 2]
                                if (kotlin.math.abs(candidate - prev) <= 12) {
                                    val sorted = samples.sorted()
                                    accepted = sorted[(sorted.size - 1) / 2]
                                }
                            }
                        }
                        if (accepted != null && done.compareAndSet(false, true)) {
                            recordResponseTime(Vital.HEART_RATE.name, System.currentTimeMillis() - startTimeMs)
                            persist(Vital.HEART_RATE, cycleId, accepted.toDouble()) {
                                repository.insertHeartRate(accepted, cycleId, "auto_cycle")
                            }
                            finishHrAttempt(cycleId, "success", null, "{\"extractor\":\"strict\",\"value\":$accepted}")
                            finishWithStop()
                        }
                    }
                },
                false
            )
        } catch (e: Exception) {
            Log.e(TAG, "measureHeartRate failed", e)
            if (done.compareAndSet(false, true)) finishNoStop()
            return
        }
        handler.postDelayed({
            // Timeout tier: strict median first; then legacy median (pre-Aug24 extraction,
            // still range-gated); else record failure so the log no longer shows false success.
            var median: Int? = null
            var legacyMedian: Int? = null
            synchronized(sampleLock) {
                if (samples.isNotEmpty()) {
                    val sorted = samples.sorted()
                    median = sorted[(sorted.size - 1) / 2]
                }
                if (legacySamples.isNotEmpty()) {
                    val sortedLegacy = legacySamples.sorted()
                    legacyMedian = sortedLegacy[(sortedLegacy.size - 1) / 2]
                }
            }
            if (done.compareAndSet(false, true)) {
                if (median != null) {
                    persist(Vital.HEART_RATE, cycleId, median.toDouble()) {
                        repository.insertHeartRate(median, cycleId, "auto_cycle")
                    }
                    finishHrAttempt(cycleId, "success", null, "{\"extractor\":\"strict_timeout\",\"value\":$median}")
                } else if (legacyMedian != null) {
                    persist(Vital.HEART_RATE, cycleId, legacyMedian.toDouble()) {
                        repository.insertHeartRate(legacyMedian, cycleId, "auto_cycle_fallback")
                    }
                    finishHrAttempt(cycleId, "success", null, "{\"extractor\":\"legacy\",\"value\":$legacyMedian}")
                } else {
                    finishHrAttempt(cycleId, "failed_no_data", "strict+legacy empty after timeout", null)
                }
                finishWithStop()
            }
        }, adaptiveTimeout(Vital.HEART_RATE.name, MEASURE_TIMEOUT_MS))
    }

    private fun measureSpo2(cycleId: Long, onDone: () -> Unit) {
        if (!MeasurementCoordinator.tryAcquire(OWNER)) { onDone(); return }
        val done = AtomicBoolean(false)
        val startTimeMs = System.currentTimeMillis()
        fun finishWithStop() {
            try { BleOperateManager.getInstance().manualModeSpO2(ICommandResponse<StartHeartRateRsp> {}, true) } catch (_: Exception) {}
            handler.postDelayed({
                MeasurementCoordinator.release(OWNER)
                onDone()
            }, POST_STOP_SETTLE_MS)
        }
        fun finishNoStop() {
            MeasurementCoordinator.release(OWNER)
            onDone()
        }
        watchForPreempt(done) { finishWithStop() }
        try {
            BleOperateManager.getInstance().manualModeSpO2(
                ICommandResponse<StartHeartRateRsp> { rsp ->
                    if (done.get()) return@ICommandResponse
                    val spo2 = if (rsp.getBloodOxygen() > 0) rsp.getBloodOxygen() else rsp.getValue()
                    if (spo2 > 0 && done.compareAndSet(false, true)) {
                        recordResponseTime(Vital.SPO2.name, System.currentTimeMillis() - startTimeMs)
                        persist(Vital.SPO2, cycleId, spo2.toDouble()) {
                            repository.insertSpo2(spo2, cycleId, "auto_cycle")
                        }
                        finishWithStop()
                    }
                },
                false
            )
        } catch (e: Exception) {
            Log.e(TAG, "measureSpo2 failed", e)
            if (done.compareAndSet(false, true)) finishNoStop()
            return
        }
        handler.postDelayed({
            if (done.compareAndSet(false, true)) finishWithStop()
        }, adaptiveTimeout(Vital.SPO2.name, MEASURE_TIMEOUT_MS))
    }

    private fun measureStress(cycleId: Long, onDone: () -> Unit) {
        if (!MeasurementCoordinator.tryAcquire(OWNER)) { onDone(); return }
        val done = AtomicBoolean(false)
        val startTimeMs = System.currentTimeMillis()
        fun finishWithStop() {
            try { BleOperateManager.getInstance().manualModePressure(ICommandResponse<StartHeartRateRsp> {}, true) } catch (_: Exception) {}
            handler.postDelayed({
                MeasurementCoordinator.release(OWNER)
                onDone()
            }, POST_STOP_SETTLE_MS)
        }
        fun finishNoStop() {
            MeasurementCoordinator.release(OWNER)
            onDone()
        }
        watchForPreempt(done) { finishWithStop() }
        try {
            BleOperateManager.getInstance().manualModePressure(
                ICommandResponse<StartHeartRateRsp> { rsp ->
                    if (done.get()) return@ICommandResponse
                    val value = rsp.getValue()
                    if (value > 0 && done.compareAndSet(false, true)) {
                        recordResponseTime(Vital.STRESS.name, System.currentTimeMillis() - startTimeMs)
                        persist(Vital.STRESS, cycleId, value.toDouble()) {
                            repository.insertStress(value, null, cycleId, "auto_cycle")
                        }
                        finishWithStop()
                    }
                },
                false
            )
        } catch (e: Exception) {
            Log.e(TAG, "measureStress failed", e)
            if (done.compareAndSet(false, true)) finishNoStop()
            return
        }
        handler.postDelayed({
            if (done.compareAndSet(false, true)) finishWithStop()
        }, adaptiveTimeout(Vital.STRESS.name, MEASURE_TIMEOUT_MS))
    }

    private fun measureBloodPressure(cycleId: Long, onDone: () -> Unit) {
        if (!MeasurementCoordinator.tryAcquire(OWNER)) { onDone(); return }
        val done = AtomicBoolean(false)
        val startTimeMs = System.currentTimeMillis()
        fun finishWithStop() {
            try { BleOperateManager.getInstance().manualModeBP(ICommandResponse<StartHeartRateRsp> {}, true) } catch (_: Exception) {}
            handler.postDelayed({
                MeasurementCoordinator.release(OWNER)
                onDone()
            }, POST_STOP_SETTLE_MS)
        }
        fun finishNoStop() {
            MeasurementCoordinator.release(OWNER)
            onDone()
        }
        watchForPreempt(done) { finishWithStop() }
        try {
            BleOperateManager.getInstance().manualModeBP(
                ICommandResponse<StartHeartRateRsp> { rsp ->
                    if (done.get()) return@ICommandResponse
                    val sbp = rsp.getSbp()
                    val dbp = rsp.getDbp()
                    if (sbp > 0 && dbp > 0 && done.compareAndSet(false, true)) {
                        recordResponseTime(Vital.BLOOD_PRESSURE.name, System.currentTimeMillis() - startTimeMs)
                        persist(Vital.BLOOD_PRESSURE, cycleId, sbp.toDouble()) {
                            repository.insertBloodPressure(sbp, dbp, cycleId, "auto_cycle")
                        }
                        finishWithStop()
                    }
                },
                false
            )
        } catch (e: Exception) {
            Log.e(TAG, "measureBloodPressure failed", e)
            if (done.compareAndSet(false, true)) finishNoStop()
            return
        }
        handler.postDelayed({
            if (done.compareAndSet(false, true)) finishWithStop()
        }, adaptiveTimeout(Vital.BLOOD_PRESSURE.name, MEASURE_TIMEOUT_MS))
    }

    // manualModeHrv has no built-in zero-filtering (unlike HR/SpO2/BP/Stress), so it's
    // applied here — same pattern, just checking getHrv() first (see comment below).
    private fun measureHrv(cycleId: Long, onDone: () -> Unit) {
        if (!MeasurementCoordinator.tryAcquire(OWNER)) { onDone(); return }
        val startTimeMs = System.currentTimeMillis()
        Log.d(TAG, "measureHrv: starting (timeout ${adaptiveTimeout(Vital.HRV.name, HRV_MEASURE_TIMEOUT_MS)}ms)")
        val done = AtomicBoolean(false)
        fun finishWithStop() {
            try { BleOperateManager.getInstance().manualModeHrv(ICommandResponse<StartHeartRateRsp> {}, true) } catch (_: Exception) {}
            handler.postDelayed({
                MeasurementCoordinator.release(OWNER)
                onDone()
            }, POST_STOP_SETTLE_MS)
        }
        fun finishNoStop() {
            MeasurementCoordinator.release(OWNER)
            onDone()
        }
        // HRV's own timeout is 90s — this is exactly the case mid-vital preemption matters
        // most for, since without it a manual tap during an auto-cycle HRV read could wait
        // up to 90s instead of the ~200ms this gives it.
        watchForPreempt(done) { finishWithStop() }
        try {
            BleOperateManager.getInstance().manualModeHrv(
                ICommandResponse<StartHeartRateRsp> { rsp ->
                    if (done.get()) return@ICommandResponse
                    // HRV comes back through the dedicated getHrv() field, not the generic
                    // getValue() field used by HR/SpO2/BP/Stress — confirmed against the
                    // official SDK sample (HrvActivity.kt) and the bundled SDK's compiled
                    // StartHeartRateRsp class. Checking getValue() only (the original bug)
                    // meant this never saw a real reading.
                    val value = if (rsp.getHrv() > 0) rsp.getHrv() else rsp.getValue()
                    if (value > 0 && done.compareAndSet(false, true)) {
                        recordResponseTime(Vital.HRV.name, System.currentTimeMillis() - startTimeMs)
                        Log.d(TAG, "measureHrv: got value=$value")
                        persist(Vital.HRV, cycleId, value.toDouble()) {
                            repository.insertHrv(value, cycleId, "auto_cycle")
                        }
                        finishWithStop()
                    }
                },
                false
            )
        } catch (e: Exception) {
            Log.e(TAG, "measureHrv failed", e)
            if (done.compareAndSet(false, true)) finishNoStop()
            return
        }
        val hrvTimeoutMs = adaptiveTimeout(Vital.HRV.name, HRV_MEASURE_TIMEOUT_MS)
        handler.postDelayed({
            if (done.compareAndSet(false, true)) {
                Log.w(TAG, "measureHrv: timed out after ${hrvTimeoutMs}ms")
                finishWithStop()
            }
        }, hrvTimeoutMs)
    }

    // Live single temperature measurement via the SDK's dedicated manualTemperature() API —
    // the same call the manual "Measure Now" path (BlePlugin.syncManualTemperature) uses.
    // The raw value is degrees Celsius × 10 (365 → 36.5 °C), matching the scaling the SDK's
    // TemperatureOnceEntity uses. Like HRV, don't gate on status: intermediate callbacks
    // don't all report RESULT_OK, so that would abort before a real reading arrives.
    private fun measureTemperature(cycleId: Long, onDone: () -> Unit) {
        if (!MeasurementCoordinator.tryAcquire(OWNER)) { onDone(); return }
        val done = AtomicBoolean(false)
        val startTimeMs = System.currentTimeMillis()
        fun finishWithStop() {
            try { BleOperateManager.getInstance().manualTemperature(null, true) } catch (_: Exception) {}
            handler.postDelayed({
                MeasurementCoordinator.release(OWNER)
                onDone()
            }, POST_STOP_SETTLE_MS)
        }
        fun finishNoStop() {
            MeasurementCoordinator.release(OWNER)
            onDone()
        }
        watchForPreempt(done) { finishWithStop() }
        try {
            BleOperateManager.getInstance().manualTemperature(
                ICommandResponse<StartHeartRateRsp> { rsp ->
                    if (done.get()) return@ICommandResponse
                    // Temperature arrives through the dedicated getTemperature() field; fall
                    // back to the generic getValue() like the manual path does.
                    val raw = if (rsp.getTemperature() > 0) rsp.getTemperature() else rsp.getValue()
                    if (raw > 0 && done.compareAndSet(false, true)) {
                        recordResponseTime(Vital.TEMPERATURE.name, System.currentTimeMillis() - startTimeMs)
                        val tempC = raw / 10.0
                        Log.d(TAG, "measureTemperature: got raw=$raw tempC=$tempC")
                        persist(Vital.TEMPERATURE, cycleId, tempC) {
                            repository.insertTemperature(tempC, cycleId, "auto_cycle")
                        }
                        finishWithStop()
                    }
                },
                false
            )
        } catch (e: Exception) {
            Log.e(TAG, "measureTemperature failed", e)
            if (done.compareAndSet(false, true)) finishNoStop()
            return
        }
        val tempTimeoutMs = adaptiveTimeout(Vital.TEMPERATURE.name, TEMP_MEASURE_TIMEOUT_MS)
        handler.postDelayed({
            if (done.compareAndSet(false, true)) {
                Log.w(TAG, "measureTemperature: timed out after ${tempTimeoutMs}ms")
                finishWithStop()
            }
        }, tempTimeoutMs)
    }

    // Passive fetch (not a blocking manual-mode measurement) of the ring's own cumulative
    // day totals — one snapshot row per cycle. Aggregation mirrors WorkoutService.syncSteps().
    // Not gated on the coordinator lock (it doesn't send a manual-mode start/stop command),
    // so there's nothing here for manual measurement to preempt.
    private fun measureSteps(cycleId: Long, onDone: () -> Unit) {
        try {
            BleOperateManager.getInstance().getTodayStepDetail(
                object : BleOperateManager.HealthDataCallback<List<BleStepDetails>> {
                    override fun onSuccess(data: List<BleStepDetails>) {
                        try {
                            val json = gson.toJson(data)
                            val arr = gson.fromJson(json, JsonArray::class.java)
                            var totalSteps = 0
                            var totalCalRaw = 0
                            var totalDist = 0.0
                            arr?.forEach { el ->
                                val obj = el.asJsonObject
                                totalSteps += obj.get("f")?.asInt ?: 0
                                totalCalRaw += obj.get("e")?.asInt ?: 0
                                totalDist += obj.get("g")?.asDouble ?: 0.0
                            }
                            val calories = totalCalRaw / 1000
                            persist(Vital.STEPS, cycleId, totalSteps.toDouble()) {
                                repository.insertStepsSnapshot(totalSteps, calories, totalDist, cycleId, "auto_cycle")
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "measureSteps parse failed", e)
                        }
                        onDone()
                    }
                    override fun onError(code: Int, message: String?) {
                        onDone()
                    }
                }
            )
        } catch (e: Exception) {
            Log.e(TAG, "measureSteps failed", e)
            onDone()
        }
    }

    private fun persist(vital: Vital, cycleId: Long, primaryValue: Double, insert: suspend () -> Long) {
        repository.ioScope.launch {
            try {
                val id = insert()
                if (id > 0) {
                    EventBus.getDefault().post(NewReadingEvent(vital, id, cycleId, System.currentTimeMillis(), primaryValue))
                } else {
                    Log.w(TAG, "persist($vital) rejected (id=$id value=$primaryValue) — not posting event")
                }
            } catch (e: Exception) {
                Log.e(TAG, "persist($vital) failed", e)
            }
        }
    }

    private fun finishHrAttempt(cycleId: Long, status: String, error: String?, valueJson: String?) {
        repository.ioScope.launch {
            try {
                val existing = repository.attemptsForCycle(cycleId).find { it.vital == Vital.HEART_RATE.name && it.status == "RUNNING" }
                if (existing != null) {
                    repository.finishAttempt(existing.id, status, error, valueJson)
                }
            } catch (_: Exception) {}
        }
    }
}
