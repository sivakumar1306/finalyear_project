package com.sundr.myapp

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.google.gson.Gson
import com.google.gson.JsonArray
import com.oudmon.ble.base.bluetooth.BleOperateManager
import com.oudmon.ble.base.communication.ICommandResponse
import com.oudmon.ble.base.communication.rsp.StartHeartRateRsp
import com.oudmon.ble.base.communication.entity.BleStepDetails
import com.oudmon.ble.base.communication.rsp.ReadHeartRateRsp
import com.oudmon.ble.base.communication.CommandHandle
import com.oudmon.ble.base.communication.Constants
import com.oudmon.ble.base.communication.req.SimpleKeyReq
import com.oudmon.ble.base.communication.rsp.BaseRspCmd
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean

class WorkoutService : Service() {

    companion object {
        const val NOTIFICATION_ID = 1002
        const val CHANNEL_ID = "qring_workout"
        // Battery: tick every 30s (was 5s). The notification shows mm:ss/h:mm:ss,
        // so refresh only when the displayed minute changes; BLE reads stay on
        // their own 60s/5min/10min gates below.
        private const val TICK_MS = 30_000L
        private const val STEPS_INTERVAL_MS = 60_000L
        private const val HR_INTERVAL_MS = 60_000L
        private const val SPO2_INTERVAL_MS = 300_000L   // 5 min
        private const val BP_INTERVAL_MS   = 600_000L   // 10 min
        // Safety: a forgotten workout must not run (and keep the process + BLE
        // awake) forever. 6h is well beyond any real session.
        private const val MAX_WORKOUT_MS = 6 * 60 * 60 * 1000L

        fun start(context: Context) {
            val intent = Intent(context, WorkoutService::class.java)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, WorkoutService::class.java))
        }
    }

    private val gson = Gson()
    private val handler = Handler(Looper.getMainLooper())
    // Same ForegroundServiceDidNotStopInTime guard as BleConnectionService:
    // never re-post the tick after onDestroy.
    private var destroyed = false

    private val prefs: SharedPreferences by lazy {
        getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    }

    // Dart (WorkoutProvider) writes: workout_category, workout_sport,
    // workout_start_time (long), workout_start_steps/calories (long),
    // workout_start_distance (double). Read defensively: Flutter stores
    // doubles as longs/floats depending on plugin version.
    private fun safeGetDouble(key: String, default: Double): Double {
        return try {
            when (val v = prefs.all[key]) {
                is Number -> v.toDouble()
                is String -> v.toDoubleOrNull() ?: default
                else -> default
            }
        } catch (_: Exception) {
            default
        }
    }

    private val workoutType: String
        get() = prefs.getString("flutter.workout_sport", null)
            ?: prefs.getString("flutter.workout_category", null)
            ?: prefs.getString("flutter.workout_type", null)
            ?: "running"

    private val workoutStartMs: Long
        get() = prefs.getLong("flutter.workout_start_time", System.currentTimeMillis())

    private var lastStepsSyncMs = 0L
    private var lastHrMs = 0L
    private var lastSpo2Ms = 0L
    private var lastBpMs = 0L
    private var lastNotifiedMinute = -1L
    private val spo2InProgress = AtomicBoolean(false)
    private val bpInProgress = AtomicBoolean(false)

    private val tickRunnable = object : Runnable {
        override fun run() {
            if (destroyed) return
            try {
                val now = System.currentTimeMillis()
                val elapsedMs = now - workoutStartMs
                // Auto-stop a leaked workout instead of ticking forever.
                if (elapsedMs >= MAX_WORKOUT_MS) {
                    Log.w("WorkoutService", "auto-stopping leaked workout after 6h")
                    try {
                        prefs.edit()
                            .remove("flutter.workout_active")
                            .remove("flutter.workout_type")
                            .remove("flutter.workout_start_time")
                            .remove("flutter.workout_start_steps")
                            .remove("flutter.workout_start_calories")
                            .remove("flutter.workout_start_distance")
                            .apply()
                    } catch (_: Exception) {}
                    stopSelf()
                    return
                }
                // Notification text only changes once per minute — rewriting it
                // every tick wakes SystemUI for no visible benefit.
                val minute = elapsedMs / 60_000L
                if (minute != lastNotifiedMinute) {
                    lastNotifiedMinute = minute
                    updateNotification(workoutType, elapsedMs)
                }

                if (now - lastStepsSyncMs >= STEPS_INTERVAL_MS) {
                    lastStepsSyncMs = now
                    try { syncSteps() } catch (_: Exception) {}
                }
                if (now - lastHrMs >= HR_INTERVAL_MS) {
                    lastHrMs = now
                    try { readLatestHr() } catch (_: Exception) {}
                }
                if (elapsedMs >= SPO2_INTERVAL_MS && now - lastSpo2Ms >= SPO2_INTERVAL_MS) {
                    if (spo2InProgress.compareAndSet(false, true)) {
                        lastSpo2Ms = now
                        try { measureSpo2() } catch (_: Exception) {
                            spo2InProgress.set(false)
                        }
                    }
                }
                if (elapsedMs >= BP_INTERVAL_MS && now - lastBpMs >= BP_INTERVAL_MS) {
                    if (!spo2InProgress.get() && bpInProgress.compareAndSet(false, true)) {
                        lastBpMs = now
                        try { measureBp() } catch (_: Exception) {
                            bpInProgress.set(false)
                        }
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("WorkoutService", "tick failed", e)
            } finally {
                if (!destroyed) handler.postDelayed(this, TICK_MS)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()

        MeasurementCoordinator.isWorkoutActive = true
        createNotificationChannel()
        val elapsed = System.currentTimeMillis() - workoutStartMs
        try {
            startForeground(NOTIFICATION_ID, buildNotification(workoutType, elapsed))
        } catch (e: Exception) {
            // startForeground can throw SecurityException or InvalidForegroundServiceTypeException
            // on some devices. Clear workout keys so the app doesn't stay locked in "workout
            // active" mode after a restart, then stop without crashing the process.
            prefs.edit()
                .remove("flutter.workout_active")
                .remove("flutter.workout_type")
                .remove("flutter.workout_start_time")
                .remove("flutter.workout_start_steps")
                .remove("flutter.workout_start_calories")
                .remove("flutter.workout_start_distance")
                .apply()
            stopSelf()
            return
        }

        com.sundr.myapp.sdk.BleSdkLifecycle.ensureInitialized(applicationContext)

        handler.postDelayed(tickRunnable, TICK_MS)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        destroyed = true
        handler.removeCallbacksAndMessages(null)
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {}
        MeasurementCoordinator.isWorkoutActive = false
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Active Workout",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Shows your active workout status"
            setShowBadge(false)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(type: String, elapsedMs: Long): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pi = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val label = type.replaceFirstChar { it.uppercase(Locale.ROOT) }
        val elapsed = formatElapsed(elapsedMs)
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("$label • $elapsed")
            .setContentText("Workout in progress — tap to open")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(pi)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun updateNotification(type: String, elapsedMs: Long) {
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, buildNotification(type, elapsedMs))
    }

    private fun formatElapsed(ms: Long): String {
        val totalSeconds = ms / 1000
        val h = totalSeconds / 3600
        val m = (totalSeconds % 3600) / 60
        val s = totalSeconds % 60
        return if (h > 0) {
            String.format(Locale.ROOT, "%d:%02d:%02d", h, m, s)
        } else {
            String.format(Locale.ROOT, "%02d:%02d", m, s)
        }
    }

    private fun syncSteps() {
        // Best-effort periodic read: skip the tick when a measurement owns the
        // shared SDK slot instead of firing a colliding command (vendor NPE).
        if (!MeasurementCoordinator.tryAcquireRead()) return
        try {
            Log.d("WorkoutService", "sdk> getTodayStepDetail (workout)")
            CommandHandle.getInstance().executeReqCmd(
                SimpleKeyReq(Constants.CMD_GET_STEP_TODAY),
                ICommandResponse<BaseRspCmd> { _ ->
                    BleOperateManager.getInstance().getTodayStepDetail(
                        object : BleOperateManager.HealthDataCallback<List<BleStepDetails>> {
                            override fun onSuccess(data: List<BleStepDetails>?) {
                                MeasurementCoordinator.releaseRead()
                                if (data == null) return
                                val json = gson.toJson(data)
                                val arr = gson.fromJson(json, JsonArray::class.java) ?: return
                                var totalSteps = 0
                                var totalCalRaw = 0
                                var totalDist = 0.0
                                for (el in arr) {
                                    val obj = el.asJsonObject
                                    // f = walk steps; runSteps may carry running sessions.
                                    totalSteps += (obj.get("f")?.asInt ?: 0) +
                                        (obj.get("runSteps")?.asInt ?: 0)
                                    totalCalRaw += obj.get("e")?.asInt ?: 0  // calories raw (小卡)
                                    totalDist += obj.get("g")?.asDouble ?: 0.0
                                }
                                val totalCal = totalCalRaw / 1000
                                val baseSteps = prefs.getLong("flutter.workout_start_steps", 0L).toInt()
                                val baseCal = prefs.getLong("flutter.workout_start_calories", 0L).toInt()
                                val baseDist = safeGetDouble("flutter.workout_start_distance", 0.0)
                                prefs.edit()
                                    .putLong("flutter.workout_current_steps", maxOf(0, totalSteps - baseSteps).toLong())
                                    .putLong("flutter.workout_current_calories", maxOf(0, totalCal - baseCal).toLong())
                                    .putString("flutter.workout_current_distance", maxOf(0.0, totalDist - baseDist).toString())
                                    .apply()
                            }
                            override fun onError(code: Int, message: String?) {
                                MeasurementCoordinator.releaseRead()
                            }
                        }
                    )
                }
            )
        } catch (_: Exception) {
            MeasurementCoordinator.releaseRead()
        }
    }

    private fun readLatestHr() {
        // Best-effort periodic read: skip the tick when a measurement owns the
        // shared SDK slot instead of firing a colliding command (vendor NPE).
        if (!MeasurementCoordinator.tryAcquireRead()) return
        try {
            Log.d("WorkoutService", "sdk> getTodayHeartRate (workout)")
            BleOperateManager.getInstance().getTodayHeartRate(
                object : BleOperateManager.HealthDataCallback<ReadHeartRateRsp> {
                    override fun onSuccess(data: ReadHeartRateRsp?) {
                        MeasurementCoordinator.releaseRead()
                        if (data == null) return
                        val json = gson.toJson(data)
                        val obj = gson.fromJson(json, com.google.gson.JsonObject::class.java) ?: return
                        val arr = obj.get("e")?.asJsonArray ?: return
                        var latest = 0
                        for (el in arr) {
                            val v = try { el.asInt } catch (_: Exception) { 0 }
                            // Day-array slots hold raw bytes: 0 = no data, 0xFF can appear as
                            // an invalid sentinel, so a bare v > 0 check let 255 through.
                            if (com.sundr.myapp.data.VitalRanges.isValidBpm(v)) latest = v
                        }
                        if (latest > 0) {
                            prefs.edit().putLong("flutter.workout_latest_hr", latest.toLong()).apply()
                        }
                    }
                    override fun onError(code: Int, message: String?) {
                        MeasurementCoordinator.releaseRead()
                    }
                }
            )
        } catch (_: Exception) {
            MeasurementCoordinator.releaseRead()
        }
    }

    private fun measureSpo2() {
        if (!MeasurementCoordinator.tryAcquire("workout")) {
            spo2InProgress.set(false)
            return
        }
        try {
            BleOperateManager.getInstance().manualModeSpO2(
                ICommandResponse<StartHeartRateRsp> { rsp ->
                    val spo2 = if (rsp.getBloodOxygen() > 0) rsp.getBloodOxygen() else rsp.getValue()
                    if (spo2 > 0) {
                        prefs.edit().putLong("flutter.workout_latest_spo2", spo2.toLong()).apply()
                    }
                    MeasurementCoordinator.release("workout")
                    spo2InProgress.set(false)
                },
                false
            )
            // Timeout in case measurement never completes
            handler.postDelayed({
                MeasurementCoordinator.release("workout")
                spo2InProgress.set(false)
            }, 65_000L)
        } catch (_: Exception) {
            MeasurementCoordinator.release("workout")
            spo2InProgress.set(false)
        }
    }

    private fun measureBp() {
        if (!MeasurementCoordinator.tryAcquire("workout")) {
            bpInProgress.set(false)
            return
        }
        try {
            BleOperateManager.getInstance().manualModeBP(
                ICommandResponse<StartHeartRateRsp> { rsp ->
                    val sbp = rsp.getSbp()
                    val dbp = rsp.getDbp()
                    if (sbp > 0 && dbp > 0) {
                        prefs.edit()
                            .putLong("flutter.workout_latest_sbp", sbp.toLong())
                            .putLong("flutter.workout_latest_dbp", dbp.toLong())
                            .apply()
                    }
                    MeasurementCoordinator.release("workout")
                    bpInProgress.set(false)
                },
                false
            )
            handler.postDelayed({
                MeasurementCoordinator.release("workout")
                bpInProgress.set(false)
            }, 65_000L)
        } catch (_: Exception) {
            MeasurementCoordinator.release("workout")
            bpInProgress.set(false)
        }
    }
}
