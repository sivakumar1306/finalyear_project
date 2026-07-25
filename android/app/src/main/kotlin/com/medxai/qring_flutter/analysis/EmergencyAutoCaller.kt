package com.medxai.qring_flutter.analysis

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telephony.SubscriptionManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.medxai.qring_flutter.MainActivity
import com.medxai.qring_flutter.data.ReadingRepository
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * On a **corroborated fall detection** (not fall prediction), immediately places a phone call
 * to the first saved emergency contact — only when the user has enabled the setting.
 *
 * Dual-SIM policy (no chooser dialog):
 * 1. Use the system **default SIM for calls** if one exists.
 * 2. Otherwise use the **first** call-capable / active SIM.
 * Never wait on "which SIM?" — that freezes emergency flow.
 */
object EmergencyAutoCaller {
    private const val TAG = "EmergencyAutoCall"
    private const val PREFS = "qring_fall_settings"
    private const val KEY_ENABLED = "auto_call_on_fall"
    private const val KEY_LAST_CALL_AT = "last_auto_call_at"
    private const val COOLDOWN_MS = 15 * 60_000L

    private const val CHANNEL_ID = "qring_emergency_call"
    const val NOTIFICATION_ID = 2004

    private val mainHandler = Handler(Looper.getMainLooper())

