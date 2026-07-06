package com.medxai.qring_flutter

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
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

    companion object {
        // TESTING: Prayer mode auto-turns DND back off after this long. Easy to
        // change later once the real duration is known.
        //
        // This MUST be a process-wide Handler/companion-object timer, not a
        // Dart-side Timer — a Dart Timer lives in the Flutter engine's isolate,
        // which Android can destroy when the Activity is closed/swiped away,
        // even though this app's foreground service (BleConnectionService) keeps
        // the process itself alive. A Handler posted to the main Looper survives
        // exactly as long as the process does, matching how the measurement loop
        // already survives app closure.
        private const val PRAYER_DND_AUTO_OFF_MS = 60_000L
        private val handler = Handler(Looper.getMainLooper())
        private var pendingDndOff: Runnable? = null
    }

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
                // Any explicit call cancels a pending auto-off — either we're
                // turning DND off ourselves already, or re-enabling it fresh
                // (Prayer re-selected — restart the countdown, don't stack timers).
                pendingDndOff?.let { handler.removeCallbacks(it) }
                pendingDndOff = null
                notificationManager.setInterruptionFilter(
                    if (enabled) NotificationManager.INTERRUPTION_FILTER_PRIORITY
                    else NotificationManager.INTERRUPTION_FILTER_ALL
                )
                if (enabled && (call.argument<Boolean>("autoOffAfterOneMinute") ?: false)) {
                    val runnable = Runnable {
                        try {
                            notificationManager.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL)
                        } catch (_: Exception) {}
                    }
                    pendingDndOff = runnable
                    handler.postDelayed(runnable, PRAYER_DND_AUTO_OFF_MS)
                }
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
