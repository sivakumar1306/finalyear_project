package com.medxai.qring_flutter.analysis

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationManagerCompat

/**
 * Notification action "Cancel SMS" — aborts the emergency SMS countdown.
 * Also used by the fall-alert "I'm okay" path via [FallAlertDismissReceiver].
 */
class EmergencySmsCancelReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        EmergencySmsSender.cancel(context)
        // Also drop the original fall / prediction notifications so the tray is clean.
        NotificationManagerCompat.from(context).cancel(FallAlertNotifier.NOTIFICATION_ID)
        NotificationManagerCompat.from(context).cancel(FallPredictionNotifier.NOTIFICATION_ID)
        SafetyLiveUpdate.clear(context)
    }
}
