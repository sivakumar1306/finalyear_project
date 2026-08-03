package com.medxai.sundr.analysis

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.SmsManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.medxai.sundr.MainActivity
import com.medxai.sundr.data.ReadingRepository
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

/**
 * Sends emergency SMS to **all** saved contacts via [SmsManager] (true background send —
 * does not open the messaging app).
 *
 * On fall / fall-prediction: [schedule] starts a short cancelable countdown so the wearer
 * can stop the blast if they are okay. Manual "Message" from the Fall Detection UI uses
 * [sendNow] with no countdown.
 */
object EmergencySmsSender {
    private const val TAG = "EmergencySms"
    private const val CHANNEL_ID = "qring_emergency_sms"
    const val NOTIFICATION_ID = 2003
    const val COUNTDOWN_SECONDS = 30

    private const val PREFS = "qring_emergency_sms"
    private const val KEY_ACTIVE = "active"
    private const val KEY_SEND_AT = "send_at_ms"
    private const val KEY_REASON = "reason"
    private const val KEY_LAST_SENT_AT = "last_sent_at"
    private const val KEY_LAST_SENT_COUNT = "last_sent_count"
    private const val KEY_LAST_ERROR = "last_error"
    private const val KEY_LAST_CANCELED_AT = "last_canceled_at"

    // Avoid re-spamming contacts if another high-risk reading arrives during/after a send.
    private const val SEND_COOLDOWN_MS = 15 * 60_000L

    const val DEFAULT_MESSAGE =
        "I may have fallen and need help. Please check on me as soon as possible. — Sent by SUNDR Fall Detection"

    private val handler = Handler(Looper.getMainLooper())
    private var tickRunnable: Runnable? = null

    @Volatile
    private var active = false

    @Volatile
    private var sendAtMs = 0L

    @Volatile
    private var reason = ""

    /**
     * Start (or restart) a [COUNTDOWN_SECONDS] countdown. When it expires, SMS is sent to
     * every emergency contact. Safe to call from background threads.
     */
    fun schedule(context: Context, reason: String) {
        val app = context.applicationContext
        val prefs = prefs(app)
        val lastSent = prefs.getLong(KEY_LAST_SENT_AT, 0L)
        val now = System.currentTimeMillis()
        if (lastSent > 0 && now - lastSent < SEND_COOLDOWN_MS) {
            Log.i(TAG, "Skipping schedule — within send cooldown")
            return
        }
        // Already counting down — leave the existing timer so we don't extend forever on
        // repeated vitals spikes; the user still has their original cancel window.
        if (active && sendAtMs > now) {
            Log.i(TAG, "Countdown already active — not restarting")
            updateCountdownNotification(app)
            return
        }

        this.reason = reason
        this.sendAtMs = now + COUNTDOWN_SECONDS * 1000L
        this.active = true
        prefs.edit()
            .putBoolean(KEY_ACTIVE, true)
            .putLong(KEY_SEND_AT, sendAtMs)
            .putString(KEY_REASON, reason)
            .putString(KEY_LAST_ERROR, null)
            .apply()

        ensureChannel(app)
        startTicking(app)
        updateCountdownNotification(app)
        Log.i(TAG, "Scheduled emergency SMS in ${COUNTDOWN_SECONDS}s (reason=$reason)")
    }

    /** Cancel a pending countdown. Does nothing if already sent or idle. */
    fun cancel(context: Context) {
        val app = context.applicationContext
        stopTicking()
        active = false
        sendAtMs = 0L
        reason = ""
        prefs(app).edit()
            .putBoolean(KEY_ACTIVE, false)
            .putLong(KEY_SEND_AT, 0L)
            .putLong(KEY_LAST_CANCELED_AT, System.currentTimeMillis())
            .apply()
        NotificationManagerCompat.from(app).cancel(NOTIFICATION_ID)
        SafetyLiveUpdate.clear(app)
        Log.i(TAG, "Emergency SMS countdown canceled")
    }

