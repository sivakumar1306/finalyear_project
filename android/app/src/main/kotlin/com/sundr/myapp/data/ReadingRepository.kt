package com.sundr.myapp.data

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

// Facade over QRingDatabase used both by MeasurementLoopManager (writes) and by
// BlePlugin's MethodChannel query methods (reads). Room requires non-main-thread
// access, so every call here hops onto Dispatchers.IO.
//
// Offline-first notes:
// - Raw readings power "today" charts and survive for RETENTION_RAW_DAYS after sync.
// - daily_vital_summary rollups keep multi-day trends available offline even after
//   raw rows are purged, and can cache cloud day-rows (origin=cloud_cache).
class ReadingRepository private constructor(context: Context) {
    private val db = QRingDatabase.getInstance(context)

    // Without a CoroutineExceptionHandler, any failed Room/sync job becomes an uncaught
    // exception on a background thread and can kill the whole process ("app randomly closes").
    private val ioExceptionHandler = CoroutineExceptionHandler { _, throwable ->
        Log.e(TAG, "Background DB/sync job failed (swallowed to keep process alive)", throwable)
    }
    val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO + ioExceptionHandler)

    private val zone: ZoneId = ZoneId.systemDefault()
    private val dateFmt: DateTimeFormatter = DateTimeFormatter.ISO_LOCAL_DATE

    suspend fun startCycle(): Long = withContext(Dispatchers.IO) {
        db.measurementCycleDao().insert(MeasurementCycleEntity(startedAt = System.currentTimeMillis(), status = "RUNNING"))
    }

    suspend fun completeCycle(cycleId: Long, status: String, abortedAtVital: String? = null) = withContext(Dispatchers.IO) {
        db.measurementCycleDao().complete(cycleId, status, System.currentTimeMillis(), abortedAtVital)
    }

    suspend fun cyclesBetween(fromMs: Long, toMs: Long) = withContext(Dispatchers.IO) {
        db.measurementCycleDao().cyclesBetween(fromMs, toMs)
    }

    // ── Measurement attempts (per-vital audit for Measurement Log) ─
    suspend fun startAttempt(vital: String, source: String, cycleId: Long): Long = withContext(Dispatchers.IO) {
        db.measurementAttemptDao().insert(
            MeasurementAttemptEntity(vital = vital, source = source, cycleId = cycleId, startedAt = System.currentTimeMillis(), status = "RUNNING"))
    }

    suspend fun finishAttempt(id: Long, status: String, error: String? = null, valueJson: String? = null) = withContext(Dispatchers.IO) {
        db.measurementAttemptDao().finish(id, System.currentTimeMillis(), status, error, valueJson)
    }

    suspend fun attemptsBetween(fromMs: Long, toMs: Long, limit: Int = 1000) = withContext(Dispatchers.IO) {
        db.measurementAttemptDao().attemptsBetween(fromMs, toMs, limit)
    }

    suspend fun attemptsForCycle(cycleId: Long) = withContext(Dispatchers.IO) {
        db.measurementAttemptDao().attemptsForCycle(cycleId)
    }

    suspend fun failedBetween(fromMs: Long, toMs: Long, limit: Int = 1000) = withContext(Dispatchers.IO) {
        db.measurementAttemptDao().failedBetween(fromMs, toMs, limit)
    }

    // ── Inserts (auto-refresh daily rollups so history works offline) ─

    suspend fun insertHeartRate(bpm: Int, cycleId: Long, source: String, deviceAddress: String? = null): Long =
        withContext(Dispatchers.IO) {
            // Final gate: an implausible value would otherwise roll into every daily
            // avg/min/max summary (home cards, trends, Supabase sync, fall-risk analysis).
            if (!VitalRanges.isValidBpm(bpm)) {
                Log.w(TAG, "Rejected implausible heart rate reading: $bpm bpm (source=$source)")
                return@withContext -1L
            }
            val at = System.currentTimeMillis()
            val id = db.heartRateDao().insert(
                HeartRateReadingEntity(
                    valueBpm = bpm, measuredAt = at, cycleId = cycleId, source = source, deviceAddress = deviceAddress
                )
            )
            safeRefreshDailySummary("heart_rate", at)
            id
        }

    // Manual / interval-sync path with explicit timestamp (QRing-style app_heart).
    // Used by BlePlugin.insertHeartRate and syncIntervalHeartRateDetail so a fresh
    // tap or a backfilled interval slot gets a correct measuredAt instead of now()
    // stuck in the wrong hourly bucket.
    suspend fun insertHeartRateAt(bpm: Int, measuredAt: Long, cycleId: Long, source: String, deviceAddress: String? = null): Long =
        withContext(Dispatchers.IO) {
            if (!VitalRanges.isValidBpm(bpm)) {
                Log.w(TAG, "Rejected implausible heart rate reading: $bpm bpm (source=$source)")
                return@withContext -1L
            }
            val id = db.heartRateDao().insert(
                HeartRateReadingEntity(
                    valueBpm = bpm, measuredAt = measuredAt, cycleId = cycleId, source = source, deviceAddress = deviceAddress
                )
            )
            safeRefreshDailySummary("heart_rate", measuredAt)
            id
        }

    suspend fun insertSpo2(pct: Int, cycleId: Long, source: String, deviceAddress: String? = null): Long =
        withContext(Dispatchers.IO) {
            val at = System.currentTimeMillis()
            val id = db.spo2Dao().insert(
                Spo2ReadingEntity(
                    valuePct = pct, measuredAt = at, cycleId = cycleId, source = source, deviceAddress = deviceAddress
                )
            )
            safeRefreshDailySummary("spo2", at)
            id
        }

    suspend fun insertSpo2At(pct: Int, measuredAt: Long, cycleId: Long, source: String, deviceAddress: String? = null): Long =
        withContext(Dispatchers.IO) {
            if (pct <= 0) return@withContext -1L
            val id = db.spo2Dao().insert(
                Spo2ReadingEntity(
                    valuePct = pct, measuredAt = measuredAt, cycleId = cycleId, source = source, deviceAddress = deviceAddress
                )
            )
            safeRefreshDailySummary("spo2", measuredAt)
            id
        }

    suspend fun insertStress(value: Int, label: String?, cycleId: Long, source: String, deviceAddress: String? = null): Long =
        withContext(Dispatchers.IO) {
            val at = System.currentTimeMillis()
            val id = db.stressDao().insert(
                StressReadingEntity(
                    value = value, label = label, measuredAt = at, cycleId = cycleId, source = source, deviceAddress = deviceAddress
                )
            )
            safeRefreshDailySummary("stress", at)
            id
        }

    suspend fun insertBloodPressure(sbp: Int, dbp: Int, cycleId: Long, source: String, deviceAddress: String? = null): Long =
        withContext(Dispatchers.IO) {
            val at = System.currentTimeMillis()
            val id = db.bloodPressureDao().insert(
                BloodPressureReadingEntity(
                    systolic = sbp, diastolic = dbp, measuredAt = at, cycleId = cycleId, source = source, deviceAddress = deviceAddress
                )
            )
            safeRefreshDailySummary("blood_pressure", at)
            id
        }

    suspend fun insertHrv(valueMs: Int, cycleId: Long, source: String, deviceAddress: String? = null): Long =
        withContext(Dispatchers.IO) {
            val at = System.currentTimeMillis()
            val id = db.hrvDao().insert(
                HrvReadingEntity(
                    valueMs = valueMs, measuredAt = at, cycleId = cycleId, source = source, deviceAddress = deviceAddress
                )
            )
            safeRefreshDailySummary("hrv", at)
            id
        }

    suspend fun insertHrvAt(valueMs: Int, measuredAt: Long, cycleId: Long, source: String, deviceAddress: String? = null): Long =
        withContext(Dispatchers.IO) {
            if (valueMs <= 0) return@withContext -1L
            val id = db.hrvDao().insert(
                HrvReadingEntity(
                    valueMs = valueMs, measuredAt = measuredAt, cycleId = cycleId, source = source, deviceAddress = deviceAddress
                )
            )
            safeRefreshDailySummary("hrv", measuredAt)
            id
        }

    suspend fun insertTemperature(valueC: Double, cycleId: Long, source: String, deviceAddress: String? = null): Long =
        withContext(Dispatchers.IO) {
            val at = System.currentTimeMillis()
            val id = db.temperatureDao().insert(
                TemperatureReadingEntity(
                    valueC = valueC, measuredAt = at, cycleId = cycleId, source = source, deviceAddress = deviceAddress
                )
            )
            safeRefreshDailySummary("temperature", at)
            id
        }

    suspend fun insertTemperatureAt(valueC: Double, measuredAt: Long, cycleId: Long, source: String, deviceAddress: String? = null): Long =
        withContext(Dispatchers.IO) {
            if (valueC <= 0) return@withContext -1L
            val id = db.temperatureDao().insert(
                TemperatureReadingEntity(
                    valueC = valueC, measuredAt = measuredAt, cycleId = cycleId, source = source, deviceAddress = deviceAddress
                )
            )
            safeRefreshDailySummary("temperature", measuredAt)
            id
        }

    suspend fun insertStepsSnapshot(
        steps: Int,
        caloriesKcal: Int,
        distanceM: Double,
        cycleId: Long,
        source: String,
        deviceAddress: String? = null
    ): Long = withContext(Dispatchers.IO) {
        val at = System.currentTimeMillis()
        val id = db.stepsSnapshotDao().insert(
            StepsSnapshotEntity(
                steps = steps,
                caloriesKcal = caloriesKcal,
                distanceM = distanceM,
                capturedAt = at,
                cycleId = cycleId,
                source = source,
                deviceAddress = deviceAddress
            )
        )
        safeRefreshDailySummary("steps", at)
        id
    }

    // ── Latest / range queries (BlePlugin read surface) ─────────────

    suspend fun latestHeartRate() = withContext(Dispatchers.IO) { db.heartRateDao().latest() }
    suspend fun latestSpo2() = withContext(Dispatchers.IO) { db.spo2Dao().latest() }
    suspend fun latestStress() = withContext(Dispatchers.IO) { db.stressDao().latest() }
    suspend fun latestBloodPressure() = withContext(Dispatchers.IO) { db.bloodPressureDao().latest() }
    suspend fun latestHrv() = withContext(Dispatchers.IO) { db.hrvDao().latest() }
    suspend fun latestTemperature() = withContext(Dispatchers.IO) { db.temperatureDao().latest() }
    suspend fun latestStepsSnapshot() = withContext(Dispatchers.IO) { db.stepsSnapshotDao().latest() }

    suspend fun heartRateAggregate(dayStart: Long, dayEnd: Long) =
        withContext(Dispatchers.IO) { db.heartRateDao().dailyAggregate(dayStart, dayEnd) }

    suspend fun spo2Aggregate(dayStart: Long, dayEnd: Long) =
        withContext(Dispatchers.IO) { db.spo2Dao().dailyAggregate(dayStart, dayEnd) }

    suspend fun stressAggregate(dayStart: Long, dayEnd: Long) =
        withContext(Dispatchers.IO) { db.stressDao().dailyAggregate(dayStart, dayEnd) }

    suspend fun bpAggregate(dayStart: Long, dayEnd: Long) =
        withContext(Dispatchers.IO) { db.bloodPressureDao().dailyAggregate(dayStart, dayEnd) }

    suspend fun hrvAggregate(dayStart: Long, dayEnd: Long) =
        withContext(Dispatchers.IO) { db.hrvDao().dailyAggregate(dayStart, dayEnd) }

    suspend fun temperatureAggregate(dayStart: Long, dayEnd: Long) =
        withContext(Dispatchers.IO) { db.temperatureDao().dailyAggregate(dayStart, dayEnd) }

    // Steps aggregate is deliberately MAX-of-day, never SUM — see StepsSnapshotDao.dailyMax.
    suspend fun stepsAggregate(dayStart: Long, dayEnd: Long) =
        withContext(Dispatchers.IO) { db.stepsSnapshotDao().dailyMax(dayStart, dayEnd) }

    suspend fun heartRateBetween(fromMs: Long, toMs: Long, limit: Int) =
        withContext(Dispatchers.IO) { db.heartRateDao().readingsBetween(fromMs, toMs, limit) }

    suspend fun spo2Between(fromMs: Long, toMs: Long, limit: Int) =
        withContext(Dispatchers.IO) { db.spo2Dao().readingsBetween(fromMs, toMs, limit) }

    suspend fun stressBetween(fromMs: Long, toMs: Long, limit: Int) =
        withContext(Dispatchers.IO) { db.stressDao().readingsBetween(fromMs, toMs, limit) }

    suspend fun bpBetween(fromMs: Long, toMs: Long, limit: Int) =
        withContext(Dispatchers.IO) { db.bloodPressureDao().readingsBetween(fromMs, toMs, limit) }

    suspend fun hrvBetween(fromMs: Long, toMs: Long, limit: Int) =
        withContext(Dispatchers.IO) { db.hrvDao().readingsBetween(fromMs, toMs, limit) }

    suspend fun temperatureBetween(fromMs: Long, toMs: Long, limit: Int) =
        withContext(Dispatchers.IO) { db.temperatureDao().readingsBetween(fromMs, toMs, limit) }

    suspend fun stepsBetween(fromMs: Long, toMs: Long, limit: Int) =
        withContext(Dispatchers.IO) { db.stepsSnapshotDao().snapshotsBetween(fromMs, toMs, limit) }

    // ── Sync surface (SupabaseSyncManager) ──────────────────────────

    suspend fun unsyncedHeartRate(limit: Int) = withContext(Dispatchers.IO) { db.heartRateDao().unsyncedBatch(limit) }
    suspend fun unsyncedSpo2(limit: Int) = withContext(Dispatchers.IO) { db.spo2Dao().unsyncedBatch(limit) }
    suspend fun unsyncedStress(limit: Int) = withContext(Dispatchers.IO) { db.stressDao().unsyncedBatch(limit) }
    suspend fun unsyncedBloodPressure(limit: Int) = withContext(Dispatchers.IO) { db.bloodPressureDao().unsyncedBatch(limit) }
    suspend fun unsyncedHrv(limit: Int) = withContext(Dispatchers.IO) { db.hrvDao().unsyncedBatch(limit) }
    suspend fun unsyncedTemperature(limit: Int) = withContext(Dispatchers.IO) { db.temperatureDao().unsyncedBatch(limit) }
    suspend fun unsyncedSteps(limit: Int) = withContext(Dispatchers.IO) { db.stepsSnapshotDao().unsyncedBatch(limit) }

    suspend fun markHeartRateSynced(ids: List<Long>, at: Long) =
        withContext(Dispatchers.IO) { db.heartRateDao().markSynced(ids, at) }

    suspend fun markSpo2Synced(ids: List<Long>, at: Long) =
        withContext(Dispatchers.IO) { db.spo2Dao().markSynced(ids, at) }

    suspend fun markStressSynced(ids: List<Long>, at: Long) =
        withContext(Dispatchers.IO) { db.stressDao().markSynced(ids, at) }

    suspend fun markBloodPressureSynced(ids: List<Long>, at: Long) =
        withContext(Dispatchers.IO) { db.bloodPressureDao().markSynced(ids, at) }

    suspend fun markHrvSynced(ids: List<Long>, at: Long) =
        withContext(Dispatchers.IO) { db.hrvDao().markSynced(ids, at) }

    suspend fun markTemperatureSynced(ids: List<Long>, at: Long) =
        withContext(Dispatchers.IO) { db.temperatureDao().markSynced(ids, at) }

    suspend fun markStepsSynced(ids: List<Long>, at: Long) =
        withContext(Dispatchers.IO) { db.stepsSnapshotDao().markSynced(ids, at) }

    // Retention: drop synced raw vitals older than [retentionDays]. Unsynced rows are kept.
    // Daily rollups are retained much longer so offline trends still work after raw purge.
    suspend fun purgeOldSyncedReadings(retentionDays: Long = RETENTION_RAW_DAYS): Int = withContext(Dispatchers.IO) {
        recomputeRecentDailySummaries(daysBack = retentionDays + 7)

        val cutoff = System.currentTimeMillis() - retentionDays * DAY_MS
        var deleted = 0
        deleted += db.heartRateDao().purgeSyncedOlderThan(cutoff)
        deleted += db.spo2Dao().purgeSyncedOlderThan(cutoff)
        deleted += db.stressDao().purgeSyncedOlderThan(cutoff)
        deleted += db.bloodPressureDao().purgeSyncedOlderThan(cutoff)
        deleted += db.hrvDao().purgeSyncedOlderThan(cutoff)
        deleted += db.temperatureDao().purgeSyncedOlderThan(cutoff)
        deleted += db.stepsSnapshotDao().purgeSyncedOlderThan(cutoff)
        deleted += db.fallRiskLogDao().purgeOlderThan(cutoff)
        deleted += db.fallEventDao().purgeOlderThan(cutoff)

        val localRollupCutoff = System.currentTimeMillis() - RETENTION_LOCAL_SUMMARY_DAYS * DAY_MS
        val cloudCacheCutoff = System.currentTimeMillis() - RETENTION_CLOUD_CACHE_DAYS * DAY_MS
        deleted += db.dailyVitalSummaryDao().purgeOldLocal(localRollupCutoff)
        deleted += db.dailyVitalSummaryDao().purgeOldCloudCache(cloudCacheCutoff)
        deleted
    }

    // ── Offline-first day summaries / multi-day history ─────────────

    /** Aggregate for any local calendar day. Prefers raw Room rows, falls back to cached rollup. */
    suspend fun daySummary(vital: String, dayStartMs: Long, dayEndMs: Long): Map<String, Any?> =
        withContext(Dispatchers.IO) {
            val fromRaw = daySummaryFromRaw(vital, dayStartMs, dayEndMs)
            if ((fromRaw["count"] as? Int ?: 0) > 0 || (fromRaw["steps"] as? Int ?: 0) > 0) {
                upsertSummaryMap(vital, dayStartMs, fromRaw, origin = "local")
                return@withContext fromRaw + mapOf("origin" to "local", "dateStr" to dateStrOf(dayStartMs))
            }
            val cached = db.dailyVitalSummaryDao().get(vital, dayStartMs)
            if (cached != null && (cached.count > 0 || (cached.steps ?: 0) > 0)) {
                return@withContext summaryEntityToMap(cached)
            }
            fromRaw + mapOf("origin" to "empty", "dateStr" to dateStrOf(dayStartMs))
        }

    /** Multi-day history for charts — refreshes recent days from raw, then returns rollups. */
    suspend fun localHistory(vital: String, fromDayStartMs: Long, toDayStartMs: Long): List<Map<String, Any?>> =
        withContext(Dispatchers.IO) {
            val todayStart = localDayStartMs(System.currentTimeMillis())
            var cursor = maxOf(fromDayStartMs, todayStart - 13L * DAY_MS)
            while (cursor <= toDayStartMs) {
                val end = cursor + DAY_MS - 1
                val raw = daySummaryFromRaw(vital, cursor, end)
                if ((raw["count"] as? Int ?: 0) > 0 || (raw["steps"] as? Int ?: 0) > 0) {
                    upsertSummaryMap(vital, cursor, raw, origin = "local")
                }
                cursor += DAY_MS
            }
            db.dailyVitalSummaryDao().between(vital, fromDayStartMs, toDayStartMs).map { summaryEntityToMap(it) }
        }

    /** Mirror a cloud day-row into Room so the next open works offline. */
    suspend fun cacheCloudDaySummary(
        vital: String,
        dayStartMs: Long,
        avg: Double?,
        min: Double?,
        max: Double?,
        count: Int,
        avgSecondary: Double? = null,
        minSecondary: Double? = null,
        maxSecondary: Double? = null,
        steps: Int? = null,
        caloriesKcal: Int? = null,
        distanceM: Double? = null,
    ) = withContext(Dispatchers.IO) {
        val existing = db.dailyVitalSummaryDao().get(vital, dayStartMs)
        if (existing != null && existing.origin == "local" && existing.count >= count && count > 0) {
            return@withContext
        }
        db.dailyVitalSummaryDao().upsert(
            DailyVitalSummaryEntity(
                vital = vital,
                dayEpochMs = dayStartMs,
                dateStr = dateStrOf(dayStartMs),
                avg = avg,
                min = min,
                max = max,
                count = count,
                avgSecondary = avgSecondary,
                minSecondary = minSecondary,
                maxSecondary = maxSecondary,
                steps = steps,
                caloriesKcal = caloriesKcal,
                distanceM = distanceM,
                origin = "cloud_cache",
                updatedAt = System.currentTimeMillis()
            )
        )
    }

    suspend fun localDbStats(): Map<String, Any?> = withContext(Dispatchers.IO) {
        mapOf(
            "database" to "qring_local.db",
            "pendingSyncRows" to (
                db.heartRateDao().unsyncedCount() + db.spo2Dao().unsyncedCount() + db.stressDao().unsyncedCount() +
                    db.bloodPressureDao().unsyncedCount() + db.hrvDao().unsyncedCount() +
                    db.temperatureDao().unsyncedCount() + db.stepsSnapshotDao().unsyncedCount()
                ),
            "dailySummaryRows" to db.dailyVitalSummaryDao().count(),
            "retentionRawDays" to RETENTION_RAW_DAYS,
            "retentionLocalSummaryDays" to RETENTION_LOCAL_SUMMARY_DAYS,
            "retentionCloudCacheDays" to RETENTION_CLOUD_CACHE_DAYS,
            "zone" to zone.id
        )
    }

    // ── Demo data seeding (dev/testing only) ────────────────────────

    suspend fun seedDemoData(hoursBack: Long = 3): Unit = withContext(Dispatchers.IO) {
        val now = System.currentTimeMillis()
        val start = now - hoursBack * 3_600_000L
        val cycleId = db.measurementCycleDao().insert(
            MeasurementCycleEntity(startedAt = start, completedAt = now, status = "COMPLETED")
        )
        val rnd = kotlin.random.Random(now)

        var cumulativeSteps = 0
        var cumulativeCalories = 0
        var cumulativeDistance = 0.0
        var t = start
        while (t <= now) {
            db.heartRateDao().insert(
                HeartRateReadingEntity(valueBpm = 58 + rnd.nextInt(25), measuredAt = t, cycleId = cycleId, source = "demo_seed")
            )
            db.spo2Dao().insert(
                Spo2ReadingEntity(valuePct = 95 + rnd.nextInt(5), measuredAt = t, cycleId = cycleId, source = "demo_seed")
            )
            val stress = 15 + rnd.nextInt(50)
            val label = when {
                stress < 30 -> "relaxed"
                stress < 60 -> "normal"
                else -> "elevated"
            }
            db.stressDao().insert(
                StressReadingEntity(value = stress, label = label, measuredAt = t, cycleId = cycleId, source = "demo_seed")
            )
            db.hrvDao().insert(
                HrvReadingEntity(valueMs = 30 + rnd.nextInt(40), measuredAt = t, cycleId = cycleId, source = "demo_seed")
            )
            val steps = 20 + rnd.nextInt(80)
            cumulativeSteps += steps
            cumulativeCalories += (steps * 0.04).toInt().coerceAtLeast(1)
            cumulativeDistance += steps * 0.75
            db.stepsSnapshotDao().insert(
                StepsSnapshotEntity(
                    steps = cumulativeSteps,
                    caloriesKcal = cumulativeCalories,
                    distanceM = cumulativeDistance,
                    capturedAt = t,
                    cycleId = cycleId,
                    source = "demo_seed"
                )
            )
            t += 5 * 60_000L
        }

        var tSlow = start
        while (tSlow <= now) {
            db.bloodPressureDao().insert(
                BloodPressureReadingEntity(
                    systolic = 108 + rnd.nextInt(20),
                    diastolic = 68 + rnd.nextInt(14),
                    measuredAt = tSlow,
                    cycleId = cycleId,
                    source = "demo_seed"
                )
            )
            db.temperatureDao().insert(
                TemperatureReadingEntity(
                    valueC = 36.1 + rnd.nextDouble() * 0.9,
                    measuredAt = tSlow,
                    cycleId = cycleId,
                    source = "demo_seed"
                )
            )
            tSlow += 30 * 60_000L
        }

        // Build rollups for the seeded window so local history APIs work immediately.
        recomputeRecentDailySummaries(daysBack = 2)
    }

    // ── Fall risk log ───────────────────────────────────────────────

    suspend fun insertFallRiskLog(entity: FallRiskLogEntity): Long = withContext(Dispatchers.IO) {
        db.fallRiskLogDao().insert(entity)
    }

    suspend fun latestFallRiskLog() = withContext(Dispatchers.IO) { db.fallRiskLogDao().latest() }

    suspend fun fallRiskLogBetween(fromMs: Long, toMs: Long, limit: Int = 500) =
        withContext(Dispatchers.IO) { db.fallRiskLogDao().recent(fromMs, toMs, limit) }

    // ── Fall events ─────────────────────────────────────────────────

    suspend fun insertFallEvent(entity: FallEventEntity): Long = withContext(Dispatchers.IO) {
        db.fallEventDao().insert(entity)
    }

    suspend fun latestFallEvent() = withContext(Dispatchers.IO) { db.fallEventDao().latest() }

    suspend fun fallEventsBetween(fromMs: Long, toMs: Long, limit: Int = 200) =
        withContext(Dispatchers.IO) { db.fallEventDao().recent(fromMs, toMs, limit) }

    // ── Emergency contacts ──────────────────────────────────────────

    suspend fun insertEmergencyContact(name: String, phone: String): Long = withContext(Dispatchers.IO) {
        db.emergencyContactDao().insert(
            EmergencyContactEntity(name = name, phone = phone, createdAt = System.currentTimeMillis())
        )
    }

    suspend fun updateEmergencyContact(id: Long, name: String, phone: String) = withContext(Dispatchers.IO) {
        db.emergencyContactDao().update(id, name, phone)
    }

    suspend fun deleteEmergencyContact(id: Long) = withContext(Dispatchers.IO) {
        db.emergencyContactDao().delete(id)
    }

    suspend fun allEmergencyContacts() = withContext(Dispatchers.IO) { db.emergencyContactDao().all() }

    suspend fun emergencyContactCount() = withContext(Dispatchers.IO) { db.emergencyContactDao().count() }

    // ── Phone mode sessions ─────────────────────────────────────────

    suspend fun startPhoneModeSession(mode: String, startedAt: Long): Long = withContext(Dispatchers.IO) {
        db.phoneModeSessionDao().insert(PhoneModeSessionEntity(mode = mode, startedAt = startedAt))
    }

    suspend fun closeOpenPhoneModeSessions(endedAt: Long) = withContext(Dispatchers.IO) {
        db.phoneModeSessionDao().closeOpen(endedAt)
    }

    suspend fun phoneModeSessionsBetween(fromMs: Long, toMs: Long, limit: Int = 200) = withContext(Dispatchers.IO) {
        db.phoneModeSessionDao().between(fromMs, toMs, limit)
    }

    suspend fun pendingRowCount(): Int = withContext(Dispatchers.IO) {
        db.heartRateDao().unsyncedCount() + db.spo2Dao().unsyncedCount() + db.stressDao().unsyncedCount() +
            db.bloodPressureDao().unsyncedCount() + db.hrvDao().unsyncedCount() +
            db.temperatureDao().unsyncedCount() + db.stepsSnapshotDao().unsyncedCount()
    }

    // ── Internals ───────────────────────────────────────────────────

    private suspend fun recomputeRecentDailySummaries(daysBack: Long) {
        val todayStart = localDayStartMs(System.currentTimeMillis())
        val vitals = listOf(
            "heart_rate", "spo2", "stress", "blood_pressure", "hrv", "temperature", "steps"
        )
        for (i in 0..daysBack) {
            val dayStart = todayStart - i * DAY_MS
            val dayEnd = dayStart + DAY_MS - 1
            for (v in vitals) {
                val raw = daySummaryFromRaw(v, dayStart, dayEnd)
                if ((raw["count"] as? Int ?: 0) > 0 || (raw["steps"] as? Int ?: 0) > 0) {
                    upsertSummaryMap(v, dayStart, raw, origin = "local")
                }
            }
        }
    }

    private suspend fun safeRefreshDailySummary(vital: String, measuredAt: Long) {
        try {
            refreshDailySummary(vital, measuredAt)
        } catch (e: Exception) {
            // Rollup failure must never fail the raw insert that already succeeded.
            Log.w(TAG, "daily summary refresh failed for $vital", e)
        }
    }

    private suspend fun refreshDailySummary(vital: String, measuredAt: Long) {
        val dayStart = localDayStartMs(measuredAt)
        val dayEnd = dayStart + DAY_MS - 1
        val raw = daySummaryFromRaw(vital, dayStart, dayEnd)
        upsertSummaryMap(vital, dayStart, raw, origin = "local")
    }

    private suspend fun daySummaryFromRaw(vital: String, dayStart: Long, dayEnd: Long): Map<String, Any?> {
        return when (vital) {
            "heart_rate" -> {
                val agg = db.heartRateDao().dailyAggregate(dayStart, dayEnd)
                val last = db.heartRateDao().latest()?.takeIf { it.measuredAt in dayStart..dayEnd }
                mapOf(
                    "avg" to agg.avg, "min" to agg.min, "max" to agg.max, "count" to agg.count,
                    "lastValue" to last?.valueBpm, "lastMeasuredAt" to last?.measuredAt
                )
            }
            "spo2" -> {
                val agg = db.spo2Dao().dailyAggregate(dayStart, dayEnd)
                val last = db.spo2Dao().latest()?.takeIf { it.measuredAt in dayStart..dayEnd }
                mapOf(
                    "avg" to agg.avg, "min" to agg.min, "max" to agg.max, "count" to agg.count,
                    "lastValue" to last?.valuePct, "lastMeasuredAt" to last?.measuredAt
                )
            }
            "stress" -> {
                val agg = db.stressDao().dailyAggregate(dayStart, dayEnd)
                val last = db.stressDao().latest()?.takeIf { it.measuredAt in dayStart..dayEnd }
                mapOf(
                    "avg" to agg.avg, "min" to agg.min, "max" to agg.max, "count" to agg.count,
                    "lastValue" to last?.value, "lastMeasuredAt" to last?.measuredAt
                )
            }
            "blood_pressure" -> {
                val agg = db.bloodPressureDao().dailyAggregate(dayStart, dayEnd)
                val last = db.bloodPressureDao().latest()?.takeIf { it.measuredAt in dayStart..dayEnd }
                mapOf(
                    "avg" to agg.avgSbp, "min" to agg.minSbp, "max" to agg.maxSbp, "count" to agg.count,
                    "avgSecondary" to agg.avgDbp, "minSecondary" to agg.minDbp, "maxSecondary" to agg.maxDbp,
                    "avgSbp" to agg.avgSbp, "minSbp" to agg.minSbp, "maxSbp" to agg.maxSbp,
                    "avgDbp" to agg.avgDbp, "minDbp" to agg.minDbp, "maxDbp" to agg.maxDbp,
                    "lastSbp" to last?.systolic, "lastDbp" to last?.diastolic, "lastMeasuredAt" to last?.measuredAt
                )
            }
            "hrv" -> {
                val agg = db.hrvDao().dailyAggregate(dayStart, dayEnd)
                val last = db.hrvDao().latest()?.takeIf { it.measuredAt in dayStart..dayEnd }
                mapOf(
                    "avg" to agg.avg, "min" to agg.min, "max" to agg.max, "count" to agg.count,
                    "lastValue" to last?.valueMs, "lastMeasuredAt" to last?.measuredAt
                )
            }
            "temperature" -> {
                val agg = db.temperatureDao().dailyAggregate(dayStart, dayEnd)
                val last = db.temperatureDao().latest()?.takeIf { it.measuredAt in dayStart..dayEnd }
                mapOf(
                    "avg" to agg.avg, "min" to agg.min, "max" to agg.max, "count" to agg.count,
                    "lastValue" to last?.valueC, "lastMeasuredAt" to last?.measuredAt
                )
            }
            "steps" -> {
                val agg = db.stepsSnapshotDao().dailyMax(dayStart, dayEnd)
                mapOf(
                    "avg" to agg?.steps?.toDouble(),
                    "min" to agg?.steps,
                    "max" to agg?.steps,
                    "count" to if (agg?.steps != null) 1 else 0,
                    "steps" to agg?.steps,
                    "caloriesKcal" to agg?.caloriesKcal,
                    "distanceM" to agg?.distanceM,
                    "capturedAt" to agg?.capturedAt
                )
            }
            else -> mapOf("count" to 0)
        }
    }

    private suspend fun upsertSummaryMap(vital: String, dayStartMs: Long, map: Map<String, Any?>, origin: String) {
        fun num(key: String): Double? = (map[key] as? Number)?.toDouble()
        fun int(key: String): Int? = (map[key] as? Number)?.toInt()
        db.dailyVitalSummaryDao().upsert(
            DailyVitalSummaryEntity(
                vital = vital,
                dayEpochMs = dayStartMs,
                dateStr = dateStrOf(dayStartMs),
                avg = num("avg"),
                min = num("min"),
                max = num("max"),
                count = int("count") ?: 0,
                avgSecondary = num("avgSecondary") ?: num("avgDbp"),
                minSecondary = num("minSecondary") ?: num("minDbp"),
                maxSecondary = num("maxSecondary") ?: num("maxDbp"),
                steps = int("steps"),
                caloriesKcal = int("caloriesKcal"),
                distanceM = num("distanceM"),
                origin = origin,
                updatedAt = System.currentTimeMillis()
            )
        )
    }

    private fun summaryEntityToMap(e: DailyVitalSummaryEntity): Map<String, Any?> = mapOf(
        "vital" to e.vital,
        "dayEpochMs" to e.dayEpochMs,
        "dateStr" to e.dateStr,
        "avg" to e.avg,
        "min" to e.min,
        "max" to e.max,
        "count" to e.count,
        "avgSecondary" to e.avgSecondary,
        "minSecondary" to e.minSecondary,
        "maxSecondary" to e.maxSecondary,
        "avgSbp" to e.avg,
        "minSbp" to e.min,
        "maxSbp" to e.max,
        "avgDbp" to e.avgSecondary,
        "minDbp" to e.minSecondary,
        "maxDbp" to e.maxSecondary,
        "steps" to e.steps,
        "caloriesKcal" to e.caloriesKcal,
        "distanceM" to e.distanceM,
        "origin" to e.origin,
        "updatedAt" to e.updatedAt
    )

    private fun localDayStartMs(epochMs: Long): Long {
        val local = Instant.ofEpochMilli(epochMs).atZone(zone).toLocalDate()
        return local.atStartOfDay(zone).toInstant().toEpochMilli()
    }

    private fun dateStrOf(dayStartMs: Long): String =
        Instant.ofEpochMilli(dayStartMs).atZone(zone).toLocalDate().format(dateFmt)

    suspend fun clearMockData() = withContext(Dispatchers.IO) {
        val wdb = db.openHelper.writableDatabase
        wdb.execSQL("DELETE FROM reading_heart_rate WHERE source = 'demo_seed'")
        wdb.execSQL("DELETE FROM reading_spo2 WHERE source = 'demo_seed'")
        wdb.execSQL("DELETE FROM reading_hrv WHERE source = 'demo_seed'")
        wdb.execSQL("DELETE FROM reading_stress WHERE source = 'demo_seed'")
        wdb.execSQL("DELETE FROM reading_blood_pressure WHERE source = 'demo_seed'")
        wdb.execSQL("DELETE FROM reading_temperature WHERE source = 'demo_seed'")
        wdb.execSQL("DELETE FROM reading_steps_snapshot WHERE source = 'demo_seed'")
        wdb.execSQL("DELETE FROM daily_vital_summary")
    }

    companion object {
        private const val TAG = "ReadingRepository"
        const val DAY_MS = 24L * 60L * 60L * 1000L
        /** Keep synced raw samples longer so past-day hour charts stay offline-capable. */
        const val RETENTION_RAW_DAYS = 90L
        /** Local-derived day rollups (survive raw purge for long trends). */
        const val RETENTION_LOCAL_SUMMARY_DAYS = 400L
        /** Cloud-mirrored day rows for days never measured on this install. */
        const val RETENTION_CLOUD_CACHE_DAYS = 400L

        @Volatile
        private var INSTANCE: ReadingRepository? = null

        fun getInstance(context: Context): ReadingRepository =
            INSTANCE ?: synchronized(this) {
                INSTANCE ?: ReadingRepository(context.applicationContext).also { INSTANCE = it }
            }

        // Logout wipe (BlePlugin.clearPersonalData): close the underlying Room DB and drop
        // the cached facade so callers rebuild against a fresh, empty database.
        fun destroy() {
            synchronized(this) {
                QRingDatabase.destroy()
                INSTANCE = null
            }
        }
    }
}
