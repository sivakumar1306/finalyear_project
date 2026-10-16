package com.sundr.myapp

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import java.util.Calendar
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.oudmon.ble.base.communication.CommandHandle
import com.oudmon.ble.base.communication.Constants
import com.oudmon.ble.base.communication.req.SimpleKeyReq
import com.sundr.myapp.analysis.FallMotionDetector
import com.sundr.myapp.sdk.BleSdkLifecycle
import com.sundr.myapp.sdk.SdkGuard
import com.sundr.myapp.sync.SupabaseSyncManager

class BleConnectionService : Service() {

    companion object {
        const val NOTIFICATION_ID = 1001
        const val CHANNEL_ID = "qring_ble_connection"

        fun start(context: Context) {
            val intent = Intent(context, BleConnectionService::class.java)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, BleConnectionService::class.java))
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var isConnecting = false
    private var wasConnected = false
    // ForegroundServiceDidNotStopInTime fix: once onDestroy runs, the loop
    // must never re-post itself or the process outlives the stop window.
    private var destroyed = false

    // Battery: exponential backoff for the reconnect/health loop while
    // disconnected, capped at 2 min. Steps: 8s -> 15s -> 30s -> 60s -> 120s.
    // Resets to fast polling as soon as the ring is connected again so a
    // fresh disconnect is still noticed within seconds.
    private var consecutiveDisconnectedTicks = 0
    private val BACKOFF_STEPS_MS = longArrayOf(8_000L, 15_000L, 30_000L, 60_000L, 120_000L)

    // Flutter shared_preferences stores keys with "flutter." prefix
    private val prefs by lazy {
        getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    }

    private val savedAddress: String?
        get() = prefs.getString("flutter.device_address", "")?.takeIf { it.isNotEmpty() }

    // Gates auto-reconnect on being logged in — main.dart writes this on boot and on every
    // Supabase auth state change. Without this, connectDirectly() below fires every 8s as
    // soon as the service starts (which happens at raw app launch, before the user even
    // reaches the login screen), and for a previously-paired ring that isn't in range/bonded
    // this repeatedly pops Android's system BLE pairing dialog on top of the login/signup UI.
    private val loggedIn: Boolean
        get() = safeGetBoolean("flutter.user_logged_in", false)

    // shared_preferences type mismatches (bool stored as long/string) throw ClassCastException
    // on a hard getBoolean — that previously killed the reconnect loop / whole process.
    private fun safeGetBoolean(key: String, default: Boolean): Boolean {
        return try {
            prefs.getBoolean(key, default)
        } catch (_: ClassCastException) {
            try {
                when (val v = prefs.all[key]) {
                    is Boolean -> v
                    is String -> v.equals("true", ignoreCase = true) || v == "1"
                    is Number -> v.toInt() != 0
                    else -> default
                }
            } catch (_: Exception) {
                default
            }
        } catch (_: Exception) {
            default
        }
    }

    private val checkRunnable = object : Runnable {
        override fun run() {
            if (destroyed) return
            try {
                val connected = BleSdkLifecycle.isConnected()

                // Back off reconnect storms while the SDK circuit breaker is open.
                // When connected and stable (was already connected last tick), relax to 30 s
                // to let the CPU sleep longer. While disconnected, back off exponentially
                // (8s -> 120s max) so an out-of-range ring doesn't cost ~10k GATT
                // attempts/night. Sleep-reminder checks piggyback this loop, so a
                // reminder may fire up to 2 min late in the worst case — acceptable.
                val intervalMs = when {
                    SdkGuard.isOpen() -> 30_000L
                    connected && wasConnected -> 30_000L
                    connected -> 8_000L
                    else -> BACKOFF_STEPS_MS[
                        consecutiveDisconnectedTicks.coerceIn(0, BACKOFF_STEPS_MS.lastIndex)
                    ]
                }

                if (connected) {
                    consecutiveDisconnectedTicks = 0
                } else {
                    consecutiveDisconnectedTicks =
                        (consecutiveDisconnectedTicks + 1).coerceAtMost(BACKOFF_STEPS_MS.lastIndex)
                }

                if (connected && !wasConnected) {
                    SdkGuard.run("service.bindSuccess") {
                        CommandHandle.getInstance().executeReqCmd(
                            SimpleKeyReq(Constants.CMD_BIND_SUCCESS), null
                        )
                    }
                    updateNotification(true)
                    SdkGuard.recordSuccess()
                } else if (!connected && wasConnected) {
                    updateNotification(false)
                }
                wasConnected = connected

                val manualConnect = try {
                    BlePlugin.instance?.isManualConnectActive() == true
                } catch (_: Exception) {
                    false
                }
                if (!connected && !isConnecting && loggedIn && !SdkGuard.isOpen() && !manualConnect) {
                    val address = savedAddress
                    if (!address.isNullOrEmpty()) {
                        isConnecting = true
                        BleSdkLifecycle.connectDirectly(address)
                        handler.postDelayed({ isConnecting = false }, 15_000L)
                    }
                }

                maybeFireSleepReminder()
                if (!destroyed) handler.postDelayed(this, intervalMs)
            } catch (e: Exception) {
                android.util.Log.e("BleConnectionService", "checkRunnable failed", e)
                if (destroyed) return
                // Keep the backoff on errors too — a tight 8s error loop is a drain.
                consecutiveDisconnectedTicks =
                    (consecutiveDisconnectedTicks + 1).coerceAtMost(BACKOFF_STEPS_MS.lastIndex)
                handler.postDelayed(
                    this,
                    BACKOFF_STEPS_MS[consecutiveDisconnectedTicks]
                )
            }
        }
    }

