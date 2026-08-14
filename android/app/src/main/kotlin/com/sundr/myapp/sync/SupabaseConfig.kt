package com.sundr.myapp.sync

import android.content.Context
import android.content.SharedPreferences

// Cached natively (via BlePlugin's configureSync MethodChannel call) so SupabaseSyncManager
// can push even when the Flutter engine/Dart isn't currently running (e.g. right after boot).
object SupabaseConfig {
    private const val PREFS_NAME = "qring_supabase_sync_config"
    private const val KEY_URL = "url"
    private const val KEY_ANON_KEY = "anon_key"
    private const val KEY_USER_ID = "user_id"
    private const val KEY_ACCESS_TOKEN = "access_token"

    private var prefs: SharedPreferences? = null

    fun init(context: Context) {
        if (prefs == null) {
            prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        }
    }

    // accessToken is the current Supabase auth session's JWT. It's optional: if RLS policies
    // require an authenticated user rather than the anon role, Dart should re-call this
    // whenever the session token refreshes (e.g. via an auth-state-change listener) to keep
    // it reasonably fresh, since native code has no way to refresh it independently.
    fun configure(url: String, anonKey: String, userId: String, accessToken: String?) {
        prefs?.edit()
            ?.putString(KEY_URL, url)
            ?.putString(KEY_ANON_KEY, anonKey)
            ?.putString(KEY_USER_ID, userId)
            ?.putString(KEY_ACCESS_TOKEN, accessToken)
            ?.apply()
    }

    val url: String? get() = prefs?.getString(KEY_URL, null)
    val anonKey: String? get() = prefs?.getString(KEY_ANON_KEY, null)
    val userId: String? get() = prefs?.getString(KEY_USER_ID, null)
    val accessToken: String? get() = prefs?.getString(KEY_ACCESS_TOKEN, null)

    val isConfigured: Boolean
        get() = !url.isNullOrEmpty() && !anonKey.isNullOrEmpty() && !userId.isNullOrEmpty()

    // Logout wipe: drop the cached URL/anon key/user_id/JWT so the native sync manager
    // stops pushing (it no-ops while !isConfigured) and no stale credentials survive.
    fun clear() {
        prefs?.edit()?.clear()?.apply()
    }
}
