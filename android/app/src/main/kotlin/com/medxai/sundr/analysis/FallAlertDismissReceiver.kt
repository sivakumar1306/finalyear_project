package com.medxai.sundr.analysis

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationManagerCompat

/** "I'm okay" on the fall-alert notification — cancel SMS countdown and dismiss alerts. */
class FallAlertDismissReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        EmergencySmsSender.cancel(context)
        NotificationManagerCompat.from(context).cancel(FallAlertNotifier.NOTIFICATION_ID)
        NotificationManagerCompat.from(context).cancel(EmergencySmsSender.NOTIFICATION_ID)
        NotificationManagerCompat.from(context).cancel(FallPredictionNotifier.NOTIFICATION_ID)
        SafetyLiveUpdate.clear(context)
    }
}
