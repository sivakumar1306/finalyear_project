package com.sundr.myapp.analysis

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.sundr.myapp.MainActivity
import com.sundr.myapp.R

/**
 * Phase 3 — the first user-visible piece of the fall-risk feature. Fires a local, high-
 * priority notification when [FallMotionDetector] logs a corroborated fall event. Deliberately
 * NOT a full-screen lock-screen overlay and NOT tied to any auto-dial/caregiver push yet —
 * those come later, once the false-positive rate from Phases 1-2's silent logging has
 * actually been measured. This is "notify the user", nothing past that.
 */
object FallAlertNotifier {
    private const val CHANNEL_ID = "qring_fall_alerts"
    const val NOTIFICATION_ID = 2001

    fun notifyFall(
        context: Context,
        confidence: Float,
        corroborationSource: String,
        simulated: Boolean = false,
    ) {
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

        val dismissIntent = PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, FallAlertDismissReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val sourceLabel = when (corroborationSource) {
            "hr_spike" -> "an elevated heart rate"
            "stress_spike" -> "an elevated stress level"
            "spo2_drop" -> "a drop in blood oxygen"
            else -> "your vitals"
        }
        val pct = (confidence * 100).toInt()
        val countdown = EmergencySmsSender.COUNTDOWN_SECONDS
        val autoCall = EmergencyAutoCaller.isEnabled(context)
        val callLine = if (autoCall) {
            " Calling your emergency contact now."
        } else {
            ""
        }

        val smsMessage = EmergencySmsSender.getMessageForReason("fall")
        val body: String
        val bigText: String
        val actionLabel: String
        if (simulated) {
            body = "Demo only — no SMS or call was triggered."
            bigText = "Simulated fall detection corroborated by $sourceLabel. This is a demo — no SMS was scheduled and no call " +
                "was placed.\n\nSMS would say: \"$smsMessage\""
            actionLabel = "Dismiss"
        } else {
            body = "SMS in ${countdown}s: \"$smsMessage\""
            bigText = "A sudden motion consistent with a fall was detected, corroborated by " +
                "$sourceLabel.$callLine SMS will be sent to all " +
                "emergency contacts in $countdown seconds:\n\n\"$smsMessage\"\n\nIf you're okay, tap I'm okay " +
                "to cancel the SMS."
            actionLabel = "I'm okay"
        }

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle(if (simulated) "SIMULATION — possible fall" else "Possible fall detected")
            .setContentText(body)
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(bigText)
            )
            .setSmallIcon(R.drawable.ic_notification)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setContentIntent(launchIntent)
            .addAction(0, actionLabel, dismissIntent)
            .build()

        NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
    }

    private fun ensureChannel(manager: NotificationManager) {
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Fall Alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Notifies you when a possible fall is detected"
            enableVibration(true)
        }
        manager.createNotificationChannel(channel)
    }
}
