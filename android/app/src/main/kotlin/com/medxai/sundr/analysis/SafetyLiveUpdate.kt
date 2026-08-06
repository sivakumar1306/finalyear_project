package com.medxai.sundr.analysis

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.medxai.sundr.MainActivity
import com.medxai.sundr.R

/**
 * Android 16 "Live Updates" (promoted ongoing notification) mirror for the safety pipeline.
 *
 * The *detection algorithm* ([FallMotionDetector]) is the trigger: on a corroborated fall it
 * pins this promoted notification to the lock screen / status bar, [EmergencySmsSender] ticks
 * the SMS countdown on it every second, and it is dismissed via "I'm okay", "Cancel SMS", or
 * a swipe. The prediction and anomaly paths ([FallPredictionNotifier], [AlertNotifier]) post
 * the same surface with their own payloads.
 *
 * Requires targetSdk 36 + POST_PROMOTED_NOTIFICATIONS. Silently no-ops when the device
 * (or the user in Settings) can't promote the notification — the legacy alerts still fire.
 */
object SafetyLiveUpdate {
    private const val CHANNEL_ID = "qring_safety_live"
    const val NOTIFICATION_ID = 2010

    fun showPrediction(context: Context, countdownSeconds: Int) {
        show(
            context = context,
            title = "You might fall soon...",
            text = "Fall risk is elevated. SMS will be sent to your emergency contacts in " +
                "$countdownSeconds seconds unless you cancel.",
            shortText = "Fall risk",
            okAction = true,
        )
    }

    fun showFall(
        context: Context,
        confidencePct: Int,
        countdownSeconds: Int,
        autoCall: Boolean,
        simulated: Boolean = false,
    ) {
        val callLine = if (autoCall) " Calling your emergency contact now." else ""
        show(
            context = context,
            title = if (simulated) "SIMULATION — possible fall" else "Possible fall detected",
            text = if (simulated) {
                "Demo only — no SMS or call was triggered."
            } else {
                "Confidence $confidencePct% — SMS in ${countdownSeconds}s.$callLine"
            },
            shortText = if (simulated) "Fall demo" else "Fall detected",
            okAction = true,
        )
    }

    fun showAnomaly(context: Context, title: String, message: String) {
        show(
            context = context,
            title = title,
            text = message,
            shortText = "Vitals alert",
            okAction = false,
        )
    }

    /** Tick the SMS countdown on the live update — called every second by [EmergencySmsSender]. */
    fun updateCountdown(
        context: Context,
        reason: String,
        remainingSeconds: Int,
        totalSeconds: Int = EmergencySmsSender.COUNTDOWN_SECONDS,
    ) {
        val title = when (reason) {
            "fall" -> "Possible fall detected"
            "prediction" -> "Fall prediction"
            else -> "Emergency alert"
        }
        val pct = ((remainingSeconds.toFloat() / totalSeconds.coerceAtLeast(1)) * 100).toInt().coerceIn(0, 100)
        show(
            context = context,
            title = title,
            text = "SMS to emergency contacts in $remainingSeconds s — tap I'm okay to cancel.",
            shortText = "SMS in ${remainingSeconds}s",
            okAction = true,
            progress = pct,
        )
    }

    /** Flip the live update to the SMS result once the countdown has fired. */
    fun showSent(context: Context, sentCount: Int) {
        show(
            context = context,
            title = if (sentCount > 0) "Emergency SMS sent" else "Emergency SMS failed",
            text = if (sentCount > 0) {
                "Alerted $sentCount emergency contact${if (sentCount == 1) "" else "s"}."
            } else {
                "Could not send SMS — open the app for details."
            },
            shortText = if (sentCount > 0) "SMS sent" else "SMS failed",
            okAction = true,
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
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.BAKLAVA) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (!manager.canPostPromotedNotifications()) return
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
