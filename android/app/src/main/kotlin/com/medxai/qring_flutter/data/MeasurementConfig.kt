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
}
