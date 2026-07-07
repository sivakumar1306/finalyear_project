package com.medxai.qring_flutter.data

import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.withContext

// Facade over QRingDatabase used both by MeasurementLoopManager (writes) and by
// BlePlugin's new MethodChannel query methods (reads). Room requires non-main-thread
// access, so every call here hops onto Dispatchers.IO.
class ReadingRepository private constructor(context: Context) {
    private val db = QRingDatabase.getInstance(context)
    val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    suspend fun startCycle(): Long = withContext(Dispatchers.IO) {
        db.measurementCycleDao().insert(MeasurementCycleEntity(startedAt = System.currentTimeMillis(), status = "RUNNING"))
    }

    suspend fun completeCycle(cycleId: Long, status: String, abortedAtVital: String? = null) = withContext(Dispatchers.IO) {
        db.measurementCycleDao().complete(cycleId, status, System.currentTimeMillis(), abortedAtVital)
    }

    suspend fun cyclesBetween(fromMs: Long, toMs: Long) = withContext(Dispatchers.IO) {
        db.measurementCycleDao().cyclesBetween(fromMs, toMs)
    }

    // ── Inserts ──────────────────────────────────────────────────────

    suspend fun insertHeartRate(bpm: Int, cycleId: Long, source: String): Long = withContext(Dispatchers.IO) {
        db.heartRateDao().insert(HeartRateReadingEntity(valueBpm = bpm, measuredAt = System.currentTimeMillis(), cycleId = cycleId, source = source))
    }

    suspend fun insertSpo2(pct: Int, cycleId: Long, source: String): Long = withContext(Dispatchers.IO) {
        db.spo2Dao().insert(Spo2ReadingEntity(valuePct = pct, measuredAt = System.currentTimeMillis(), cycleId = cycleId, source = source))
    }

    suspend fun insertStress(value: Int, label: String?, cycleId: Long, source: String): Long = withContext(Dispatchers.IO) {
        db.stressDao().insert(StressReadingEntity(value = value, label = label, measuredAt = System.currentTimeMillis(), cycleId = cycleId, source = source))
    }

    suspend fun insertBloodPressure(sbp: Int, dbp: Int, cycleId: Long, source: String): Long = withContext(Dispatchers.IO) {
        db.bloodPressureDao().insert(BloodPressureReadingEntity(systolic = sbp, diastolic = dbp, measuredAt = System.currentTimeMillis(), cycleId = cycleId, source = source))
    }

    suspend fun insertHrv(valueMs: Int, cycleId: Long, source: String): Long = withContext(Dispatchers.IO) {
        db.hrvDao().insert(HrvReadingEntity(valueMs = valueMs, measuredAt = System.currentTimeMillis(), cycleId = cycleId, source = source))
    }

    suspend fun insertTemperature(valueC: Double, cycleId: Long, source: String): Long = withContext(Dispatchers.IO) {
        db.temperatureDao().insert(TemperatureReadingEntity(valueC = valueC, measuredAt = System.currentTimeMillis(), cycleId = cycleId, source = source))
    }

    suspend fun insertStepsSnapshot(steps: Int, caloriesKcal: Int, distanceM: Double, cycleId: Long, source: String): Long = withContext(Dispatchers.IO) {
        db.stepsSnapshotDao().insert(StepsSnapshotEntity(steps = steps, caloriesKcal = caloriesKcal, distanceM = distanceM, capturedAt = System.currentTimeMillis(), cycleId = cycleId, source = source))
    }

    // ── Latest / range queries (BlePlugin read surface) ─────────────

    suspend fun latestHeartRate() = withContext(Dispatchers.IO) { db.heartRateDao().latest() }
    suspend fun latestSpo2() = withContext(Dispatchers.IO) { db.spo2Dao().latest() }
    suspend fun latestStress() = withContext(Dispatchers.IO) { db.stressDao().latest() }
    suspend fun latestBloodPressure() = withContext(Dispatchers.IO) { db.bloodPressureDao().latest() }
    suspend fun latestHrv() = withContext(Dispatchers.IO) { db.hrvDao().latest() }
    suspend fun latestTemperature() = withContext(Dispatchers.IO) { db.temperatureDao().latest() }
    suspend fun latestStepsSnapshot() = withContext(Dispatchers.IO) { db.stepsSnapshotDao().latest() }

