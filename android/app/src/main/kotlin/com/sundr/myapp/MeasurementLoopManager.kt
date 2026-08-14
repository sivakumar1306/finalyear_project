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
object MeasurementLoopManager {
    private const val TAG = "MeasurementLoop"
    private const val DISCONNECTED_RECHECK_MS = 8_000L
    private const val WORKOUT_RECHECK_MS = 15_000L
    private const val MEASURE_TIMEOUT_MS = 60_000L
    // HRV specifically needs much more headroom than the other vitals: a real reading was
    // clocked at ~60.5s on-device via logcat (manualModeHrv callback trace), right past the
    // shared 60s timeout above. Mirrors the manual "Measure Now" path's 90s timeout.
    private const val HRV_MEASURE_TIMEOUT_MS = 90_000L
    // Temperature gets the same headroom as HRV: the live single-temperature measurement
    // (manualTemperature) streams intermediate callbacks and only settles on the final
    // value, so cutting it off at the shared 60s timeout could abort real readings.
    private const val TEMP_MEASURE_TIMEOUT_MS = 90_000L
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

    private val sequence = listOf(
        Vital.STEPS, Vital.HEART_RATE, Vital.SPO2, Vital.STRESS, Vital.BLOOD_PRESSURE,
        Vital.HRV, Vital.TEMPERATURE
    )

    private val gson = Gson()
    private val handler = Handler(Looper.getMainLooper())
    private var started = false
    private val runningCycle = AtomicBoolean(false)
    private lateinit var repository: ReadingRepository

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

    // Hooked directly from BlePlugin.onServiceDiscovered() so the loop reacts immediately on
    // connect rather than waiting on its own disconnected-recheck poll.
    fun onRingConnected() {
        if (!started) return
        runningCycle.set(false)
        handler.removeCallbacks(cycleRunnable)
        handler.post(cycleRunnable)
    }

