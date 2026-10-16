package com.sundr.myapp.analysis

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationManagerCompat

/** "I'm okay" on the fall-alert notification — dismiss alerts. */
class FallAlertDismissReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        NotificationManagerCompat.from(context).cancel(FallAlertNotifier.NOTIFICATION_ID)
        NotificationManagerCompat.from(context).cancel(FallPredictionNotifier.NOTIFICATION_ID)
        FallPredictionNotifier.clearPending(context)
        SafetyLiveUpdate.clear(context)
    }
}
