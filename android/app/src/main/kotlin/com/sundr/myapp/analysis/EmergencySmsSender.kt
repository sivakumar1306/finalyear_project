package com.sundr.myapp.analysis

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.SmsManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.sundr.myapp.MainActivity
import com.sundr.myapp.data.ReadingRepository
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

/**
 * Sends emergency SMS to **all** saved contacts via [SmsManager] (true background send —
 * does not open the messaging app).
 *
 * On fall / fall-prediction: [schedule] starts a short cancelable countdown so the wearer
 * can stop the blast if they are okay. Manual "Message" from the Fall Detection UI uses
 * [sendNow] with no countdown.
 *
 * Part 1 of the alerting plan (docs/sms/emergency-alerting-system.md): every message is
 * dispatched with SENT / DELIVERED result PendingIntents handled by
 * [EmergencySmsResultReceiver], and the final state is written to a per-contact receipt
 * ledger (SharedPreferences JSON). The UI therefore reports honest "sending / sent /
 * delivered / failed" counts instead of optimistic fire-and-forget. The SMS body also
 * carries the wearer's last-known live location as a map link when available.
 */
object EmergencySmsSender {
    private const val TAG = "EmergencySms"
    private const val CHANNEL_ID = "qring_emergency_sms"
    const val NOTIFICATION_ID = 2003
    const val COUNTDOWN_SECONDS = 30

    // Receipt broadcast actions / extras (also used by EmergencySmsResultReceiver).
    const val ACTION_SMS_SENT = "com.sundr.myapp.action.EMERGENCY_SMS_SENT"
    const val ACTION_SMS_DELIVERED = "com.sundr.myapp.action.EMERGENCY_SMS_DELIVERED"
    const val EXTRA_PHONE = "phone"
    const val EXTRA_NAME = "name"
    const val EXTRA_PART = "part"
    const val EXTRA_TOTAL = "total"

    private const val PREFS = "qring_emergency_sms"
    private const val KEY_ACTIVE = "active"
    private const val KEY_SEND_AT = "send_at_ms"
    private const val KEY_REASON = "reason"
    private const val KEY_LAST_SENT_AT = "last_sent_at"
    private const val KEY_LAST_SENT_COUNT = "last_sent_count"
    private const val KEY_LAST_ERROR = "last_error"
    private const val KEY_LAST_CANCELED_AT = "last_canceled_at"

    // Receipt-ledger state.
    private const val KEY_SEND_IN_PROGRESS = "send_in_progress"
    private const val KEY_SEND_STARTED_AT = "send_started_at"
    private const val KEY_PENDING = "pending_receipts_json"
    private const val KEY_REQUEST_CODE = "receipt_request_code"
    private const val KEY_LAST_QUEUED = "last_queued_count"
    private const val KEY_LAST_DELIVERED = "last_delivered_count"
    private const val KEY_LAST_FAILED = "last_failed_count"
    private const val KEY_PER_CONTACT = "last_per_contact_json"

    // Avoid re-spamming contacts if another high-risk reading arrives during/after a send.
    private const val SEND_COOLDOWN_MS = 15 * 60_000L

    // How long we wait for carrier receipts before marking silent contacts "unknown".
    private const val RECEIPT_TIMEOUT_MS = 90 * 1000L

    // Ignore location fixes older than this when building the live-location link.
    private const val LOCATION_MAX_AGE_MS = 30 * 60_000L