    // Alarms & Notifications screen writes the schedule as plain strings (setInt on Dart's
    // shared_preferences round-trips as Long on Android — getInt() here would crash), and
    // this tracks its own native-only "already fired today" date so it fires exactly once
    // per day even though this check runs on the (backed-off) service loop.
    private fun maybeFireSleepReminder() {
        try {
            if (!safeGetBoolean("flutter.sleep_reminder_enabled", false)) return
            val hour = prefs.getString("flutter.sleep_reminder_hour", null)?.toIntOrNull() ?: return
            val minute = prefs.getString("flutter.sleep_reminder_minute", null)?.toIntOrNull() ?: return

            val now = Calendar.getInstance()
            val today = "%04d-%02d-%02d".format(
                now.get(Calendar.YEAR), now.get(Calendar.MONTH), now.get(Calendar.DAY_OF_MONTH)
            )
            if (prefs.getString("sleep_reminder_last_fired_date", "") == today) return

            val scheduled = (now.clone() as Calendar).apply {
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            if (now.before(scheduled)) return

            SleepReminderNotifier.notify(applicationContext)
            prefs.edit().putString("sleep_reminder_last_fired_date", today).apply()
        } catch (_: Exception) {}
    }

    override fun onCreate() {
        super.onCreate()

        createNotificationChannel()

        // startForeground() must be called immediately — before any slow SDK setup — or
        // Android force-kills the app with ForegroundServiceDidNotStartInTimeException if
        // the notification isn't posted within 5 seconds of the service starting.
        //
        // It's also wrapped in try/catch: startForeground() can throw SecurityException /
        // InvalidForegroundServiceTypeException (e.g. a missing FOREGROUND_SERVICE_* manifest
        // permission for a declared foregroundServiceType, or a type Android 14+ rejects at
        // runtime). Without this catch, that exception is unhandled and crashes the whole
        // process on every launch — so on failure we log it and stop the service cleanly
        // instead of taking the app down.
        try {
            startForeground(NOTIFICATION_ID, buildNotification(false))
        } catch (e: Exception) {
            android.util.Log.e("BleConnectionService", "startForeground failed", e)
            stopSelf()
            return
        }

        BleSdkLifecycle.ensureInitialized(applicationContext)

        handler.postDelayed(checkRunnable, 4_000L)

        try {
            MeasurementLoopManager.start(applicationContext)
        } catch (_: Exception) {}
        try {
            SupabaseSyncManager.start(applicationContext)
        } catch (_: Exception) {}
        try {
            FallMotionDetector.start(applicationContext)
        } catch (_: Exception) {}
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
        MeasurementLoopManager.stop()
        SupabaseSyncManager.stop()
        FallMotionDetector.stop()
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Ring Connection",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Keeps your ring connected in the background"
            setShowBadge(false)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(connected: Boolean): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pi = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Vital Monitoring")
            .setContentText(if (connected) "Ring connected" else "Looking for your ring…")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(pi)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun updateNotification(connected: Boolean) {
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, buildNotification(connected))
    }
}
