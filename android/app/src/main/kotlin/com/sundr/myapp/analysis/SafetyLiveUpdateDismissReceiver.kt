package com.sundr.myapp.analysis

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** "Dismiss" / swipe-away on the safety live update — clears it without re-posting. */
class SafetyLiveUpdateDismissReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        SafetyLiveUpdate.clear(context)
    }
}