    fun getMessageForReason(reason: String, hr: Int? = null): String {
        return when (reason) {
            "fall" -> "We have detected a fall. We have detected that you may have potentially fallen. — Sent by SUNDR Fall Detection"
            "prediction" -> "You might fall soon... We have detected multiple signs that you might fall down in the next 2-3 minutes. Take a seat and contact your caretaker. — Sent by SUNDR Fall Detection"
            "heart_rate" -> "We are concerned ... Your heart rate rose to ${hr ?: "a high"} BPM while you seemed to be in-active for the last 10 minutes. — Sent by SUNDR Fall Detection"
            else -> "I may have fallen and need help. Please check on me as soon as possible. — Sent by SUNDR Fall Detection"
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var tickRunnable: Runnable? = null
    private var watchdogRunnable: Runnable? = null
    private val receiptLock = Any()

    @Volatile
    private var active = false

    @Volatile
    private var sendAtMs = 0L

    @Volatile
    private var reason = ""

    /**
     * Start (or restart) a [COUNTDOWN_SECONDS] countdown. When it expires, SMS is sent to
     * every emergency contact. Safe to call from background threads.
     *
     * Refuses to start when no real emergency contact exists — the countdown must never run
     * against an empty (or fake) contact list. Returns false when it could not start.
     */
    fun schedule(context: Context, reason: String): Boolean {
        val app = context.applicationContext
        val prefs = prefs(app)
        val lastSent = prefs.getLong(KEY_LAST_SENT_AT, 0L)
        val now = System.currentTimeMillis()
        if (lastSent > 0 && now - lastSent < SEND_COOLDOWN_MS) {
            Log.i(TAG, "Skipping schedule — within send cooldown")
            return false
        }
        // Already counting down — leave the existing timer so we don't extend forever on
        // repeated vitals spikes; the user still has their original cancel window.
        if (active && sendAtMs > now) {
            Log.i(TAG, "Countdown already active — not restarting")
            updateCountdownNotification(app)
            return true
        }

        // Block auto-SMS until at least one real contact (with a digit) is saved.
        val hasContact = try {
            runBlocking {
                ReadingRepository.getInstance(app).allEmergencyContacts().any {
                    it.phone.trim().any { ch -> ch.isDigit() }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load contacts before scheduling", e)
            false
        }
        if (!hasContact) {
            val err = "No emergency contacts saved — add one before SMS alerting can work"
            Log.w(TAG, err)
            prefs.edit().putString(KEY_LAST_ERROR, err).apply()
            notifySendResult(app, success = false, count = 0, detail = err)
            return false
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
        return true
    }

    /** Cancel a pending countdown. Does nothing if already sent or idle. */
    fun cancel(context: Context) {
        val app = context.applicationContext
        stopTicking()
        active = false
        sendAtMs = 0L
        reason = ""
        // Countdown canceled before expiry — nothing was dispatched; clear receipt state too.
        clearReceiptState(app)
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
     * Returns a status map suitable for MethodChannel JSON. The returned counts reflect
     * dispatch (queued) — confirmed sent/delivered counts arrive via receipts and are
     * exposed through [status].
     */
    fun sendNow(context: Context, message: String? = null): Map<String, Any?> {
        val app = context.applicationContext
        // Manual send supersedes any pending countdown.
        stopTicking()
        active = false
        prefs(app).edit().putBoolean(KEY_ACTIVE, false).putLong(KEY_SEND_AT, 0L).apply()
        NotificationManagerCompat.from(app).cancel(NOTIFICATION_ID)
        return performSend(app, message ?: getMessageForReason("manual"))
    }

    /** Snapshot for Flutter polling — remaining seconds, last send, errors, receipts. */
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
            // Honest receipt state (Part 1).
            "sendInProgress" to prefs.getBoolean(KEY_SEND_IN_PROGRESS, false),
            "queuedCount" to prefs.getInt(KEY_LAST_QUEUED, 0),
            "deliveredCount" to prefs.getInt(KEY_LAST_DELIVERED, 0),
            "failedCount" to prefs.getInt(KEY_LAST_FAILED, 0),
            "perContact" to parsePerContact(prefs.getString(KEY_PER_CONTACT, null)),
        )
    }

    /** After process death, re-arm countdown from SharedPreferences if still in window. */
    fun restoreIfNeeded(context: Context) {
        finalizeStaleReceiptsIfAny(context)
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
                performSend(app, getMessageForReason(reason))
            }
            return
        }
        sendAtMs = at
        reason = prefs.getString(KEY_REASON, "fall") ?: "fall"
        active = true
        startTicking(app)
        updateCountdownNotification(app)
    }

    // ── Sending ───────────────────────────────────────────────────────────────

    private fun performSend(context: Context, message: String): Map<String, Any?> {
        if (!hasSendSmsPermission(context)) {
            val err = "SEND_SMS permission not granted"
            Log.w(TAG, err)
            prefs(context).edit().putString(KEY_LAST_ERROR, err).apply()
            notifySendResult(context, success = false, count = 0, detail = err)
            return mapOf(
                "ok" to false,
                "queuedCount" to 0,
                "sentCount" to 0,
                "deliveredCount" to 0,
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
            return mapOf(
                "ok" to false,
                "queuedCount" to 0,
                "sentCount" to 0,
                "deliveredCount" to 0,
                "failedCount" to 0,
                "error" to err,
            )
        }

        val namedPhones = contacts
            .map { it.name.trim() to it.phone.trim() }
            .filter { it.second.isNotEmpty() && it.second.any { ch -> ch.isDigit() } }
            .distinctBy { it.second }

        if (namedPhones.isEmpty()) {
            val err = "No emergency contacts with phone numbers"
            prefs(context).edit().putString(KEY_LAST_ERROR, err).apply()
            notifySendResult(context, success = false, count = 0, detail = err)
            return mapOf(
                "ok" to false,
                "queuedCount" to 0,
                "sentCount" to 0,
                "deliveredCount" to 0,
                "failedCount" to 0,
                "error" to err,
            )
        }

        val finalMessage = appendLiveLocation(context, message)
        val sms = smsManager(context)
        val now = System.currentTimeMillis()
        var queued = 0
        var immediateFailures = 0
        val errors = mutableListOf<String>()

        synchronized(receiptLock) {
            val prefs = prefs(context)
            val root = JSONObject()
            for ((name, phone) in namedPhones) {
                val entry = JSONObject()
                    .put("name", name)
                    .put("totalParts", 1)
                    .put("sent", JSONArray())
                    .put("failed", JSONArray())
                    .put("delivered", JSONArray())
                    .put("error", "")
                try {
                    val parts = sms.divideMessage(finalMessage)
                    entry.put("totalParts", parts.size)
                    if (parts.size == 1) {
                        sms.sendTextMessage(
                            phone,
                            null,
                            finalMessage,
                            receiptIntent(context, ACTION_SMS_SENT, name, phone, 0, 1),
                            receiptIntent(context, ACTION_SMS_DELIVERED, name, phone, 0, 1),
                        )
                    } else {
                        val sentPIs = ArrayList<PendingIntent>(parts.size)
                        val deliveredPIs = ArrayList<PendingIntent>(parts.size)
                        for (i in parts.indices) {
                            sentPIs.add(receiptIntent(context, ACTION_SMS_SENT, name, phone, i, parts.size))
                            deliveredPIs.add(receiptIntent(context, ACTION_SMS_DELIVERED, name, phone, i, parts.size))
                        }
                        sms.sendMultipartTextMessage(phone, null, parts, sentPIs, deliveredPIs)
                    }
                    queued++
                } catch (e: Exception) {
                    immediateFailures++
                    errors.add("$phone: ${e.message}")
                    Log.e(TAG, "SMS dispatch failed for $phone", e)
                    markAllPartsFailed(entry, e.message ?: "dispatch failed")
                }
                root.put(phone, entry)
            }

            prefs.edit()
                .putBoolean(KEY_SEND_IN_PROGRESS, queued > 0)
                .putLong(KEY_SEND_STARTED_AT, if (queued > 0) now else 0L)
                .putString(KEY_PENDING, root.toString())
                .putInt(KEY_LAST_QUEUED, queued)
                .putInt(KEY_LAST_FAILED, immediateFailures)
                .putString(KEY_PER_CONTACT, perContactArray(root).toString())
                // Cooldown anchor — same semantics as before (set at dispatch time).
                .putLong(KEY_LAST_SENT_AT, now)
                .putString(KEY_LAST_ERROR, errors.joinToString("; ").ifEmpty { null })
                .apply()
        }

        if (queued > 0) {
            armWatchdog(context.applicationContext)
            notifySending(context, queued)
        } else {
            notifySendResult(
                context,
                success = false,
                count = 0,
                detail = errors.joinToString("; ").ifEmpty { "Failed to send SMS" },
            )
        }

        Log.i(TAG, "SMS dispatch complete: queued=$queued immediateFailures=$immediateFailures")
        return mapOf(
            "ok" to (queued > 0),
            "queuedCount" to queued,
            "sentCount" to 0,
            "deliveredCount" to 0,
            "failedCount" to immediateFailures,
            "error" to errors.joinToString("; ").ifEmpty { null },
        )
    }

    // ── Receipt ledger ────────────────────────────────────────────────────────

    /** Called by [EmergencySmsResultReceiver] for every SENT / DELIVERED part receipt. */
    fun onReceipt(
        context: Context,
        kind: String,
        phone: String,
        name: String,
        partIndex: Int,
        totalParts: Int,
        resultCode: Int,
    ) {
        val app = context.applicationContext
        synchronized(receiptLock) {
            val prefs = prefs(app)
            if (!prefs.getBoolean(KEY_SEND_IN_PROGRESS, false)) return
            val root = try {
                JSONObject(prefs.getString(KEY_PENDING, "{}") ?: "{}")
            } catch (_: Exception) {
                return
            }
            val entry = root.optJSONObject(phone) ?: return
            val ok = resultCode == Activity.RESULT_OK
            val arrayKey = when {
                !ok && kind == "sent" -> "failed"
                !ok -> "" // delivered failures don't undo a sent part; recorded as error note
                kind == "sent" -> "sent"
                else -> "delivered"
            }
            if (!ok) {
                if (kind == "sent") {
                    putIntUnique(entry.optJSONArray("failed") ?: JSONArray(), partIndex)
                    if (entry.optString("error").isEmpty()) {
                        entry.put("error", describeSmsError(resultCode))
                    }
                }
            } else if (arrayKey.isNotEmpty()) {
                putIntUnique(entry.optJSONArray(arrayKey) ?: JSONArray(), partIndex)
            }
            root.put(phone, entry)
            prefs.edit().putString(KEY_PENDING, root.toString()).apply()
            maybeFinalize(app, root)
        }
    }

    private fun maybeFinalize(app: Context, root: JSONObject) {
        for (key in root.keys()) {
            if (contactStatus(root.optJSONObject(key) ?: continue) == "sending") return
        }
        finalizeSend(app, root, markUnknown = false)
    }

    private fun armWatchdog(app: Context) {
        disarmWatchdog()
        val runnable = Runnable {
            synchronized(receiptLock) {
                val prefs = prefs(app)
                if (!prefs.getBoolean(KEY_SEND_IN_PROGRESS, false)) return@Runnable
                val root = try {
                    JSONObject(prefs.getString(KEY_PENDING, "{}") ?: "{}")
                } catch (_: Exception) {
                    return@Runnable
                }
                finalizeSend(app, root, markUnknown = true)
            }
        }
        watchdogRunnable = runnable
        handler.postDelayed(runnable, RECEIPT_TIMEOUT_MS)
    }

    private fun disarmWatchdog() {
        watchdogRunnable?.let { handler.removeCallbacks(it) }
        watchdogRunnable = null
    }

    /** Process-death recovery: settle a send that never received all its receipts. */
    private fun finalizeStaleReceiptsIfAny(context: Context) {
        synchronized(receiptLock) {
            val app = context.applicationContext
            val prefs = prefs(app)
            if (!prefs.getBoolean(KEY_SEND_IN_PROGRESS, false)) return
            val startedAt = prefs.getLong(KEY_SEND_STARTED_AT, 0L)
            if (startedAt <= 0 || System.currentTimeMillis() - startedAt < RECEIPT_TIMEOUT_MS) return
            val root = try {
                JSONObject(prefs.getString(KEY_PENDING, "{}") ?: "{}")
            } catch (_: Exception) {
                prefs.edit().putBoolean(KEY_SEND_IN_PROGRESS, false).apply()
                return
            }
            finalizeSend(app, root, markUnknown = true)
        }
    }

    private fun finalizeSend(app: Context, root: JSONObject, markUnknown: Boolean) {
        val prefs = prefs(app)
        if (markUnknown) {
            for (key in root.keys()) {
                val entry = root.optJSONObject(key) ?: continue
                if (contactStatus(entry) == "sending" && entry.optString("error").isEmpty()) {
                    entry.put("error", "no delivery confirmation")
                }
            }
        }
        var sent = 0
        var delivered = 0
        var failed = 0
        for (key in root.keys()) {
            when (contactStatus(root.optJSONObject(key) ?: continue)) {
                "delivered" -> { sent++; delivered++ }
                "sent" -> sent++
                "failed" -> failed++
            }
        }
        disarmWatchdog()
        prefs.edit()
            .putBoolean(KEY_SEND_IN_PROGRESS, false)
            .putLong(KEY_SEND_STARTED_AT, 0L)
            .putInt(KEY_LAST_SENT_COUNT, sent)
            .putInt(KEY_LAST_DELIVERED, delivered)
            .putInt(KEY_LAST_FAILED, failed)
            .putString(KEY_PER_CONTACT, perContactArray(root).toString())
            .apply()
        val detail = buildString {
            append(if (delivered > 0) "Delivered to $delivered" else "Sent to $sent")
            if (sent - delivered > 0) append(" · delivery unconfirmed for ${sent - delivered}")
            if (failed > 0) append(" · Failed: $failed")
        }
        notifySendResult(
            app,
            success = sent > 0,
            count = sent,
            detail = if (sent > 0) detail else "SMS failed for all $failed contact(s)",
        )
        Log.i(TAG, "SMS finalized: sent=$sent delivered=$delivered failed=$failed")
    }

    private fun clearReceiptState(app: Context) {
        synchronized(receiptLock) {
            disarmWatchdog()
            prefs(app).edit()
                .putBoolean(KEY_SEND_IN_PROGRESS, false)
                .putLong(KEY_SEND_STARTED_AT, 0L)
                .putString(KEY_PENDING, "{}")
                .apply()
        }
    }

    private fun contactStatus(entry: JSONObject): String {
        val total = entry.optInt("totalParts", 1)
        val failed = entry.optJSONArray("failed")
        if (failed != null && failed.length() > 0) return "failed"
        val sent = entry.optJSONArray("sent")
        val delivered = entry.optJSONArray("delivered")
        val sentOk = sent != null && sent.length() >= total
        val deliveredOk = delivered != null && delivered.length() >= total
        return when {
            sentOk && deliveredOk -> "delivered"
            sentOk -> "sent"
            else -> "sending"
        }
    }

    private fun perContactArray(root: JSONObject): JSONArray {
        val out = JSONArray()
        for (key in root.keys()) {
            val entry = root.optJSONObject(key) ?: continue
            out.put(
                JSONObject()
                    .put("name", entry.optString("name"))
                    .put("phone", key)
                    .put("status", contactStatus(entry))
                    .put("error", entry.optString("error")),
            )
        }
        return out
    }

    private fun parsePerContact(raw: String?): List<Map<String, String>> {
        if (raw.isNullOrEmpty()) return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).map { i ->
                val o = array.getJSONObject(i)
                mapOf(
                    "name" to o.optString("name"),
                    "phone" to o.optString("phone"),
                    "status" to o.optString("status"),
                    "error" to o.optString("error"),
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun putIntUnique(array: JSONArray, value: Int) {
        for (i in 0 until array.length()) {
            if (array.optInt(i) == value) return
        }
        array.put(value)
    }

    private fun markAllPartsFailed(entry: JSONObject, error: String) {
        val total = entry.optInt("totalParts", 1)
        val failed = JSONArray()
        for (i in 0 until total) failed.put(i)
        entry.put("failed", failed)
        entry.put("error", error)
    }

    private fun describeSmsError(code: Int): String = when (code) {
        SmsManager.RESULT_ERROR_GENERIC_FAILURE -> "generic failure"
        SmsManager.RESULT_ERROR_RADIO_OFF -> "radio off"
        SmsManager.RESULT_ERROR_NULL_PDU -> "null PDU"
        SmsManager.RESULT_ERROR_NO_SERVICE -> "no service"
        else -> "error code $code"
    }

    // ── Live location link ────────────────────────────────────────────────────

    /**
     * Best-effort last-known fix (GPS → network → passive), newest first, ignored when
     * older than [LOCATION_MAX_AGE_MS]. Appends a Google Maps link so recipients can find
     * the wearer. Never throws; returns the original message when no usable fix exists.
     */
    private fun appendLiveLocation(context: Context, message: String): String {
        return try {
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                return message
            }
            val lm = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                ?: return message
            val best: Location? = listOf("gps", "network", "passive")
                .mapNotNull { provider ->
                    try {
                        lm.getLastKnownLocation(provider)
                    } catch (_: Exception) {
                        null
                    }
                }
                .filterNotNull()
                .maxByOrNull { it.time }
            if (best == null || System.currentTimeMillis() - best.time > LOCATION_MAX_AGE_MS) {
                return message
            }
            val link = "https://maps.google.com/?q=" +
                String.format(Locale.US, "%.5f,%.5f", best.latitude, best.longitude)
            "$message Live location: $link"
        } catch (_: Exception) {
            message
        }
    }

    // ── Receipt PendingIntents ────────────────────────────────────────────────

    private fun nextRequestCode(context: Context): Int {
        val prefs = prefs(context)
        val next = prefs.getInt(KEY_REQUEST_CODE, 3000) + 1
        prefs.edit().putInt(KEY_REQUEST_CODE, next).apply()
        return next
    }

    private fun receiptIntent(
        context: Context,
        action: String,
        name: String,
        phone: String,
        partIndex: Int,
        totalParts: Int,
    ): PendingIntent = PendingIntent.getBroadcast(
        context,
        nextRequestCode(context),
        Intent(context, EmergencySmsResultReceiver::class.java).apply {
            this.action = action
            putExtra(EXTRA_PHONE, phone)
            putExtra(EXTRA_NAME, name)
            putExtra(EXTRA_PART, partIndex)
            putExtra(EXTRA_TOTAL, totalParts)
        },
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    // ── Countdown plumbing (unchanged behavior) ───────────────────────────────

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
                        performSend(app, getMessageForReason(reason))
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

        // Mirror the remaining countdown onto the Android 16 live update.
        val skipStandard = SafetyLiveUpdate.updateCountdown(context, reason, remaining)
        if (!skipStandard) {
            try {
                NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
            } catch (_: SecurityException) {
                // POST_NOTIFICATIONS denied — countdown still runs; Flutter UI can still cancel.
            }
        }
    }

    private fun notifySending(context: Context, queued: Int) {
        ensureChannel(context)
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle("Sending emergency SMS…")
            .setContentText("Dispatching to $queued emergency contact${if (queued == 1) "" else "s"}")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOngoing(true)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID + 1, notification)
        } catch (_: SecurityException) {
        }
    }

    private fun notifySendResult(context: Context, success: Boolean, count: Int, detail: String) {
        if (SafetyLiveUpdate.showSent(context, count)) return
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
