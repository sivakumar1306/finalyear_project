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
            // Battery: don't start the always-on foreground service (and its
            // reconnect backoff loop) at boot when logged out or with no saved
            // ring — otherwise a stale address causes a reconnect storm even
            // though nobody can use the connection.
            val loggedIn = try {
                prefs.getBoolean("flutter.user_logged_in", false)
            } catch (_: ClassCastException) {
                when (val v = prefs.all["flutter.user_logged_in"]) {
                    is Boolean -> v
                    is String -> v.equals("true", ignoreCase = true) || v == "1"
                    is Number -> v.toInt() != 0
                    else -> false
                }
            } catch (_: Exception) {
                false
            }
            if (address.isNotEmpty() && loggedIn) {
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
