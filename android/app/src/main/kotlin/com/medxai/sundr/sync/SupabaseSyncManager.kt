package com.medxai.sundr.sync

import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.gson.Gson
import com.medxai.sundr.data.MeasurementConfig
import com.medxai.sundr.data.ReadingRepository
import kotlinx.coroutines.launch
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.concurrent.TimeUnit

// Every 1 min, batch-pushes unsynced local Room rows to new Supabase "raw reading" tables
// (idempotent via a local_reading_id unique constraint), then recomputes and upserts the
// existing daily-aggregate tables (user_hr/user_spo2/user_hrv/user_steps) from local Room so
// existing chart/history screens keep working unchanged. Driven by BleConnectionService, same
// Handler.postDelayed pattern as its own reconnect loop.
object SupabaseSyncManager {
    private const val TAG = "SupabaseSync"
    private const val PREFS_NAME = "qring_supabase_sync_state"
    private const val KEY_LAST_ATTEMPT = "last_attempt_at"
    private const val KEY_LAST_SUCCESS = "last_success_at"
    private const val TICK_MS = 60 * 1000L // check every 1 min whether a push is due
    private const val PUSH_INTERVAL_MS = 60 * 1000L
    private const val BATCH_LIMIT = 200

    private val gson = Gson()
    private val handler = Handler(Looper.getMainLooper())
    private var started = false
    private lateinit var repository: ReadingRepository
    private lateinit var prefs: SharedPreferences

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    private val tickRunnable = object : Runnable {
        override fun run() {
            maybePush()
            handler.postDelayed(this, TICK_MS)
        }
    }

    fun start(context: Context) {
        if (started) {
            Log.d(TAG, "start: already started, ignoring")
            return
        }
        started = true
        val appContext = context.applicationContext
        MeasurementConfig.init(appContext)
        SupabaseConfig.init(appContext)
        repository = ReadingRepository.getInstance(appContext)
        prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        Log.d(TAG, "start: scheduling tick loop (first tick in 30s, then every ${TICK_MS}ms)")
        handler.postDelayed(tickRunnable, 30_000L) // let the connection settle first
    }

    fun stop() {
        started = false
        handler.removeCallbacks(tickRunnable)
    }

    fun getSyncStatus(): Map<String, Any?> {
        val lastAttempt = if (::prefs.isInitialized) prefs.getLong(KEY_LAST_ATTEMPT, 0L) else 0L
        val lastSuccess = if (::prefs.isInitialized) prefs.getLong(KEY_LAST_SUCCESS, 0L) else 0L
        return mapOf("lastPushAttemptAt" to lastAttempt, "lastPushSuccessAt" to lastSuccess)
    }

    // Debug/testing hook — triggers a push immediately, bypassing the 1h-elapsed and
    // isSyncEnabled gates in maybePush(). Still requires SupabaseConfig to be set (via
    // configureSync) since there's nothing to push to otherwise.
    fun forceSyncNow(): Boolean {
        if (!started || !::repository.isInitialized || !SupabaseConfig.isConfigured) return false
        repository.ioScope.launch { runPushCycle() }
        return true
    }

    private fun maybePush() {
        if (!MeasurementConfig.isSyncEnabled()) {
            Log.d(TAG, "maybePush: skipped — sync disabled (MeasurementConfig.isSyncEnabled()=false)")
            return
        }
        if (!SupabaseConfig.isConfigured) {
            Log.d(TAG, "maybePush: skipped — not configured (url=${SupabaseConfig.url != null}, " +
                "anonKey=${SupabaseConfig.anonKey != null}, userId=${SupabaseConfig.userId != null})")
            return
        }
        val lastSuccess = prefs.getLong(KEY_LAST_SUCCESS, 0L)
        val elapsedMs = System.currentTimeMillis() - lastSuccess
        if (elapsedMs < PUSH_INTERVAL_MS) {
            Log.d(TAG, "maybePush: skipped — only ${elapsedMs}ms elapsed, need ${PUSH_INTERVAL_MS}ms")
            return
        }
        Log.d(TAG, "maybePush: starting push cycle")
        repository.ioScope.launch { runPushCycle() }
    }

    private suspend fun runPushCycle() {
        prefs.edit().putLong(KEY_LAST_ATTEMPT, System.currentTimeMillis()).apply()
        val allOk = listOf(
            pushHeartRate(), pushSpo2(), pushHrv(), pushSteps(),
            pushBloodPressure(), pushStress(), pushTemperature()
        ).all { it }
        if (allOk) {
            prefs.edit().putLong(KEY_LAST_SUCCESS, System.currentTimeMillis()).apply()
            Log.d(TAG, "runPushCycle: all pushes succeeded")
        } else {
            Log.w(TAG, "runPushCycle: one or more pushes failed — will retry next tick, lastSuccess not advanced")
        }
        try {
            recomputeAndUpsertAggregates()
        } catch (e: Exception) {
            Log.e(TAG, "aggregate recompute/upsert failed", e)
        }
    }

