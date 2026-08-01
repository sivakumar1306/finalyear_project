package com.medxai.qring_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import androidx.core.app.NotificationCompat
import com.medxai.qring_flutter.analysis.SafetyLiveUpdate
import com.medxai.qring_flutter.data.Vital

// Scaffolding for a future analyzer module (e.g. fall detection) to surface an alert to the
// user. Nothing in this codebase calls notifyAnomaly() yet — the actual detection algorithm
// is separate, out-of-scope work. Deliberately a NEW, audible channel: unlike the existing
// silent qring_ble_connection/qring_workout status notifications, an anomaly alert should
// not be silent.
object AlertNotifier {
    private const val CHANNEL_ID = "qring_health_alerts"
    private var nextNotificationId = 2000

    fun ensureChannel(context: Context) {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Health Alerts",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Important alerts about your vitals (e.g. possible fall detected)"
        }
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    fun notifyAnomaly(context: Context, title: String, message: String, vital: Vital) {
        ensureChannel(context)
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val pi = PendingIntent.getActivity(
            context, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification: Notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(message)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(pi)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .build()
        context.getSystemService(NotificationManager::class.java)
            .notify(nextNotificationId++, notification)
        SafetyLiveUpdate.showAnomaly(context, title, message)
    }
}
