package com.medxai.qring_flutter

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
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.oudmon.ble.base.bluetooth.BleOperateManager
import com.oudmon.ble.base.communication.CommandHandle
import com.oudmon.ble.base.communication.Constants
import com.oudmon.ble.base.communication.req.SimpleKeyReq
import com.medxai.qring_flutter.sync.SupabaseSyncManager

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

            if (!connected && !isConnecting) {
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

            handler.postDelayed(this, 8_000L)
        }
    }

    override fun onCreate() {
        super.onCreate()
        try {
            BleOperateManager.getInstance(applicationContext as Application)
            BleOperateManager.getInstance().init()
        } catch (_: Exception) {}

        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification(false))

        // Start first check after a short delay to let SDK settle
        handler.postDelayed(checkRunnable, 4_000L)

        // Both are no-ops while their respective MeasurementConfig flag is off.
        MeasurementLoopManager.start(applicationContext)
        SupabaseSyncManager.start(applicationContext)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        MeasurementLoopManager.stop()
        SupabaseSyncManager.stop()
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Ring Connection",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Keeps your QRing connected in the background"
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
            .setContentTitle("QRing")
            .setContentText(if (connected) "Ring connected" else "Looking for your ring…")
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
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