    fun onRingDisconnected() {
        runningCycle.set(false)
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
            finishCycle(cycleId, "ABORTED_DISCONNECT", sequence[index].name)
            return
        }
        if (MeasurementCoordinator.isWorkoutActive) {
            finishCycle(cycleId, "SKIPPED_WORKOUT", sequence[index].name)
            return
        }
        if (MeasurementCoordinator.manualRequestPending) {
            // Manual "Measure Now" wants the ring — yield instead of starting the next vital.
            // We deliberately don't try to resume mid-sequence; the next cycle starts fresh
            // from the top (same as the disconnect-abort path above).
            Log.d(TAG, "walkSequence: yielding to manual before ${sequence[index].name}")
            finishCycle(cycleId, "YIELDED_TO_MANUAL", sequence[index].name)
            return
        }
        val vital = sequence[index]
        if (!MeasurementConfig.isEnabled(vital)) {
            walkSequence(cycleId, index + 1)
            return
        }
        measure(vital, cycleId) { walkSequence(cycleId, index + 1) }
    }

    private fun finishCycle(cycleId: Long, status: String, abortedAtVital: String?) {
        repository.ioScope.launch {
            repository.completeCycle(cycleId, status, abortedAtVital)
        }
        runningCycle.set(false)
        // After yielding to manual measurement, come back sooner than the full cooldown so
        // the loop resumes promptly once manual measurement is done, instead of the user
        // seeing a full cooldown-length gap in the auto cycle. Otherwise use the
        // user/dev-configurable cooldown (MeasurementConfig.getCycleCooldownMs(), default 3
        // min) read fresh each time so a runtime change takes effect on the very next cycle.
        val delay = if (status == "YIELDED_TO_MANUAL") WORKOUT_RECHECK_MS else MeasurementConfig.getCycleCooldownMs()
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
        try {
            BleOperateManager.getInstance().manualModeHeart(
                ICommandResponse<StartHeartRateRsp> { rsp ->
                    if (done.get()) return@ICommandResponse
                    // Don't gate on rsp.status == RESULT_OK here — a manual heart rate
                    // measurement sends several intermediate callbacks while still measuring,
                    // and not all of them report RESULT_OK. The previous code bailed out via
                    // finishWithStop() on the first non-OK response, before a real reading
                    // ever arrived — which is why HR consistently failed while every other
                    // vital (none of which gate on status) succeeded on the same connection.
                    // Just wait for a genuine value like SpO2/Stress/BP/HRV do; let
                    // MEASURE_TIMEOUT_MS below handle the case where none ever comes.
                    val value = if (rsp.getHeartRate() > 0) rsp.getHeartRate() else rsp.getValue()
                    Log.d(TAG, "measureHeartRate: status=${rsp.status} heartRate=${rsp.getHeartRate()} value=${rsp.getValue()}")
                    if (value > 0 && done.compareAndSet(false, true)) {
                        persist(Vital.HEART_RATE, cycleId, value.toDouble()) {
                            repository.insertHeartRate(value, cycleId, "auto_cycle")
                        }
                        finishWithStop()
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
            if (done.compareAndSet(false, true)) finishWithStop()
        }, MEASURE_TIMEOUT_MS)
    }

    private fun measureSpo2(cycleId: Long, onDone: () -> Unit) {
        if (!MeasurementCoordinator.tryAcquire(OWNER)) { onDone(); return }
        val done = AtomicBoolean(false)
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
        }, MEASURE_TIMEOUT_MS)
    }

    private fun measureStress(cycleId: Long, onDone: () -> Unit) {
        if (!MeasurementCoordinator.tryAcquire(OWNER)) { onDone(); return }
        val done = AtomicBoolean(false)
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
        }, MEASURE_TIMEOUT_MS)
    }

    private fun measureBloodPressure(cycleId: Long, onDone: () -> Unit) {
        if (!MeasurementCoordinator.tryAcquire(OWNER)) { onDone(); return }
        val done = AtomicBoolean(false)
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
        }, MEASURE_TIMEOUT_MS)
    }

    // manualModeHrv has no built-in zero-filtering (unlike HR/SpO2/BP/Stress), so it's
    // applied here — same pattern, just checking getHrv() first (see comment below).
    private fun measureHrv(cycleId: Long, onDone: () -> Unit) {
        if (!MeasurementCoordinator.tryAcquire(OWNER)) { onDone(); return }
        Log.d(TAG, "measureHrv: starting (timeout ${HRV_MEASURE_TIMEOUT_MS}ms)")
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
        handler.postDelayed({
            if (done.compareAndSet(false, true)) {
                Log.w(TAG, "measureHrv: timed out after ${HRV_MEASURE_TIMEOUT_MS}ms")
                finishWithStop()
            }
        }, HRV_MEASURE_TIMEOUT_MS)
    }

    // Live single temperature measurement via the SDK's dedicated manualTemperature() API —
    // the same call the manual "Measure Now" path (BlePlugin.syncManualTemperature) uses.
    // The raw value is degrees Celsius × 10 (365 → 36.5 °C), matching the scaling the SDK's
    // TemperatureOnceEntity uses. Like HRV, don't gate on status: intermediate callbacks
    // don't all report RESULT_OK, so that would abort before a real reading arrives.
    private fun measureTemperature(cycleId: Long, onDone: () -> Unit) {
        if (!MeasurementCoordinator.tryAcquire(OWNER)) { onDone(); return }
        val done = AtomicBoolean(false)
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
        handler.postDelayed({
            if (done.compareAndSet(false, true)) {
                Log.w(TAG, "measureTemperature: timed out after ${TEMP_MEASURE_TIMEOUT_MS}ms")
                finishWithStop()
            }
        }, TEMP_MEASURE_TIMEOUT_MS)
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
                EventBus.getDefault().post(NewReadingEvent(vital, id, cycleId, System.currentTimeMillis(), primaryValue))
            } catch (e: Exception) {
                Log.e(TAG, "persist($vital) failed", e)
            }
        }
    }
}