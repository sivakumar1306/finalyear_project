package com.medxai.sundr

import android.app.Application
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
import com.oudmon.ble.base.bluetooth.BleOperateManager
import com.oudmon.ble.base.communication.CommandHandle
import com.oudmon.ble.base.communication.Constants
import com.oudmon.ble.base.communication.req.SimpleKeyReq
import com.medxai.sundr.analysis.FallMotionDetector
import com.medxai.sundr.sync.SupabaseSyncManager

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
        get() = prefs.getBoolean("flutter.user_logged_in", false)

    private val checkRunnable = object : Runnable {
        override fun run() {
            val connected = try {
                BleOperateManager.getInstance().isConnected
            } catch (_: Exception) { false }

            // On reconnect: send bind command to finalize
            if (connected && !wasConnected) {
                try {
                    CommandHandle.getInstance().executeReqCmd(
                        SimpleKeyReq(Constants.CMD_BIND_SUCCESS), null
                    )
                } catch (_: Exception) {}
                updateNotification(true)
            } else if (!connected && wasConnected) {
                updateNotification(false)
            }
            wasConnected = connected

            if (!connected && !isConnecting && loggedIn) {
                val address = savedAddress
                if (!address.isNullOrEmpty()) {
                    isConnecting = true
                    try {
                        BleOperateManager.getInstance().connectDirectly(address)
                    } catch (_: Exception) {}
                    // Release connecting flag after window
                    handler.postDelayed({ isConnecting = false }, 15_000L)
                }
            }

            maybeFireSleepReminder()

            handler.postDelayed(this, 8_000L)
        }
    }

    // Alarms & Notifications screen writes the schedule as plain strings (setInt on Dart's
    // shared_preferences round-trips as Long on Android — getInt() here would crash), and
    // this tracks its own native-only "already fired today" date so it fires exactly once
    // per day even though this check runs every 8s.
    private fun maybeFireSleepReminder() {
        try {
            if (!prefs.getBoolean("flutter.sleep_reminder_enabled", false)) return
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
        try {
            BleOperateManager.getInstance(applicationContext as Application)
            BleOperateManager.getInstance().init()
        } catch (_: Exception) {}

        createNotificationChannel()

        // Android 14+ (API 34+) may throw ForegroundServiceStartNotAllowedException
        // if startForeground() is called while the app is not in the foreground
        // (e.g. during early boot before Flutter's runApp). Catch and retry.
        try {
            startForeground(NOTIFICATION_ID, buildNotification(false))
        } catch (_: Exception) {
            handler.postDelayed({
                try {
                    startForeground(NOTIFICATION_ID, buildNotification(false))
                } catch (_: Exception) {}
            }, 5_000L)
        }

        // Start first check after a short delay to let SDK settle
        handler.postDelayed(checkRunnable, 4_000L)

        // Both are no-ops while their respective MeasurementConfig flag is off.
        MeasurementLoopManager.start(applicationContext)
        SupabaseSyncManager.start(applicationContext)

        // Piggybacks on this already-running foreground service rather than starting a
        // second one — see FallMotionDetector kdoc.
        FallMotionDetector.start(applicationContext)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
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
            description = "Keeps your SUNDR ring connected in the background"
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
            .setContentTitle("SUNDR")
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