    suspend fun heartRateAggregate(dayStart: Long, dayEnd: Long) = withContext(Dispatchers.IO) { db.heartRateDao().dailyAggregate(dayStart, dayEnd) }
    suspend fun spo2Aggregate(dayStart: Long, dayEnd: Long) = withContext(Dispatchers.IO) { db.spo2Dao().dailyAggregate(dayStart, dayEnd) }
    suspend fun stressAggregate(dayStart: Long, dayEnd: Long) = withContext(Dispatchers.IO) { db.stressDao().dailyAggregate(dayStart, dayEnd) }
    suspend fun bpAggregate(dayStart: Long, dayEnd: Long) = withContext(Dispatchers.IO) { db.bloodPressureDao().dailyAggregate(dayStart, dayEnd) }
    suspend fun hrvAggregate(dayStart: Long, dayEnd: Long) = withContext(Dispatchers.IO) { db.hrvDao().dailyAggregate(dayStart, dayEnd) }
    suspend fun temperatureAggregate(dayStart: Long, dayEnd: Long) = withContext(Dispatchers.IO) { db.temperatureDao().dailyAggregate(dayStart, dayEnd) }
    // Steps aggregate is deliberately MAX-of-day, never SUM — see StepsSnapshotDao.dailyMax.
    suspend fun stepsAggregate(dayStart: Long, dayEnd: Long) = withContext(Dispatchers.IO) { db.stepsSnapshotDao().dailyMax(dayStart, dayEnd) }

    suspend fun heartRateBetween(fromMs: Long, toMs: Long, limit: Int) = withContext(Dispatchers.IO) { db.heartRateDao().readingsBetween(fromMs, toMs, limit) }
    suspend fun spo2Between(fromMs: Long, toMs: Long, limit: Int) = withContext(Dispatchers.IO) { db.spo2Dao().readingsBetween(fromMs, toMs, limit) }
    suspend fun stressBetween(fromMs: Long, toMs: Long, limit: Int) = withContext(Dispatchers.IO) { db.stressDao().readingsBetween(fromMs, toMs, limit) }
    suspend fun bpBetween(fromMs: Long, toMs: Long, limit: Int) = withContext(Dispatchers.IO) { db.bloodPressureDao().readingsBetween(fromMs, toMs, limit) }
    suspend fun hrvBetween(fromMs: Long, toMs: Long, limit: Int) = withContext(Dispatchers.IO) { db.hrvDao().readingsBetween(fromMs, toMs, limit) }
    suspend fun temperatureBetween(fromMs: Long, toMs: Long, limit: Int) = withContext(Dispatchers.IO) { db.temperatureDao().readingsBetween(fromMs, toMs, limit) }
    suspend fun stepsBetween(fromMs: Long, toMs: Long, limit: Int) = withContext(Dispatchers.IO) { db.stepsSnapshotDao().snapshotsBetween(fromMs, toMs, limit) }

    // ── Sync surface (SupabaseSyncManager) ──────────────────────────

    suspend fun unsyncedHeartRate(limit: Int) = withContext(Dispatchers.IO) { db.heartRateDao().unsyncedBatch(limit) }
    suspend fun unsyncedSpo2(limit: Int) = withContext(Dispatchers.IO) { db.spo2Dao().unsyncedBatch(limit) }
    suspend fun unsyncedStress(limit: Int) = withContext(Dispatchers.IO) { db.stressDao().unsyncedBatch(limit) }
    suspend fun unsyncedBloodPressure(limit: Int) = withContext(Dispatchers.IO) { db.bloodPressureDao().unsyncedBatch(limit) }
    suspend fun unsyncedHrv(limit: Int) = withContext(Dispatchers.IO) { db.hrvDao().unsyncedBatch(limit) }
    suspend fun unsyncedTemperature(limit: Int) = withContext(Dispatchers.IO) { db.temperatureDao().unsyncedBatch(limit) }
    suspend fun unsyncedSteps(limit: Int) = withContext(Dispatchers.IO) { db.stepsSnapshotDao().unsyncedBatch(limit) }

    suspend fun markHeartRateSynced(ids: List<Long>, at: Long) = withContext(Dispatchers.IO) { db.heartRateDao().markSynced(ids, at) }
    suspend fun markSpo2Synced(ids: List<Long>, at: Long) = withContext(Dispatchers.IO) { db.spo2Dao().markSynced(ids, at) }
    suspend fun markStressSynced(ids: List<Long>, at: Long) = withContext(Dispatchers.IO) { db.stressDao().markSynced(ids, at) }
    suspend fun markBloodPressureSynced(ids: List<Long>, at: Long) = withContext(Dispatchers.IO) { db.bloodPressureDao().markSynced(ids, at) }
    suspend fun markHrvSynced(ids: List<Long>, at: Long) = withContext(Dispatchers.IO) { db.hrvDao().markSynced(ids, at) }
    suspend fun markTemperatureSynced(ids: List<Long>, at: Long) = withContext(Dispatchers.IO) { db.temperatureDao().markSynced(ids, at) }
    suspend fun markStepsSynced(ids: List<Long>, at: Long) = withContext(Dispatchers.IO) { db.stepsSnapshotDao().markSynced(ids, at) }

