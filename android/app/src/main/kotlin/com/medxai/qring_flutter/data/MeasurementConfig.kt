package com.medxai.qring_flutter.data

import android.content.Context
import android.content.SharedPreferences

// Backed by SharedPreferences (same idiom as the rest of this app) rather than a Room
// table — flipping a vital on/off (e.g. HRV/Temperature once their one-click reliability
// is fixed) never needs a data migration, just a flag flip via setEnabled().
object MeasurementConfig {
    private const val PREFS_NAME = "qring_measurement_config"
    private const val KEY_PREFIX_ENABLED = "vital_enabled_"
    private const val KEY_MASTER_ENABLED = "master_loop_enabled"
    private const val KEY_SYNC_ENABLED = "supabase_sync_enabled"
    private const val KEY_CYCLE_COOLDOWN_MS = "cycle_cooldown_ms"

    // Default gap between the end of one auto-measurement cycle and the start of the next.
    // Chosen to reduce continuous PPG sensor duty-cycle (battery/heat) versus the earlier
    // 60s value, while still giving a reasonable sampling cadence for trend charts.
    private const val DEFAULT_CYCLE_COOLDOWN_MS = 180_000L // 3 minutes

    // Sanity bounds so a bad value (e.g. a stray 0 or a typo like "300" meaning ms instead
    // of seconds) can't make the loop spin constantly or effectively stop running.
    private const val MIN_CYCLE_COOLDOWN_MS = 30_000L   // 30s floor
    private const val MAX_CYCLE_COOLDOWN_MS = 1_800_000L // 30 min ceiling

    private var prefs: SharedPreferences? = null

    fun init(context: Context) {
        if (prefs == null) {
            prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        }
    }

    // Rollout Phase 1 kill-switch: the whole round-robin loop is a no-op while this is false.
    fun isMasterEnabled(): Boolean = prefs?.getBoolean(KEY_MASTER_ENABLED, false) ?: false

    fun setMasterEnabled(enabled: Boolean) {
        prefs?.edit()?.putBoolean(KEY_MASTER_ENABLED, enabled)?.apply()
    }

    // Rollout Phase 2 kill-switch: the 6-hour Supabase push is a no-op while this is false,
    // independent of the loop itself so local-only soaking (Phase 1) is possible.
    fun isSyncEnabled(): Boolean = prefs?.getBoolean(KEY_SYNC_ENABLED, false) ?: false

    fun setSyncEnabled(enabled: Boolean) {
        prefs?.edit()?.putBoolean(KEY_SYNC_ENABLED, enabled)?.apply()
    }

    fun isEnabled(vital: Vital): Boolean =
        prefs?.getBoolean(KEY_PREFIX_ENABLED + vital.name, vital.defaultEnabled) ?: vital.defaultEnabled

    fun setEnabled(vital: Vital, enabled: Boolean) {
        prefs?.edit()?.putBoolean(KEY_PREFIX_ENABLED + vital.name, enabled)?.apply()
    }

    // Gap between auto-cycles, in milliseconds. Configurable from Flutter (see
    // BlePlugin.getCycleCooldownMs/setCycleCooldownMs) so it can be tuned without a rebuild.
    fun getCycleCooldownMs(): Long {
        val stored = prefs?.getLong(KEY_CYCLE_COOLDOWN_MS, DEFAULT_CYCLE_COOLDOWN_MS) ?: DEFAULT_CYCLE_COOLDOWN_MS
        return stored.coerceIn(MIN_CYCLE_COOLDOWN_MS, MAX_CYCLE_COOLDOWN_MS)
    }

    fun setCycleCooldownMs(ms: Long) {
        val clamped = ms.coerceIn(MIN_CYCLE_COOLDOWN_MS, MAX_CYCLE_COOLDOWN_MS)
        prefs?.edit()?.putLong(KEY_CYCLE_COOLDOWN_MS, clamped)?.apply()
    }
}