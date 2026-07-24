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
 * high-risk threshold.
 *
 * Pending state is written as soon as the prediction fires (SharedPreferences +
 * MainActivity companion fields), not only when the notification is tapped — so opening
 * the app from the launcher still surfaces the Home banner. Cleared only when the user
 * dismisses the banner via [clearPending].
 */
object FallPredictionNotifier {
    private const val CHANNEL_ID = "qring_fall_predictions"
    const val NOTIFICATION_ID = 2002
    const val EXTRA_FALL_PREDICTION = "fall_prediction"
    const val EXTRA_FALL_PREDICTION_HR = "fall_prediction_hr"

    private const val PREFS = "qring_fall_prediction"
    private const val KEY_PENDING = "pending"
    private const val KEY_HR = "hr"

    fun notifyPrediction(context: Context, hr: Int) {
        // Persist immediately so a cold start / launcher open still picks this up —
        // previously the flag lived only on the notification PendingIntent extras.
        markPending(context, hr)

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

        val countdown = EmergencySmsSender.COUNTDOWN_SECONDS
        val bodyText = "We have detected multiple signs that you might fall down in the " +
            "next 2-3 minutes. SMS will be sent to all emergency contacts in $countdown " +
            "seconds unless you cancel."

        val cancelSmsIntent = PendingIntent.getBroadcast(
            context,
            2,
            Intent(context, EmergencySmsCancelReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

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
            .addAction(0, "Cancel SMS", cancelSmsIntent)
            .addAction(0, "Open app", launchIntent(1))
            .build()

        NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
    }

    /** Write pending prediction so any subsequent app open can surface the alert. */
    fun markPending(context: Context, hr: Int) {
        MainActivity.pendingFallPrediction = true
        MainActivity.pendingFallPredictionHr = hr
        context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_PENDING, true)
            .putInt(KEY_HR, hr)
            .apply()
    }

    /**
     * Reload persisted pending state into MainActivity companion fields.
     * Safe to call on every cold start / resume check.
     */
    fun restorePending(context: Context) {
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_PENDING, false)) return
        MainActivity.pendingFallPrediction = true
        MainActivity.pendingFallPredictionHr = prefs.getInt(KEY_HR, 0)
    }

    /** User dismissed the in-app banner — stop resurfacing until the next prediction. */
    fun clearPending(context: Context) {
        MainActivity.pendingFallPrediction = false
        MainActivity.pendingFallPredictionHr = 0
        context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_PENDING, false)
            .putInt(KEY_HR, 0)
            .apply()
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
