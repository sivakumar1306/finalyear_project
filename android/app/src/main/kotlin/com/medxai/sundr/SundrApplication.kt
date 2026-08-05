package com.medxai.sundr

import android.app.Application
import android.content.pm.ApplicationInfo
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import com.medxai.sundr.analysis.EmergencySmsSender
import com.medxai.sundr.analysis.FallRiskAnalyzer
import com.oudmon.ble.base.bluetooth.BleAction
import com.oudmon.ble.base.bluetooth.BleOperateManager

/**
 * Registers the SDK's required in-app broadcast receiver before anything else touches
 * BleOperateManager. Without this, onServiceDiscovered() never fires, so large-data/file
 * syncs (temperature, sleep, blood oxygen, ...) silently never initialize.
 * See sdk_ring_external_access_en.pdf §3.1.
 */
class QRingApplication : Application() {

    override fun onCreate() {
        super.onCreate()

        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            Log.e("SundrCrash", "Uncaught on ${thread.name}", throwable)
            // BLE vendor SDK / sensor / OkHttp worker threads occasionally throw; killing the
            // whole process for those is the main source of "random closes". Keep the process
            // alive for non-main threads and only crash the process for main-thread failures.
            val isMain = thread == Looper.getMainLooper().thread
            if (isMain) {
                previous?.uncaughtException(thread, throwable)
            }
            // Background: already logged — swallow so MeasurementLoop / BLE callbacks don't
            // take the UI down with them.
        }

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
        }

        try {
            BleOperateManager.getInstance(this)
            BleOperateManager.getInstance().init()
            // On for `flutter build apk --debug`, off for release — mirrors the SDK sample's
            // BuildConfig.DEBUG gate without requiring the buildConfig Gradle feature.
            BleOperateManager.getInstance().isBleLogEnabled =
                (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        } catch (e: Exception) {
            Log.e("SundrApp", "BleOperateManager init failed", e)
        }

        try {
            FallRiskAnalyzer.init(this)
            // If the process died mid-countdown, resume ticking (or send if the window elapsed).
            EmergencySmsSender.restoreIfNeeded(this)
        } catch (e: Exception) {
            Log.e("SundrApp", "Fall/SMS restore init failed", e)
        }
    }
}
