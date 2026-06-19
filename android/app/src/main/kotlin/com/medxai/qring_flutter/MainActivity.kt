package com.medxai.qring_flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val BLE_METHOD_CHANNEL = "com.medxai.qring/ble"
        const val BLE_EVENT_CHANNEL = "com.medxai.qring/ble_events"
    }

    private lateinit var blePlugin: BlePlugin

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
    }

    override fun onDestroy() {
        blePlugin.onDestroy()
        super.onDestroy()
    }
}
