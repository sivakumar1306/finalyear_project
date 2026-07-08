package com.medxai.qring_flutter

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Ongoing, colorized notification mirroring the Home screen's Alarms card for whichever mode
 * is active. Focus has no fixed end time (Silent mode stays on until the user changes it), so
 * it gets a live stopwatch counting up. Prayer ties into PhoneModePlugin's real DND auto-off
 * timer, so its countdown reflects exactly when DND will actually turn back off — not a
 * separate fake timer. Base has no ongoing session, so switching to it just cancels this.
 *
 * setUsesChronometer/setChronometerCountDown let the system tick the displayed time itself
 * (no repeating Handler/service needed to redraw the notification every second).
 */
object PhoneModeNotifier {
    private const val CHANNEL_ID = "qring_phone_mode"
    private const val NOTIFICATION_ID = 3001

    // Matches AppTheme.focus / AppTheme.success in the Flutter Alarms card — same accent
    // per mode, so the notification reads as part of the same design system, not a bolt-on.
    private const val COLOR_FOCUS = 0xFFE08A4A.toInt()
    private const val COLOR_PRAYER = 0xFF34D399.toInt()

    fun showFocus(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureChannel(manager)
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle("Focus mode")
            .setContentText("Silent mode is on — notifications are muted")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setColor(COLOR_FOCUS)
            .setColorized(true)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setUsesChronometer(true)
            .setChronometerCountDown(false)
            .setWhen(System.currentTimeMillis())
            .setContentIntent(launchIntent(context))
            .build()
        NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
    }

    fun showPrayer(context: Context, endsAtMs: Long) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureChannel(manager)
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle("Prayer mode")
            .setContentText("Do Not Disturb is on")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setColor(COLOR_PRAYER)
            .setColorized(true)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .setWhen(endsAtMs)
            .setContentIntent(launchIntent(context))
            .build()
        NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
    }

    fun cancel(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }

    private fun launchIntent(context: Context): PendingIntent {
        return PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun ensureChannel(manager: NotificationManager) {
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Alarm Mode",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shows the active Focus/Prayer mode with a live timer"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }
}
