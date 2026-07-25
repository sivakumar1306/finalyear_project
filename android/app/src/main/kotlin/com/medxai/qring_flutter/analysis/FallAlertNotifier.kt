package com.medxai.qring_flutter.analysis

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.medxai.qring_flutter.MainActivity
import com.medxai.qring_flutter.R

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

    fun notifyFall(context: Context, confidence: Float, corroborationSource: String) {
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

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle("Possible fall detected")
            .setContentText(
                "Confidence $pct% — SMS in ${countdown}s.$callLine Tap I'm okay to cancel SMS."
            )
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    "A sudden motion consistent with a fall was detected, corroborated by " +
                        "$sourceLabel ($pct% confidence).$callLine SMS will be sent to all " +
                        "emergency contacts in $countdown seconds. If you're okay, tap I'm okay " +
                        "to cancel the SMS."
                )
            )
            .setSmallIcon(R.drawable.ic_notification)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setContentIntent(launchIntent)
            .addAction(0, "I'm okay", dismissIntent)
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