    // ── Demo data seeding (dev/testing only) ────────────────────────
    //
    // Fills the last `hoursBack` hours with synthetic-but-plausible readings so a
    // freshly reinstalled app has something to show without needing the ring
    // connected. Inserted rows are tagged source = "demo_seed" and get real
    // historical `measuredAt` timestamps (not "now"), unlike the live insert*
    // helpers above.
    suspend fun seedDemoData(hoursBack: Long = 3): Unit = withContext(Dispatchers.IO) {
        val now = System.currentTimeMillis()
        val start = now - hoursBack * 3_600_000L
        val cycleId = db.measurementCycleDao().insert(
            MeasurementCycleEntity(startedAt = start, completedAt = now, status = "COMPLETED")
        )
        val rnd = kotlin.random.Random(now)

        // Heart rate / SpO2 / stress / HRV / steps: every 5 minutes across the window.
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
            val label = when { stress < 30 -> "relaxed"; stress < 60 -> "normal"; else -> "elevated" }
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
                    steps = cumulativeSteps, caloriesKcal = cumulativeCalories, distanceM = cumulativeDistance,
                    capturedAt = t, cycleId = cycleId, source = "demo_seed"
                )
            )
            t += 5 * 60_000L
        }

        // Blood pressure / temperature: measured less often, every 30 minutes.
        var tSlow = start
        while (tSlow <= now) {
            db.bloodPressureDao().insert(
                BloodPressureReadingEntity(
                    systolic = 108 + rnd.nextInt(20), diastolic = 68 + rnd.nextInt(14),
                    measuredAt = tSlow, cycleId = cycleId, source = "demo_seed"
                )
            )
            db.temperatureDao().insert(
                TemperatureReadingEntity(valueC = 36.1 + rnd.nextDouble() * 0.9, measuredAt = tSlow, cycleId = cycleId, source = "demo_seed")
            )
            tSlow += 30 * 60_000L
        }
    }

    // ── Fall risk log (Phase 1 — silent scoring, see FallRiskAnalyzer) ──

    suspend fun insertFallRiskLog(entity: FallRiskLogEntity): Long = withContext(Dispatchers.IO) {
        db.fallRiskLogDao().insert(entity)
    }

    suspend fun latestFallRiskLog() = withContext(Dispatchers.IO) { db.fallRiskLogDao().latest() }

    suspend fun fallRiskLogBetween(fromMs: Long, toMs: Long, limit: Int = 500) =
        withContext(Dispatchers.IO) { db.fallRiskLogDao().recent(fromMs, toMs, limit) }

    // ── Fall events (Phase 2 — phone-motion detector, see FallMotionDetector) ──

    suspend fun insertFallEvent(entity: FallEventEntity): Long = withContext(Dispatchers.IO) {
        db.fallEventDao().insert(entity)
    }

    suspend fun latestFallEvent() = withContext(Dispatchers.IO) { db.fallEventDao().latest() }

    suspend fun fallEventsBetween(fromMs: Long, toMs: Long, limit: Int = 200) =
        withContext(Dispatchers.IO) { db.fallEventDao().recent(fromMs, toMs, limit) }

    // ── Emergency contacts (native-persisted, see EmergencyContactEntity) ──

    suspend fun insertEmergencyContact(name: String, phone: String): Long = withContext(Dispatchers.IO) {
        db.emergencyContactDao().insert(EmergencyContactEntity(name = name, phone = phone, createdAt = System.currentTimeMillis()))
    }

    suspend fun deleteEmergencyContact(id: Long) = withContext(Dispatchers.IO) {
        db.emergencyContactDao().delete(id)
    }

    suspend fun allEmergencyContacts() = withContext(Dispatchers.IO) { db.emergencyContactDao().all() }

    suspend fun emergencyContactCount() = withContext(Dispatchers.IO) { db.emergencyContactDao().count() }

    suspend fun pendingRowCount(): Int = withContext(Dispatchers.IO) {
        db.heartRateDao().unsyncedCount() + db.spo2Dao().unsyncedCount() + db.stressDao().unsyncedCount() +
            db.bloodPressureDao().unsyncedCount() + db.hrvDao().unsyncedCount() +
            db.temperatureDao().unsyncedCount() + db.stepsSnapshotDao().unsyncedCount()
    }

    companion object {
        @Volatile private var INSTANCE: ReadingRepository? = null

        fun getInstance(context: Context): ReadingRepository =
            INSTANCE ?: synchronized(this) {
                INSTANCE ?: ReadingRepository(context.applicationContext).also { INSTANCE = it }
            }
    }
}
