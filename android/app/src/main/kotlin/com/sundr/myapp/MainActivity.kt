package com.sundr.myapp

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import com.sundr.myapp.analysis.EmergencySmsSender
import com.sundr.myapp.analysis.FallPredictionNotifier
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val TAG = "MainActivity"
        const val PACKAGE_NAME = "com.sundr.myapp"
        const val BLE_METHOD_CHANNEL = "$PACKAGE_NAME/ble"
        const val BLE_EVENT_CHANNEL = "$PACKAGE_NAME/ble_events"
        const val PHONE_MODE_METHOD_CHANNEL = "$PACKAGE_NAME/phone_mode"

        var pendingFallPrediction = false
        var pendingFallPredictionMessage = ""
    }

    private var blePlugin: BlePlugin? = null
    private var phoneModePlugin: PhoneModePlugin? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            if (hasBlePermission()) {
                BleConnectionService.start(this)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start BleConnectionService", e)
        }
        try {
            FallPredictionNotifier.restorePending(this)
            EmergencySmsSender.restoreIfNeeded(this)
            handleIntent(intent)
        } catch (e: Exception) {
            Log.e(TAG, "onCreate restore/intent failed", e)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        try {
            handleIntent(intent)
        } catch (e: Exception) {
            Log.e(TAG, "onNewIntent failed", e)
        }
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.getBooleanExtra(FallPredictionNotifier.EXTRA_FALL_PREDICTION, false) == true) {
            val msg = intent.getStringExtra(FallPredictionNotifier.EXTRA_FALL_PREDICTION_MESSAGE) ?: "A fall-related alert is active."
            FallPredictionNotifier.markPending(this, msg)
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

        try {
            val plugin = BlePlugin(this)
            blePlugin = plugin

            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                BLE_METHOD_CHANNEL
            ).setMethodCallHandler { call, result ->
                try {
                    plugin.handleMethodCall(call, result)
                } catch (e: Exception) {
                    Log.e(TAG, "BLE method ${call.method} crashed", e)
                    try {
                        result.error("NATIVE_CRASH", e.message, null)
                    } catch (_: Exception) {
                        // Result may already be replied — never crash the process for that.
                    }
                }
            }

            EventChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                BLE_EVENT_CHANNEL
            ).setStreamHandler(plugin.eventStreamHandler)

            val phonePlugin = PhoneModePlugin(this)
            phoneModePlugin = phonePlugin

            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                PHONE_MODE_METHOD_CHANNEL
            ).setMethodCallHandler { call, result ->
                try {
                    phonePlugin.handleMethodCall(call, result)
                } catch (e: Exception) {
                    Log.e(TAG, "PhoneMode method ${call.method} crashed", e)
                    try {
                        result.error("NATIVE_CRASH", e.message, null)
                    } catch (_: Exception) {
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "configureFlutterEngine failed", e)
        }
    }

    override fun onDestroy() {
        try {
            blePlugin?.onDestroy()
        } catch (e: Exception) {
            Log.e(TAG, "blePlugin.onDestroy failed", e)
        }
        blePlugin = null
        phoneModePlugin = null
        super.onDestroy()
    }
}