    /**
     * Send immediately to all contacts (manual Message action). Bypasses countdown.
     * Returns a status map suitable for MethodChannel JSON.
     */
    fun sendNow(context: Context, message: String = DEFAULT_MESSAGE): Map<String, Any?> {
        val app = context.applicationContext
        // Manual send supersedes any pending countdown.
        stopTicking()
        active = false
        prefs(app).edit().putBoolean(KEY_ACTIVE, false).putLong(KEY_SEND_AT, 0L).apply()
        NotificationManagerCompat.from(app).cancel(NOTIFICATION_ID)
        return performSend(app, message)
    }

    /** Snapshot for Flutter polling — remaining seconds, last send, errors. */
    fun status(context: Context): Map<String, Any?> {
        restoreIfNeeded(context)
        val now = System.currentTimeMillis()
        val remaining = if (active && sendAtMs > now) {
            ((sendAtMs - now + 999) / 1000).toInt().coerceAtLeast(0)
        } else {
            0
        }
        val prefs = prefs(context.applicationContext)
        return mapOf(
            "active" to (active && remaining > 0),
            "secondsRemaining" to remaining,
            "reason" to reason,
            "countdownSeconds" to COUNTDOWN_SECONDS,
            "lastSentAt" to prefs.getLong(KEY_LAST_SENT_AT, 0L),
            "lastSentCount" to prefs.getInt(KEY_LAST_SENT_COUNT, 0),
            "lastError" to prefs.getString(KEY_LAST_ERROR, null),
            "lastCanceledAt" to prefs.getLong(KEY_LAST_CANCELED_AT, 0L),
            "hasPermission" to hasSendSmsPermission(context),
        )
    }

    /** After process death, re-arm countdown from SharedPreferences if still in window. */
    fun restoreIfNeeded(context: Context) {
        if (active) return
        val app = context.applicationContext
        val prefs = prefs(app)
        if (!prefs.getBoolean(KEY_ACTIVE, false)) return
        val at = prefs.getLong(KEY_SEND_AT, 0L)
        val now = System.currentTimeMillis()
        if (at <= now) {
            // Missed the window while process was dead — send immediately.
            reason = prefs.getString(KEY_REASON, "fall") ?: "fall"
            active = false
            prefs.edit().putBoolean(KEY_ACTIVE, false).apply()
            ReadingRepository.getInstance(app).ioScope.launch {
                performSend(app, DEFAULT_MESSAGE)
            }
            return
        }
        sendAtMs = at
        reason = prefs.getString(KEY_REASON, "fall") ?: "fall"
        active = true
        startTicking(app)
        updateCountdownNotification(app)
    }

    private fun startTicking(app: Context) {
        stopTicking()
        val runnable = object : Runnable {
            override fun run() {
                if (!active) return
                val now = System.currentTimeMillis()
                if (now >= sendAtMs) {
                    active = false
                    prefs(app).edit().putBoolean(KEY_ACTIVE, false).putLong(KEY_SEND_AT, 0L).apply()
                    NotificationManagerCompat.from(app).cancel(NOTIFICATION_ID)
                    tickRunnable = null
                    // Room + SmsManager off the main thread.
                    ReadingRepository.getInstance(app).ioScope.launch {
                        performSend(app, DEFAULT_MESSAGE)
                    }
                    return
                }
                updateCountdownNotification(app)
                handler.postDelayed(this, 1000L)
            }
        }
        tickRunnable = runnable
        handler.post(runnable)
    }

    private fun stopTicking() {
        tickRunnable?.let { handler.removeCallbacks(it) }
        tickRunnable = null
    }

