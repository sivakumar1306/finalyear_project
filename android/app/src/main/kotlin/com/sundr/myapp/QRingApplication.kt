package com.sundr.myapp

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import com.sundr.myapp.analysis.EmergencySmsSender
import com.sundr.myapp.analysis.FallRiskAnalyzer
import com.sundr.myapp.sdk.BleSdkLifecycle
import com.sundr.myapp.sdk.CrashStore
import com.sundr.myapp.sdk.ProcessRestarter
import com.oudmon.ble.base.bluetooth.BleAction

/**
 * Registers the SDK's required in-app broadcast receiver before anything else touches
 * BleOperateManager. Without this, onServiceDiscovered() never fires, so large-data/file
 * syncs (temperature, sleep, blood oxygen, ...) silently never initialize.
 * See sdk_ring_external_access_en.pdf §3.1.
 */
class QRingApplication : Application() {

    companion object {
        const val CHANNEL_COMPANION_ALERTS = "companion_alerts"
    }

    override fun onCreate() {
        super.onCreate()

        CrashStore.init(this)
        installUncaughtHandler()
        ensureCompanionAlertChannel()

        try {
            ContextCompat.registerReceiver(
                applicationContext,
                QRingBluetoothReceiver(),
                BleAction.getIntentFilter(),
                ContextCompat.RECEIVER_NOT_EXPORTED
            )

            ContextCompat.registerReceiver(
                applicationContext,
                QRingSystemBluetoothReceiver(),
                BleAction.getDeviceIntentFilter(),
                ContextCompat.RECEIVER_EXPORTED
            )
        } catch (e: Exception) {
            Log.e("SundrApp", "BLE receiver registration failed", e)
            CrashStore.record("receiver_register", e)
        }

        BleSdkLifecycle.ensureInitialized(this)

        try {
            FallRiskAnalyzer.init(this)
            EmergencySmsSender.restoreIfNeeded(this)
        } catch (e: Exception) {
            Log.e("SundrApp", "Fall/SMS restore init failed", e)
            CrashStore.record("fall_sms_init", e)
        }
    }

    /**
     * Channel for FCM companion alerts (send-emergency-alert edge function sets
     * android.notification.channel_id = "companion_alerts"). Must exist before the first
     * background FCM notification arrives, so it is created at process start.
     */
    private fun ensureCompanionAlertChannel() {
        try {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (manager.getNotificationChannel(CHANNEL_COMPANION_ALERTS) != null) return
            val channel = NotificationChannel(
                CHANNEL_COMPANION_ALERTS,
                "Companion emergency alerts",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description =
                    "Alerts when a friend who listed you as their emergency contact needs help"
                enableVibration(true)
            }
            manager.createNotificationChannel(channel)
        } catch (e: Exception) {
            Log.e("SundrApp", "companion alert channel creation failed", e)
        }
    }

    private fun installUncaughtHandler() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            Log.e("SundrCrash", "Uncaught on ${thread.name}", throwable)
            try {
                CrashStore.record("uncaught:${thread.name}", throwable)
            } catch (_: Exception) {
            }

            val isMain = thread == Looper.getMainLooper().thread
            if (isMain) {
                try {
                    ProcessRestarter.scheduleRelaunch(this, "main:${throwable.javaClass.simpleName}")
                } catch (_: Exception) {
                }
                previous?.uncaughtException(thread, throwable)
            }
            // Background: already logged — swallow so BLE callbacks don't take the UI down.
        }
    }
}
