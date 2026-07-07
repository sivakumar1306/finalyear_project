package com.medxai.qring_flutter.analysis

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationManagerCompat

/** Handles the "I'm okay" action on the fall-alert notification — just dismisses it. */
class FallAlertDismissReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        NotificationManagerCompat.from(context).cancel(FallAlertNotifier.NOTIFICATION_ID)
    }
}
