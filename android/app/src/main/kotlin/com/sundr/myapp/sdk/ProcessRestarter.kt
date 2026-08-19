package com.sundr.myapp.sdk

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.util.Log
import com.sundr.myapp.BleConnectionService
import com.sundr.myapp.MainActivity

/**
 * After a fatal main-thread crash, schedules a one-shot relaunch of the BLE
 * foreground service and MainActivity (rate-limited).
 */
object ProcessRestarter {
    private const val TAG = "ProcessRestarter"
    private const val PREFS = "sundr_process_restarter"
    private const val KEY_LAST_MS = "last_relaunch_ms"
    private const val MIN_INTERVAL_MS = 60_000L
    private const val DELAY_MS = 2_500L
    const val ACTION_RELAUNCH = "com.sundr.myapp.action.CRASH_RELAUNCH"

    fun scheduleRelaunch(context: Context, reason: String) {
        val app = context.applicationContext
        val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val last = prefs.getLong(KEY_LAST_MS, 0L)
        if (now - last < MIN_INTERVAL_MS) {
            Log.w(TAG, "relaunch suppressed (rate limit): $reason")
            return
        }
        prefs.edit().putLong(KEY_LAST_MS, now).apply()

        CrashStore.record(
            source = "process_relaunch_scheduled",
            message = reason,
            errorType = "ProcessRelaunch"
        )

        try {
            val intent = Intent(app, CrashRelaunchReceiver::class.java).setAction(ACTION_RELAUNCH)
            val pi = PendingIntent.getBroadcast(
                app,
                0x51D0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val am = app.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.setAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                SystemClock.elapsedRealtime() + DELAY_MS,
                pi
            )
            Log.i(TAG, "scheduled relaunch in ${DELAY_MS}ms ($reason)")
        } catch (e: Exception) {
            Log.e(TAG, "failed to schedule relaunch", e)
        }
    }
}

class CrashRelaunchReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != ProcessRestarter.ACTION_RELAUNCH) return
        Log.i("ProcessRestarter", "relaunch firing")
        try {
            BleConnectionService.start(context.applicationContext)
        } catch (e: Exception) {
            Log.e("ProcessRestarter", "service start failed", e)
        }
        try {
            val launch = Intent(context, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
                putExtra("auto_relaunch", true)
            }
            context.startActivity(launch)
        } catch (e: Exception) {
            Log.e("ProcessRestarter", "activity start failed", e)
        }
    }
}