    private fun performSend(context: Context, message: String): Map<String, Any?> {
        if (!hasSendSmsPermission(context)) {
            val err = "SEND_SMS permission not granted"
            Log.w(TAG, err)
            prefs(context).edit().putString(KEY_LAST_ERROR, err).apply()
            notifySendResult(context, success = false, count = 0, detail = err)
            return mapOf(
                "ok" to false,
                "sentCount" to 0,
                "failedCount" to 0,
                "error" to err,
            )
        }

        val contacts = try {
            runBlocking { ReadingRepository.getInstance(context).allEmergencyContacts() }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load contacts", e)
            val err = e.message ?: "Failed to load contacts"
            prefs(context).edit().putString(KEY_LAST_ERROR, err).apply()
            return mapOf("ok" to false, "sentCount" to 0, "failedCount" to 0, "error" to err)
        }

        val phones = contacts
            .map { it.phone.trim() }
            .filter { it.isNotEmpty() && it.any { ch -> ch.isDigit() } }
            .distinct()

        if (phones.isEmpty()) {
            val err = "No emergency contacts with phone numbers"
            prefs(context).edit().putString(KEY_LAST_ERROR, err).apply()
            notifySendResult(context, success = false, count = 0, detail = err)
            return mapOf("ok" to false, "sentCount" to 0, "failedCount" to 0, "error" to err)
        }

        val sms = smsManager(context)
        var sent = 0
        var failed = 0
        val errors = mutableListOf<String>()

        for (phone in phones) {
            try {
                val parts = sms.divideMessage(message)
                if (parts.size == 1) {
                    sms.sendTextMessage(phone, null, message, null, null)
                } else {
                    sms.sendMultipartTextMessage(phone, null, parts, null, null)
                }
                sent++
            } catch (e: Exception) {
                failed++
                errors.add("$phone: ${e.message}")
                Log.e(TAG, "SMS failed for $phone", e)
            }
        }

        val errSummary = errors.joinToString("; ").ifEmpty { null }
        prefs(context).edit()
            .putLong(KEY_LAST_SENT_AT, System.currentTimeMillis())
            .putInt(KEY_LAST_SENT_COUNT, sent)
            .putString(KEY_LAST_ERROR, errSummary)
            .apply()

        notifySendResult(
            context,
            success = sent > 0,
            count = sent,
            detail = if (sent > 0) {
                "Alerted $sent emergency contact${if (sent == 1) "" else "s"}"
            } else {
                errSummary ?: "Failed to send SMS"
            },
        )
        SafetyLiveUpdate.showSent(context, sent)

        Log.i(TAG, "SMS send complete: sent=$sent failed=$failed")
        return mapOf(
            "ok" to (sent > 0),
            "sentCount" to sent,
            "failedCount" to failed,
            "error" to errSummary,
        )
    }

    private fun updateCountdownNotification(context: Context) {
        val now = System.currentTimeMillis()
        val remaining = ((sendAtMs - now + 999) / 1000).toInt().coerceAtLeast(0)
        if (remaining <= 0) return

        val launchIntent = PendingIntent.getActivity(
            context,
            10,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val cancelIntent = PendingIntent.getBroadcast(
            context,
            11,
            Intent(context, EmergencySmsCancelReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val reasonLabel = when (reason) {
            "fall" -> "Possible fall detected"
            "prediction" -> "Fall prediction"
            else -> "Emergency alert"
        }
        val body = "$reasonLabel — SMS will be sent to all emergency contacts in $remaining s. " +
            "Tap Cancel if you are okay."

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle("Sending emergency SMS in ${remaining}s")
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(launchIntent)
            .addAction(0, "Cancel SMS", cancelIntent)
            .setProgress(COUNTDOWN_SECONDS, COUNTDOWN_SECONDS - remaining, false)
            .build()

        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS denied — countdown still runs; Flutter UI can still cancel.
        }
        // Mirror the remaining countdown onto the Android 16 live update.
        SafetyLiveUpdate.updateCountdown(context, reason, remaining)
    }

    private fun notifySendResult(context: Context, success: Boolean, count: Int, detail: String) {
        ensureChannel(context)
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle(if (success) "Emergency contacts alerted" else "Emergency SMS failed")
            .setContentText(detail)
            .setStyle(NotificationCompat.BigTextStyle().bigText(detail))
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID + 1, notification)
        } catch (_: SecurityException) {
        }
    }

    private fun ensureChannel(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Emergency SMS",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Countdown and results when SMS is sent to emergency contacts after a fall"
            enableVibration(true)
        }
        manager.createNotificationChannel(channel)
    }

    private fun hasSendSmsPermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.SEND_SMS) ==
            PackageManager.PERMISSION_GRANTED

    @Suppress("DEPRECATION")
    private fun smsManager(context: Context): SmsManager {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(SmsManager::class.java)
        } else {
            SmsManager.getDefault()
        }
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