    // ── Raw-reading pushes (new tables, idempotent via measured_at — NOT local_reading_id,
    // which is Room's local autoincrement PK and resets to 1 on every reinstall, causing
    // cross-install collisions/overwrites. measured_at is real wall-clock time and is
    // immune to that. local_reading_id is still sent along for local traceability only. ──

    private suspend fun pushHeartRate(): Boolean {
        val userId = SupabaseConfig.userId ?: return false
        val rows = repository.unsyncedHeartRate(BATCH_LIMIT)
        if (rows.isEmpty()) return true
        val payload = rows.map { r ->
            mapOf(
                "user_id" to userId, "value_bpm" to r.valueBpm,
                "measured_at" to isoTimestamp(r.measuredAt), "source" to r.source,
                "local_reading_id" to r.id
            )
        }
        val ok = postJsonWithRetry("user_hr_readings", "user_id,measured_at", gson.toJson(payload))
        if (ok) repository.markHeartRateSynced(rows.map { it.id }, System.currentTimeMillis())
        return ok
    }

    private suspend fun pushSpo2(): Boolean {
        val userId = SupabaseConfig.userId ?: return false
        val rows = repository.unsyncedSpo2(BATCH_LIMIT)
        if (rows.isEmpty()) return true
        val payload = rows.map { r ->
            mapOf(
                "user_id" to userId, "value_pct" to r.valuePct,
                "measured_at" to isoTimestamp(r.measuredAt), "source" to r.source,
                "local_reading_id" to r.id
            )
        }
        val ok = postJsonWithRetry("user_spo2_readings", "user_id,measured_at", gson.toJson(payload))
        if (ok) repository.markSpo2Synced(rows.map { it.id }, System.currentTimeMillis())
        return ok
    }

    private suspend fun pushHrv(): Boolean {
        val userId = SupabaseConfig.userId ?: return false
        val rows = repository.unsyncedHrv(BATCH_LIMIT)
        if (rows.isEmpty()) return true
        val payload = rows.map { r ->
            mapOf(
                "user_id" to userId, "value_ms" to r.valueMs,
                "measured_at" to isoTimestamp(r.measuredAt), "source" to r.source,
                "local_reading_id" to r.id
            )
        }
        val ok = postJsonWithRetry("user_hrv_readings", "user_id,measured_at", gson.toJson(payload))
        if (ok) repository.markHrvSynced(rows.map { it.id }, System.currentTimeMillis())
        return ok
    }

    private suspend fun pushSteps(): Boolean {
        val userId = SupabaseConfig.userId ?: return false
        val rows = repository.unsyncedSteps(BATCH_LIMIT)
        if (rows.isEmpty()) return true
        val payload = rows.map { r ->
            mapOf(
                "user_id" to userId, "steps" to r.steps, "calories_kcal" to r.caloriesKcal,
                "distance_m" to r.distanceM, "captured_at" to isoTimestamp(r.capturedAt),
                "source" to r.source, "local_reading_id" to r.id
            )
        }
        val ok = postJsonWithRetry("user_steps_snapshots", "user_id,captured_at", gson.toJson(payload))
        if (ok) repository.markStepsSynced(rows.map { it.id }, System.currentTimeMillis())
        return ok
    }

    // ── Per-event pushes into EXISTING tables (additive local_reading_id column) ──

    private suspend fun pushBloodPressure(): Boolean {
        val userId = SupabaseConfig.userId ?: return false
        val rows = repository.unsyncedBloodPressure(BATCH_LIMIT)
        if (rows.isEmpty()) return true
        val payload = rows.map { r ->
            mapOf(
                "user_id" to userId, "systolic" to r.systolic, "diastolic" to r.diastolic,
                "measured_at" to isoTimestamp(r.measuredAt), "source" to r.source,
                "local_reading_id" to r.id
            )
        }
        val ok = postJsonWithRetry("user_bp", "user_id,measured_at", gson.toJson(payload))
        if (ok) repository.markBloodPressureSynced(rows.map { it.id }, System.currentTimeMillis())
        return ok
    }

    private suspend fun pushStress(): Boolean {
        val userId = SupabaseConfig.userId ?: return false
        val rows = repository.unsyncedStress(BATCH_LIMIT)
        if (rows.isEmpty()) return true
        val payload = rows.map { r ->
            mapOf(
                "user_id" to userId, "stress_value" to r.value, "label" to r.label,
                "measured_at" to isoTimestamp(r.measuredAt), "source" to r.source,
                "local_reading_id" to r.id
            )
        }
        val ok = postJsonWithRetry("user_stress", "user_id,measured_at", gson.toJson(payload))
        if (ok) repository.markStressSynced(rows.map { it.id }, System.currentTimeMillis())
        return ok
    }

