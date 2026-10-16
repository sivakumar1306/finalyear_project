package com.sundr.myapp.analysis

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.sundr.myapp.MainActivity
import com.sundr.myapp.R

/**
 * Android 16 "Live Updates" (promoted ongoing notification) mirror for the safety pipeline.
 *
 * The *detection algorithm* ([FallMotionDetector]) is the trigger: on a corroborated fall it
 * pins this promoted notification to the lock screen / status bar, and it is dismissed via
 * "I'm okay" or a swipe. The prediction and anomaly paths ([FallPredictionNotifier], [AlertNotifier]) post
 * the same surface with their own payloads.
 *
 * Requires targetSdk 36 + POST_PROMOTED_NOTIFICATIONS. Silently no-ops when the device
 * (or the user in Settings) can't promote the notification — the legacy alerts still fire.
 */
object SafetyLiveUpdate {
    private const val CHANNEL_ID = "qring_safety_live"
    const val NOTIFICATION_ID = 2010

    fun showPrediction(context: Context): Boolean {
        return show(
            context = context,
            title = "You might fall soon...",
            text = "Fall risk is elevated. Take a seat and rest until you feel steady.",
            shortText = "Fall risk",
            okAction = true,
        )
    }

    fun showFall(
        context: Context,
        confidencePct: Int,
        simulated: Boolean = false,
    ): Boolean {
        return show(
            context = context,
            title = if (simulated) "SIMULATION — possible fall" else "Possible fall detected",
            text = if (simulated) {
                "Demo only — simulated fall ($confidencePct% confidence)."
            } else {
                "Fall detected ($confidencePct% confidence). Tap I'm okay if you are fine."
            },
            shortText = if (simulated) "Fall demo" else "Fall detected",
            okAction = true,
        )
    }

    fun showAnomaly(context: Context, title: String, message: String): Boolean {
        return show(
            context = context,
            title = title,
            text = message,
            shortText = "Vitals alert",
            okAction = false,
        )
    }

    /** Dismiss the live update (user acknowledged or swiped away). */
    fun clear(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }

    private fun show(
        context: Context,
        title: String,
        text: String,
        shortText: String,
        okAction: Boolean,
        progress: Int = 100,
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.BAKLAVA) return false
        val manager = context.getSystemService(NotificationManager::class.java)
        if (!manager.canPostPromotedNotifications()) return false
        ensureChannel(manager)

        val launchIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val dismissIntent = PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, SafetyLiveUpdateDismissReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val okIntent = if (okAction) {
            PendingIntent.getBroadcast(
                context,
                1,
                Intent(context, FallAlertDismissReceiver::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        } else {
            dismissIntent
        }

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.ProgressStyle().setProgress(progress))
            .setSmallIcon(R.drawable.ic_notification)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShortCriticalText(shortText)
            .setContentIntent(launchIntent)
            .setDeleteIntent(dismissIntent)
            .addAction(0, "I'm okay", okIntent)

        val notification = builder.build()
        notification.flags = notification.flags or Notification.FLAG_PROMOTED_ONGOING
        NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
        return true
    }

    private fun ensureChannel(manager: NotificationManager) {
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Safety Live Updates",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Keeps fall alerts and abnormal vitals visible on the lock screen"
            enableVibration(true)
        }
        manager.createNotificationChannel(channel)
    }
}
