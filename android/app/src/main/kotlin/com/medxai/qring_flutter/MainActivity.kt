package com.medxai.qring_flutter

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import com.medxai.qring_flutter.analysis.FallPredictionNotifier
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val BLE_METHOD_CHANNEL = "com.medxai.qring/ble"
        const val BLE_EVENT_CHANNEL = "com.medxai.qring/ble_events"
        const val PHONE_MODE_METHOD_CHANNEL = "com.medxai.qring/phone_mode"

        // Fall-prediction pending state. Set when a prediction fires (FallPredictionNotifier
        // also persists to SharedPreferences) and/or when the notification is tapped.
        // Home reads via BlePlugin.consumeFallPredictionFlag; cleared only when the user
        // dismisses the banner (clearFallPredictionFlag) — so opening from the launcher
        // after a prediction still surfaces the alert.
        var pendingFallPrediction = false
        var pendingFallPredictionHr = 0
    }

    private lateinit var blePlugin: BlePlugin
    private lateinit var phoneModePlugin: PhoneModePlugin

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Only start the foreground service if Bluetooth permission is already granted.
        // On first launch permissions haven't been requested yet — Flutter's main() handles that
        // and calls startForegroundService via method channel after the user accepts.
        if (hasBlePermission()) {
            BleConnectionService.start(this)
        }
        // Restore any prediction that fired while the app was backgrounded/killed, then
        // overlay intent extras if this launch came from the notification itself.
        FallPredictionNotifier.restorePending(this)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.getBooleanExtra(FallPredictionNotifier.EXTRA_FALL_PREDICTION, false) == true) {
            val hr = intent.getIntExtra(FallPredictionNotifier.EXTRA_FALL_PREDICTION_HR, 0)
            // Keep SharedPreferences in sync so a later cold start still sees the alert
            // until the user dismisses it in-app.
            FallPredictionNotifier.markPending(this, hr)
        }
    }

    private fun hasBlePermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        blePlugin = BlePlugin(this)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BLE_METHOD_CHANNEL
        ).setMethodCallHandler { call, result ->
            blePlugin.handleMethodCall(call, result)
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BLE_EVENT_CHANNEL
        ).setStreamHandler(blePlugin.eventStreamHandler)

        phoneModePlugin = PhoneModePlugin(this)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PHONE_MODE_METHOD_CHANNEL
        ).setMethodCallHandler { call, result ->
            phoneModePlugin.handleMethodCall(call, result)
        }
    }

    override fun onDestroy() {
        blePlugin.onDestroy()
        super.onDestroy()
    }
}
