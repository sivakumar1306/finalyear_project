package com.medxai.sundr

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import com.medxai.sundr.analysis.EmergencySmsSender
import com.medxai.sundr.analysis.FallPredictionNotifier
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    companion object {
        const val PACKAGE_NAME = "com.medxai.sundr"
        const val BLE_METHOD_CHANNEL = "$PACKAGE_NAME/ble"
        const val BLE_EVENT_CHANNEL = "$PACKAGE_NAME/ble_events"
        const val PHONE_MODE_METHOD_CHANNEL = "$PACKAGE_NAME/phone_mode"

        var pendingFallPrediction = false
        var pendingFallPredictionHr = 0
    }

    private lateinit var blePlugin: BlePlugin
    private lateinit var phoneModePlugin: PhoneModePlugin

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (hasBlePermission()) {
            BleConnectionService.start(this)
        }
        FallPredictionNotifier.restorePending(this)
        EmergencySmsSender.restoreIfNeeded(this)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.getBooleanExtra(FallPredictionNotifier.EXTRA_FALL_PREDICTION, false) == true) {
            val hr = intent.getIntExtra(FallPredictionNotifier.EXTRA_FALL_PREDICTION_HR, 0)
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
