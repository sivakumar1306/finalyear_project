package com.medxai.qring_flutter

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonArray
import com.medxai.qring_flutter.data.MeasurementConfig
import com.medxai.qring_flutter.data.ReadingRepository
import com.medxai.qring_flutter.data.Vital
import com.medxai.qring_flutter.events.NewReadingEvent
import com.oudmon.ble.base.bluetooth.BleOperateManager
import com.oudmon.ble.base.communication.ICommandResponse
import com.oudmon.ble.base.communication.entity.BleStepDetails
import com.oudmon.ble.base.communication.rsp.BaseRspCmd
import com.oudmon.ble.base.communication.rsp.StartHeartRateRsp
import kotlinx.coroutines.launch
import org.greenrobot.eventbus.EventBus
import java.util.concurrent.atomic.AtomicBoolean

// Continuously round-robins Steps -> HR -> SpO2 -> Stress -> BP (HRV/Temperature skipped
// while disabled) with a 1-minute cooldown between full cycles, persisting every reading
// to Room and publishing a NewReadingEvent for future analyzer modules. Driven by
// BleConnectionService.onCreate()/onDestroy() — never runs standalone.
object MeasurementLoopManager {
    private const val TAG = "MeasurementLoop"
    private const val CYCLE_COOLDOWN_MS = 60_000L
    private const val DISCONNECTED_RECHECK_MS = 8_000L
    private const val WORKOUT_RECHECK_MS = 15_000L
    private const val MEASURE_TIMEOUT_MS = 60_000L
    // Gap enforced after sending a "stop" command (success or timeout) before the next
    // vital's "start" command goes out. Without this, back-to-back start-stop-start
    // commands with no settle time can leave the ring's firmware stuck mid-measurement
    // (observed in testing: continuous LED blink, no further one-click measurement
    // possible until the ring was power-cycled).
    private const val POST_STOP_SETTLE_MS = 2_000L
    private const val OWNER = "loop"

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
        handler.removeCallbacks(cycleRunnable)
        handler.post(cycleRunnable)
    }

    fun onRingDisconnected() {
        // No proactive action needed — an in-flight cycle already checks isConnected between
        // steps and will mark itself ABORTED_DISCONNECT on its own next step.
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
        val connected = try { BleOperateManager.getInstance().isConnected } catch (_: Exception) { false }
        if (!connected) {
            scheduleNext(DISCONNECTED_RECHECK_MS)
            return
        }
        if (MeasurementCoordinator.isWorkoutActive) {
            scheduleNext(WORKOUT_RECHECK_MS)
            return
        }
        if (!runningCycle.compareAndSet(false, true)) return // a cycle is already in flight

        repository.ioScope.launch {
            val cycleId = repository.startCycle()
            handler.post { walkSequence(cycleId, 0) }
        }
    }

    private fun walkSequence(cycleId: Long, index: Int) {
        if (index >= sequence.size) {
            finishCycle(cycleId, "COMPLETED", null)
            return
        }
        val connected = try { BleOperateManager.getInstance().isConnected } catch (_: Exception) { false }
        if (!connected) {
            // Deliberately restart at HEART_RATE on the next cycle rather than resuming here.
            finishCycle(cycleId, "ABORTED_DISCONNECT", sequence[index].name)
            return
        }
        if (MeasurementCoordinator.isWorkoutActive) {
            finishCycle(cycleId, "SKIPPED_WORKOUT", sequence[index].name)
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
        scheduleNext(CYCLE_COOLDOWN_MS)
    }

    // ── Per-vital measurement, mirroring BlePlugin's proven wait-for-nonzero pattern ──

    private fun measure(vital: Vital, cycleId: Long, onDone: () -> Unit) {
        when (vital) {
            Vital.HEART_RATE -> measureHeartRate(cycleId, onDone)
            Vital.SPO2 -> measureSpo2(cycleId, onDone)
            Vital.STRESS -> measureStress(cycleId, onDone)
            Vital.BLOOD_PRESSURE -> measureBloodPressure(cycleId, onDone)
            Vital.STEPS -> measureSteps(cycleId, onDone)
            Vital.HRV -> measureHrv(cycleId, onDone)
            Vital.TEMPERATURE -> {
                // No reliable one-click SDK measurement exists yet (separate, out-of-scope
                // fix) — this vital stays disabled via MeasurementConfig, so in practice this
                // branch is never reached until that's fixed and the flag is flipped.
                Log.w(TAG, "TEMPERATURE reached in sequence with no implementation — skipping")
                onDone()
            }
        }
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
        try {
            BleOperateManager.getInstance().manualModeHeart(
                ICommandResponse<StartHeartRateRsp> { rsp ->
                    if (done.get()) return@ICommandResponse
                    if (rsp.status == BaseRspCmd.RESULT_OK) {
                        val value = if (rsp.getHeartRate() > 0) rsp.getHeartRate() else rsp.getValue()
                        if (value > 0 && done.compareAndSet(false, true)) {
                            persist(Vital.HEART_RATE, cycleId, value.toDouble()) {
                                repository.insertHeartRate(value, cycleId, "auto_cycle")
                            }
                            finishWithStop()
                        }
                    } else if (done.compareAndSet(false, true)) {
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
            if (done.compareAndSet(false, true)) finishWithStop()
        }, MEASURE_TIMEOUT_MS)
    }

    // Passive fetch (not a blocking manual-mode measurement) of the ring's own cumulative
    // day totals — one snapshot row per cycle. Aggregation mirrors WorkoutService.syncSteps().
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
            val id = insert()
            EventBus.getDefault().post(NewReadingEvent(vital, id, cycleId, System.currentTimeMillis(), primaryValue))
        }
    }
}
