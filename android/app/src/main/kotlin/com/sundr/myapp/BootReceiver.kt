package com.sundr.myapp

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.sundr.myapp.sdk.CrashStore

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
                intent.action != "android.intent.action.QUICKBOOT_POWERON"
            ) {
                return
            }
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val address = try {
                prefs.getString("flutter.device_address", "") ?: ""
            } catch (e: Exception) {
                Log.e("BootReceiver", "prefs read failed", e)
                ""
            }
            if (address.isNotEmpty()) {
                BleConnectionService.start(context)
            }
        } catch (e: Exception) {
            Log.e("BootReceiver", "onReceive failed", e)
            try {
                CrashStore.init(context.applicationContext)
                CrashStore.record("boot_receiver", e)
            } catch (_: Exception) {
            }
        }
    }
}