    fun isEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_ENABLED, false)

    fun setEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
        Log.i(TAG, "Auto-call on fall detection set to $enabled")
    }

    fun placeIfEnabled(context: Context) {
        val app = context.applicationContext
        if (!isEnabled(app)) {
            Log.i(TAG, "Auto-call skipped — feature disabled in settings")
            return
        }

        val now = System.currentTimeMillis()
        val last = prefs(app).getLong(KEY_LAST_CALL_AT, 0L)
        if (last > 0 && now - last < COOLDOWN_MS) {
            Log.i(TAG, "Auto-call skipped — within cooldown")
            return
        }

        if (!hasCallPermission(app)) {
            Log.w(TAG, "Auto-call skipped — CALL_PHONE not granted")
            notifyFailure(app, "Phone permission needed to auto-call emergency contact")
            return
        }

        val contact = try {
            runBlocking {
                ReadingRepository.getInstance(app).allEmergencyContacts().firstOrNull {
                    it.phone.trim().any { ch -> ch.isDigit() }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load emergency contacts", e)
            notifyFailure(app, "Could not load emergency contacts")
            return
        }

        if (contact == null) {
            Log.w(TAG, "Auto-call skipped — no emergency contacts")
            notifyFailure(app, "No emergency contact saved")
            return
        }

        val phone = contact.phone.trim()
        val ok = placeCall(app, phone)
        if (ok) {
            prefs(app).edit().putLong(KEY_LAST_CALL_AT, now).apply()
            notifyCalling(app, contact.name, phone)
            Log.i(TAG, "Auto-call started to ${contact.name} ($phone)")
        } else {
            notifyFailure(app, "Failed to place emergency call — check Phone permission / SIMs")
        }
    }

    /**
     * Place a call without the dual-SIM chooser:
     * default SIM if set, else first available SIM.
     */
    fun placeCall(context: Context, phone: String): Boolean {
        val app = context.applicationContext
        if (!hasCallPermission(app)) {
            Log.w(TAG, "placeCall: no CALL_PHONE permission")
            return false
        }
        val digits = phone.filter { it.isDigit() || it == '+' || it == '*' || it == '#' }
        if (digits.isEmpty()) {
            Log.w(TAG, "placeCall: empty phone after sanitize")
            return false
        }
        val uri = Uri.fromParts("tel", digits, null)

        // Telecom APIs are safest on the main thread on many OEMs.
        return runOnMainBlocking {
            placeViaTelecomPreferringDefaultOrFirst(app, uri) || placeViaIntent(app, uri, slot = 0)
        }
    }

    fun placeIfEnabledAsync(context: Context) {
        val app = context.applicationContext
        ReadingRepository.getInstance(app).ioScope.launch {
            placeIfEnabled(app)
        }
    }

    fun status(context: Context): Map<String, Any?> = mapOf(
        "enabled" to isEnabled(context),
        "hasPermission" to hasCallPermission(context),
        "lastCallAt" to prefs(context).getLong(KEY_LAST_CALL_AT, 0L),
    )

    /**
     * 1) default outgoing SIM if the user set one
     * 2) else first call-capable / first active subscription SIM
     * Tries each candidate until [TelecomManager.placeCall] succeeds.
     */
    @SuppressLint("MissingPermission")
    private fun placeViaTelecomPreferringDefaultOrFirst(context: Context, uri: Uri): Boolean {
        val telecom = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
            ?: return false

        val accounts = listPhoneAccounts(context, telecom)
        val defaultAccount = safeDefaultOutgoing(context, telecom)
        val ordered = linkedSetOf<PhoneAccountHandle>().apply {
            if (defaultAccount != null) add(defaultAccount)
            addAll(accounts)
        }.toList()

        Log.i(
            TAG,
            "SIM plan: default=${defaultAccount != null}, " +
                "accounts=${accounts.size}, will try ${ordered.size} handle(s) " +
                "(default first, else first SIM)",
        )

        if (ordered.isEmpty()) {
            // Single-SIM / account list unavailable — placeCall with empty extras.
            return tryPlace(telecom, uri, account = null)
        }

        for ((index, handle) in ordered.withIndex()) {
            Log.i(TAG, "Trying SIM account[$index]=$handle")
            if (tryPlace(telecom, uri, handle)) {
                Log.i(TAG, "Call placed with account[$index]")
                return true
            }
        }
        return false
    }

    private fun tryPlace(
        telecom: TelecomManager,
        uri: Uri,
        account: PhoneAccountHandle?,
    ): Boolean {
        return try {
            val extras = Bundle()
            if (account != null) {
                extras.putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, account)
            }
            telecom.placeCall(uri, extras)
            true
        } catch (e: SecurityException) {
            Log.e(TAG, "placeCall SecurityException account=$account", e)
            false
        } catch (e: Exception) {
            Log.e(TAG, "placeCall failed account=$account", e)
            false
        }
    }

    @SuppressLint("MissingPermission")
    private fun safeDefaultOutgoing(
        context: Context,
        telecom: TelecomManager,
    ): PhoneAccountHandle? {
        if (!hasReadPhoneState(context)) return null
        return try {
            telecom.getDefaultOutgoingPhoneAccount(PhoneAccount.SCHEME_TEL)
        } catch (e: Exception) {
            Log.w(TAG, "getDefaultOutgoingPhoneAccount: ${e.message}")
            null
        }
    }

    /**
     * All SIMs we can place a call on, first = slot 0 / first subscription.
     */
    @SuppressLint("MissingPermission")
    private fun listPhoneAccounts(
        context: Context,
        telecom: TelecomManager,
    ): List<PhoneAccountHandle> {
        val out = LinkedHashSet<PhoneAccountHandle>()

        if (hasReadPhoneState(context)) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    telecom.callCapablePhoneAccounts?.let { out.addAll(it) }
                }
            } catch (e: Exception) {
                Log.w(TAG, "callCapablePhoneAccounts: ${e.message}")
            }
        }

        // Fallback via SubscriptionManager when Telecom returns empty but SIMs are active.
        if (out.isEmpty() && hasReadPhoneState(context)) {
            try {
                val subMgr = context.getSystemService(SubscriptionManager::class.java)
                val subs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                    subMgr?.activeSubscriptionInfoList
                } else {
                    null
                }
                Log.i(TAG, "Active subscriptions: ${subs?.size ?: 0}")
                // Subscription IDs alone are not PhoneAccountHandles; if Telecom gave us
                // nothing, OEM ACTION_CALL with slot=0 is the remaining path.
            } catch (e: Exception) {
                Log.w(TAG, "SubscriptionManager: ${e.message}")
            }
        }

        return out.toList()
    }

    /**
     * Last resort: ACTION_CALL forced onto SIM slot 0 (first SIM) via common OEM extras.
     * Still better than showing a chooser that blocks forever.
     */
    @SuppressLint("MissingPermission")
    private fun placeViaIntent(context: Context, uri: Uri, slot: Int): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_CALL).apply {
                data = uri
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                // Common dual-SIM OEM keys — force first SIM, not a picker.
                putExtra("com.android.phone.force.slot", slot)
                putExtra("com.android.phone.extra.slot", slot)
                putExtra("slot", slot)
                putExtra("simslot", slot)
                putExtra("sim_slot", slot)
                putExtra("slot_id", slot)
                putExtra("simId", slot)
            }

            val telecom = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
            if (telecom != null) {
                val handle = safeDefaultOutgoing(context, telecom)
                    ?: listPhoneAccounts(context, telecom).firstOrNull()
                if (handle != null) {
                    intent.putExtra(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle)
                }
            }

            if (hasReadPhoneState(context) && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                try {
                    val subMgr = context.getSystemService(SubscriptionManager::class.java)
                    val firstSub = subMgr?.activeSubscriptionInfoList
                        ?.sortedBy { it.simSlotIndex }
                        ?.firstOrNull()
                    if (firstSub != null) {
                        val subId = firstSub.subscriptionId
                        intent.putExtra("subscription", subId)
                        intent.putExtra("Subscription", subId)
                        intent.putExtra("android.telephony.extra.SUBSCRIPTION_INDEX", firstSub.simSlotIndex)
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "subscription extras: ${e.message}")
                }
            }

            context.startActivity(intent)
            Log.i(TAG, "ACTION_CALL launched (prefer slot=$slot / first SIM)")
            true
        } catch (e: Exception) {
            Log.e(TAG, "ACTION_CALL failed", e)
            false
        }
    }

    private fun runOnMainBlocking(block: () -> Boolean): Boolean {
        if (Looper.myLooper() == Looper.getMainLooper()) return block()
        val latch = CountDownLatch(1)
        val ok = AtomicBoolean(false)
        mainHandler.post {
            try {
                ok.set(block())
            } finally {
                latch.countDown()
            }
        }
        return try {
            latch.await(8, TimeUnit.SECONDS)
            ok.get()
        } catch (_: InterruptedException) {
            false
        }
    }

    private fun hasCallPermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.CALL_PHONE) ==
            PackageManager.PERMISSION_GRANTED

    private fun hasReadPhoneState(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.READ_PHONE_STATE) ==
            PackageManager.PERMISSION_GRANTED

    private fun notifyCalling(context: Context, name: String, phone: String) {
        ensureChannel(context)
        val openApp = PendingIntent.getActivity(
            context,
            20,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle("Calling emergency contact")
            .setContentText("Calling $name ($phone) after fall detection")
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setAutoCancel(true)
            .setContentIntent(openApp)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
        }
    }

    private fun notifyFailure(context: Context, detail: String) {
        ensureChannel(context)
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle("Emergency call not placed")
            .setContentText(detail)
            .setStyle(NotificationCompat.BigTextStyle().bigText(detail))
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
        }
    }

    private fun ensureChannel(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Emergency Calls",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Notifies you when an emergency call is placed after fall detection"
            },
        )
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
