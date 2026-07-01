package com.medxai.qring_flutter

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges the Focus / Prayer mode toggles to real system state:
 * Focus -> Silent ringer mode, Prayer -> Do Not Disturb.
 *
 * Both require the user to have granted Do Not Disturb access via
 * [Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS] first — Android
 * refuses ringer/notification-policy changes without it.
 */
class PhoneModePlugin(private val context: Context) {

    private val notificationManager: NotificationManager
        get() = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private val audioManager: AudioManager
        get() = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isDndAccessGranted" ->
                result.success(notificationManager.isNotificationPolicyAccessGranted)

            "openDndAccessSettings" -> {
                context.startActivity(
                    Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                )
                result.success(null)
            }

            "setDoNotDisturb" -> {
                if (!notificationManager.isNotificationPolicyAccessGranted) {
                    result.success(false)
                    return
                }
                val enabled = call.argument<Boolean>("enabled") ?: false
                notificationManager.setInterruptionFilter(
                    if (enabled) NotificationManager.INTERRUPTION_FILTER_PRIORITY
                    else NotificationManager.INTERRUPTION_FILTER_ALL
                )
                result.success(true)
            }

            "setSilentMode" -> {
                if (!notificationManager.isNotificationPolicyAccessGranted) {
                    result.success(false)
                    return
                }
                val enabled = call.argument<Boolean>("enabled") ?: false
                audioManager.ringerMode =
                    if (enabled) AudioManager.RINGER_MODE_SILENT
                    else AudioManager.RINGER_MODE_NORMAL
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }
}
