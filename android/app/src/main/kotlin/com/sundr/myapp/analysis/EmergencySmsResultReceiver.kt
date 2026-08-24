package com.sundr.myapp.analysis

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Receives per-part SENT / DELIVERED receipts for the emergency SMS dispatched by
 * [EmergencySmsSender] and feeds them back into its receipt ledger, so the app can
 * report honest delivery state instead of fire-and-forget optimism.
 *
 * Registered in AndroidManifest.xml (exported=false — only reachable via the
 * explicit-component PendingIntents the sender creates).
 */
class EmergencySmsResultReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val phone = intent.getStringExtra(EmergencySmsSender.EXTRA_PHONE) ?: return
        val name = intent.getStringExtra(EmergencySmsSender.EXTRA_NAME) ?: ""
        val part = intent.getIntExtra(EmergencySmsSender.EXTRA_PART, 0)
        val total = intent.getIntExtra(EmergencySmsSender.EXTRA_TOTAL, 1)
        val kind = when (intent.action) {
            EmergencySmsSender.ACTION_SMS_SENT -> "sent"
            EmergencySmsSender.ACTION_SMS_DELIVERED -> "delivered"
            else -> return
        }
        EmergencySmsSender.onReceipt(
            context,
            kind = kind,
            phone = phone,
            name = name,
            partIndex = part,
            totalParts = total,
            resultCode = resultCode,
        )
    }
}