    private suspend fun pushTemperature(): Boolean {
        val userId = SupabaseConfig.userId ?: return false
        val rows = repository.unsyncedTemperature(BATCH_LIMIT)
        if (rows.isEmpty()) return true
        val payload = rows.map { r ->
            mapOf(
                "user_id" to userId, "value_c" to r.valueC,
                "measured_at" to isoTimestamp(r.measuredAt), "source" to r.source,
                "local_reading_id" to r.id
            )
        }
        val ok = postJsonWithRetry("user_temp", "user_id,measured_at", gson.toJson(payload))
        if (ok) repository.markTemperatureSynced(rows.map { it.id }, System.currentTimeMillis())
        return ok
    }

    // ── Daily aggregate recompute-and-upsert (existing tables, zero schema change) ─

    private suspend fun recomputeAndUpsertAggregates() {
        val userId = SupabaseConfig.userId ?: return
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now(zone)
        val dayStart = today.atStartOfDay(zone).toInstant().toEpochMilli()
        val dayEnd = today.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli() - 1
        val dateStr = today.toString()
        val nowIso = isoTimestamp(System.currentTimeMillis())

        val hr = repository.heartRateAggregate(dayStart, dayEnd)
        if (hr.count > 0) {
            postJsonWithRetry(
                "user_hr", "user_id,date",
                gson.toJson(listOf(mapOf(
                    "user_id" to userId, "date" to dateStr,
                    "avg_hr" to hr.avg?.let { Math.round(it).toInt() },
                    "min_hr" to hr.min, "max_hr" to hr.max,
                    "sample_count" to hr.count, "synced_at" to nowIso
                )))
            )
        }

        val spo2 = repository.spo2Aggregate(dayStart, dayEnd)
        if (spo2.count > 0) {
            postJsonWithRetry(
                "user_spo2", "user_id,date",
                gson.toJson(listOf(mapOf(
                    "user_id" to userId, "date" to dateStr,
                    "avg_spo2" to spo2.avg?.let { Math.round(it).toInt() },
                    "min_spo2" to spo2.min, "max_spo2" to spo2.max,
                    "sample_count" to spo2.count, "synced_at" to nowIso
                )))
            )
        }

        val hrv = repository.hrvAggregate(dayStart, dayEnd)
        if (hrv.count > 0) {
            postJsonWithRetry(
                "user_hrv", "user_id,date",
                gson.toJson(listOf(mapOf(
                    "user_id" to userId, "date" to dateStr,
                    "avg_hrv" to hrv.avg?.let { Math.round(it).toInt() },
                    "min_hrv" to hrv.min, "max_hrv" to hrv.max,
                    "sample_count" to hrv.count, "synced_at" to nowIso
                )))
            )
        }

        // MAX-of-day, never SUM — steps/calories/distance are cumulative-to-date counters.
        val steps = repository.stepsAggregate(dayStart, dayEnd)
        if (steps != null) {
            postJsonWithRetry(
                "user_steps", "user_id,date",
                gson.toJson(listOf(mapOf(
                    "user_id" to userId, "date" to dateStr,
                    "steps" to steps.steps, "calories" to steps.caloriesKcal,
                    "distance_m" to steps.distanceM, "synced_at" to nowIso
                )))
            )
        }
    }

    // ── HTTP plumbing ──────────────────────────────────────────────────────────────

    private fun isoTimestamp(epochMs: Long): String = Instant.ofEpochMilli(epochMs).toString()

    private fun postJson(path: String, onConflict: String, body: String): Boolean {
        val baseUrl = SupabaseConfig.url ?: return false
        val anonKey = SupabaseConfig.anonKey ?: return false
        val token = SupabaseConfig.accessToken ?: anonKey
        val fullUrl = "$baseUrl/rest/v1/$path?on_conflict=$onConflict"
        val request = Request.Builder()
            .url(fullUrl)
            .post(body.toRequestBody("application/json".toMediaType()))
            .addHeader("apikey", anonKey)
            .addHeader("Authorization", "Bearer $token")
            .addHeader("Content-Type", "application/json")
            .addHeader("Prefer", "resolution=merge-duplicates,return=minimal")
            .build()
        return try {
            client.newCall(request).execute().use { resp ->
                if (!resp.isSuccessful) {
                    // PostgREST returns the actual rejection reason (constraint violation,
                    // missing column, RLS denial, etc.) in the response body — without this,
                    // a failed push looks identical to a silent no-op in the local DB.
                    Log.e(TAG, "postJson $path failed: HTTP ${resp.code} body=${resp.body?.string()}")
                } else {
                    Log.d(TAG, "postJson $path succeeded: HTTP ${resp.code}")
                }
                resp.isSuccessful
            }
        } catch (e: Exception) {
            Log.e(TAG, "postJson failed for $path", e)
            false
        }
    }

    // Runs on Dispatchers.IO (via ReadingRepository.ioScope) — blocking sleep between
    // retries is intentional and safe there.
    private fun postJsonWithRetry(path: String, onConflict: String, body: String, attempts: Int = 3): Boolean {
        var delayMs = 5_000L
        for (attempt in 0 until attempts) {
            if (postJson(path, onConflict, body)) return true
            if (attempt < attempts - 1) {
                try { Thread.sleep(delayMs) } catch (_: InterruptedException) {}
                delayMs *= 3
            }
        }
        return false
    }
}