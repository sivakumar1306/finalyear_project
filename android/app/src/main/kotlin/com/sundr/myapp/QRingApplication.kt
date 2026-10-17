package com.sundr.myapp

import android.app.Application
import android.content.Context
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
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

    override fun onCreate() {
        super.onCreate()

        CrashStore.init(this)
        installUncaughtHandler()

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
            Log.e("VitalApp", "BLE receiver registration failed", e)
            CrashStore.record("receiver_register", e)
        }

        BleSdkLifecycle.ensureInitialized(this)

        try {
            FallRiskAnalyzer.init(this)
        } catch (e: Exception) {
            Log.e("VitalApp", "Fall analyzer init failed", e)
            CrashStore.record("fall_sms_init", e)
        }
    }

    private fun installUncaughtHandler() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            Log.e("VitalCrash", "Uncaught on ${thread.name}", throwable)
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
