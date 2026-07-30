package com.medxai.qring_flutter

import android.app.Application
import android.content.pm.ApplicationInfo
import androidx.core.content.ContextCompat
import com.medxai.qring_flutter.analysis.EmergencySmsSender
import com.medxai.qring_flutter.analysis.FallRiskAnalyzer
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

        BleOperateManager.getInstance(this)
        BleOperateManager.getInstance().init()
        // On for `flutter build apk --debug`, off for release — mirrors the SDK sample's
        // BuildConfig.DEBUG gate without requiring the buildConfig Gradle feature.
        BleOperateManager.getInstance().isBleLogEnabled =
            (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

        FallRiskAnalyzer.init(this)
        // If the process died mid-countdown, resume ticking (or send if the window elapsed).
        EmergencySmsSender.restoreIfNeeded(this)
    }
}
