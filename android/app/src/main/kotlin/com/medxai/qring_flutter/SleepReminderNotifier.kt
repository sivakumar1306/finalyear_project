package com.medxai.qring_flutter

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Fires once a day at the user's scheduled bedtime. See BleConnectionService's existing 8s
 * reconnect loop, which checks the schedule on every tick using the same always-alive-
 * while-process-alive pattern PhoneModePlugin's Prayer auto-off timer relies on — avoids
 * needing AlarmManager exact-alarm scheduling (and the Android 12+ permission friction
 * that comes with it) for what only needs roughly-on-time accuracy.
 */
object SleepReminderNotifier {
    private const val CHANNEL_ID = "qring_sleep_reminder"
    private const val NOTIFICATION_ID = 4001

    // Matches Sleep's orb color on the Home card (_kOrbSleep in home_screen.dart).
    private const val COLOR = 0xFF6B82D9.toInt()

    fun notify(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureChannel(manager)

        val launchIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle("Time to sleep")
            .setContentText("It's time to wind down and get some rest.")
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(COLOR)
            .setColorized(true)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setContentIntent(launchIntent)
            .build()

        NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
    }

    private fun ensureChannel(manager: NotificationManager) {
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Sleep Reminder",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Reminds you at your scheduled bedtime"
            enableVibration(true)
        }
        manager.createNotificationChannel(channel)
    }
}
