package com.medxai.sundr

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON") {
            // Only start service if we have a saved device
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val address = prefs.getString("flutter.device_address", "") ?: ""
            if (address.isNotEmpty()) {
                BleConnectionService.start(context)
            }
        }
    }
}
