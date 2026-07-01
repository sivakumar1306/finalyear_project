package com.medxai.qring_flutter

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val BLE_METHOD_CHANNEL = "com.medxai.qring/ble"
        const val BLE_EVENT_CHANNEL = "com.medxai.qring/ble_events"
        const val PHONE_MODE_METHOD_CHANNEL = "com.medxai.qring/phone_mode"
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
