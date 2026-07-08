package com.medxai.qring_flutter.analysis

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.medxai.qring_flutter.MainActivity

/**
 * Client-demo notifier for the *predictive* (pre-fall) alert, distinct from
 * [FallAlertNotifier] which fires on a corroborated post-fall motion event. This one fires
 * when a vitals spike (real or simulated via BlePlugin.simulateFallPrediction) crosses the
 * high-risk threshold. Tapping the notification or its action both open the app with a flag
 * so the Home screen can surface the "we're concerned" banner before the user drills into
 * the Fall Detection screen — see MainActivity.pendingFallPrediction.
 */
object FallPredictionNotifier {
    private const val CHANNEL_ID = "qring_fall_predictions"
    const val NOTIFICATION_ID = 2002
    const val EXTRA_FALL_PREDICTION = "fall_prediction"
    const val EXTRA_FALL_PREDICTION_HR = "fall_prediction_hr"

    fun notifyPrediction(context: Context, hr: Int) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureChannel(manager)

        val launchIntent = { requestCode: Int ->
            PendingIntent.getActivity(
                context,
                requestCode,
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    putExtra(EXTRA_FALL_PREDICTION, true)
                    putExtra(EXTRA_FALL_PREDICTION_HR, hr)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        val bodyText = "We have detected multiple signs that you might fall down in the " +
            "next 2-3 minutes. Take a seat and contact your caretaker."

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle("You might fall soon...")
            .setContentText(bodyText)
            .setSubText("Fall Prediction")
            .setStyle(NotificationCompat.BigTextStyle().bigText(bodyText))
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setContentIntent(launchIntent(0))
            .addAction(0, "Alert emergency contact", launchIntent(1))
            .build()

        NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
    }

    private fun ensureChannel(manager: NotificationManager) {
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Fall Predictions",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Warns you when your vitals suggest a fall may be about to happen"
            enableVibration(true)
        }
        manager.createNotificationChannel(channel)
    }
}
