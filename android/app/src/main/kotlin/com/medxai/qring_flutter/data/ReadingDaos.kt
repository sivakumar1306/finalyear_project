package com.medxai.qring_flutter.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query

data class DailyAggregate(val avg: Double?, val min: Int?, val max: Int?, val count: Int)

data class BpDailyAggregate(
    val avgSbp: Double?, val minSbp: Int?, val maxSbp: Int?,
    val avgDbp: Double?, val minDbp: Int?, val maxDbp: Int?,
    val count: Int
)

data class DailyStepsAggregate(
    val steps: Int?, val caloriesKcal: Int?, val distanceM: Double?, val capturedAt: Long?
)

@Dao
interface MeasurementCycleDao {
    @Insert
    suspend fun insert(entity: MeasurementCycleEntity): Long

    @Query("UPDATE measurement_cycle SET status = :status, completedAt = :completedAt, abortedAtVital = :abortedAtVital WHERE id = :id")
    suspend fun complete(id: Long, status: String, completedAt: Long?, abortedAtVital: String?)

    @Query("SELECT * FROM measurement_cycle WHERE startedAt BETWEEN :fromMs AND :toMs ORDER BY startedAt DESC")
    suspend fun cyclesBetween(fromMs: Long, toMs: Long): List<MeasurementCycleEntity>
}

@Dao
interface HeartRateReadingDao {
    @Insert
    suspend fun insert(entity: HeartRateReadingEntity): Long

    @Query("SELECT * FROM reading_heart_rate WHERE syncedAt IS NULL ORDER BY measuredAt ASC LIMIT :limit")
    suspend fun unsyncedBatch(limit: Int): List<HeartRateReadingEntity>

    @Query("SELECT COUNT(*) FROM reading_heart_rate WHERE syncedAt IS NULL")
    suspend fun unsyncedCount(): Int

    @Query("UPDATE reading_heart_rate SET syncedAt = :syncedAt WHERE id IN (:ids)")
    suspend fun markSynced(ids: List<Long>, syncedAt: Long)

    @Query("SELECT * FROM reading_heart_rate WHERE measuredAt BETWEEN :fromMs AND :toMs ORDER BY measuredAt ASC LIMIT :limit")
    suspend fun readingsBetween(fromMs: Long, toMs: Long, limit: Int): List<HeartRateReadingEntity>

    @Query("SELECT * FROM reading_heart_rate ORDER BY measuredAt DESC LIMIT 1")
    suspend fun latest(): HeartRateReadingEntity?

    @Query("SELECT AVG(valueBpm) as avg, MIN(valueBpm) as min, MAX(valueBpm) as max, COUNT(*) as count FROM reading_heart_rate WHERE measuredAt BETWEEN :dayStart AND :dayEnd")
    suspend fun dailyAggregate(dayStart: Long, dayEnd: Long): DailyAggregate
}

@Dao
interface Spo2ReadingDao {
    @Insert
    suspend fun insert(entity: Spo2ReadingEntity): Long

    @Query("SELECT * FROM reading_spo2 WHERE syncedAt IS NULL ORDER BY measuredAt ASC LIMIT :limit")
    suspend fun unsyncedBatch(limit: Int): List<Spo2ReadingEntity>

    @Query("SELECT COUNT(*) FROM reading_spo2 WHERE syncedAt IS NULL")
    suspend fun unsyncedCount(): Int

    @Query("UPDATE reading_spo2 SET syncedAt = :syncedAt WHERE id IN (:ids)")
    suspend fun markSynced(ids: List<Long>, syncedAt: Long)

    @Query("SELECT * FROM reading_spo2 WHERE measuredAt BETWEEN :fromMs AND :toMs ORDER BY measuredAt ASC LIMIT :limit")
    suspend fun readingsBetween(fromMs: Long, toMs: Long, limit: Int): List<Spo2ReadingEntity>

    @Query("SELECT * FROM reading_spo2 ORDER BY measuredAt DESC LIMIT 1")
    suspend fun latest(): Spo2ReadingEntity?

    @Query("SELECT AVG(valuePct) as avg, MIN(valuePct) as min, MAX(valuePct) as max, COUNT(*) as count FROM reading_spo2 WHERE measuredAt BETWEEN :dayStart AND :dayEnd")
    suspend fun dailyAggregate(dayStart: Long, dayEnd: Long): DailyAggregate
}

@Dao
interface StressReadingDao {
    @Insert
    suspend fun insert(entity: StressReadingEntity): Long

    @Query("SELECT * FROM reading_stress WHERE syncedAt IS NULL ORDER BY measuredAt ASC LIMIT :limit")
    suspend fun unsyncedBatch(limit: Int): List<StressReadingEntity>

    @Query("SELECT COUNT(*) FROM reading_stress WHERE syncedAt IS NULL")
    suspend fun unsyncedCount(): Int

    @Query("UPDATE reading_stress SET syncedAt = :syncedAt WHERE id IN (:ids)")
    suspend fun markSynced(ids: List<Long>, syncedAt: Long)

    @Query("SELECT * FROM reading_stress WHERE measuredAt BETWEEN :fromMs AND :toMs ORDER BY measuredAt ASC LIMIT :limit")
    suspend fun readingsBetween(fromMs: Long, toMs: Long, limit: Int): List<StressReadingEntity>

    @Query("SELECT * FROM reading_stress ORDER BY measuredAt DESC LIMIT 1")
    suspend fun latest(): StressReadingEntity?

    @Query("SELECT AVG(value) as avg, MIN(value) as min, MAX(value) as max, COUNT(*) as count FROM reading_stress WHERE measuredAt BETWEEN :dayStart AND :dayEnd")
    suspend fun dailyAggregate(dayStart: Long, dayEnd: Long): DailyAggregate
}

@Dao
interface BloodPressureReadingDao {
    @Insert
    suspend fun insert(entity: BloodPressureReadingEntity): Long

    @Query("SELECT * FROM reading_blood_pressure WHERE syncedAt IS NULL ORDER BY measuredAt ASC LIMIT :limit")
    suspend fun unsyncedBatch(limit: Int): List<BloodPressureReadingEntity>

    @Query("SELECT COUNT(*) FROM reading_blood_pressure WHERE syncedAt IS NULL")
    suspend fun unsyncedCount(): Int

    @Query("UPDATE reading_blood_pressure SET syncedAt = :syncedAt WHERE id IN (:ids)")
    suspend fun markSynced(ids: List<Long>, syncedAt: Long)

    @Query("SELECT * FROM reading_blood_pressure WHERE measuredAt BETWEEN :fromMs AND :toMs ORDER BY measuredAt ASC LIMIT :limit")
    suspend fun readingsBetween(fromMs: Long, toMs: Long, limit: Int): List<BloodPressureReadingEntity>

    @Query("SELECT * FROM reading_blood_pressure ORDER BY measuredAt DESC LIMIT 1")
    suspend fun latest(): BloodPressureReadingEntity?

    @Query("""
        SELECT AVG(systolic) as avgSbp, MIN(systolic) as minSbp, MAX(systolic) as maxSbp,
               AVG(diastolic) as avgDbp, MIN(diastolic) as minDbp, MAX(diastolic) as maxDbp,
               COUNT(*) as count
        FROM reading_blood_pressure WHERE measuredAt BETWEEN :dayStart AND :dayEnd
    """)
    suspend fun dailyAggregate(dayStart: Long, dayEnd: Long): BpDailyAggregate
}

@Dao
interface HrvReadingDao {
    @Insert
    suspend fun insert(entity: HrvReadingEntity): Long

    @Query("SELECT * FROM reading_hrv WHERE syncedAt IS NULL ORDER BY measuredAt ASC LIMIT :limit")
    suspend fun unsyncedBatch(limit: Int): List<HrvReadingEntity>

    @Query("SELECT COUNT(*) FROM reading_hrv WHERE syncedAt IS NULL")
    suspend fun unsyncedCount(): Int

    @Query("UPDATE reading_hrv SET syncedAt = :syncedAt WHERE id IN (:ids)")
    suspend fun markSynced(ids: List<Long>, syncedAt: Long)

    @Query("SELECT * FROM reading_hrv WHERE measuredAt BETWEEN :fromMs AND :toMs ORDER BY measuredAt ASC LIMIT :limit")
    suspend fun readingsBetween(fromMs: Long, toMs: Long, limit: Int): List<HrvReadingEntity>

    @Query("SELECT * FROM reading_hrv ORDER BY measuredAt DESC LIMIT 1")
    suspend fun latest(): HrvReadingEntity?

    @Query("SELECT AVG(valueMs) as avg, MIN(valueMs) as min, MAX(valueMs) as max, COUNT(*) as count FROM reading_hrv WHERE measuredAt BETWEEN :dayStart AND :dayEnd")
    suspend fun dailyAggregate(dayStart: Long, dayEnd: Long): DailyAggregate
}

@Dao
interface TemperatureReadingDao {
    @Insert
    suspend fun insert(entity: TemperatureReadingEntity): Long

    @Query("SELECT * FROM reading_temperature WHERE syncedAt IS NULL ORDER BY measuredAt ASC LIMIT :limit")
    suspend fun unsyncedBatch(limit: Int): List<TemperatureReadingEntity>

    @Query("SELECT COUNT(*) FROM reading_temperature WHERE syncedAt IS NULL")
    suspend fun unsyncedCount(): Int

    @Query("UPDATE reading_temperature SET syncedAt = :syncedAt WHERE id IN (:ids)")
    suspend fun markSynced(ids: List<Long>, syncedAt: Long)

    @Query("SELECT * FROM reading_temperature WHERE measuredAt BETWEEN :fromMs AND :toMs ORDER BY measuredAt ASC LIMIT :limit")
    suspend fun readingsBetween(fromMs: Long, toMs: Long, limit: Int): List<TemperatureReadingEntity>

    @Query("SELECT * FROM reading_temperature ORDER BY measuredAt DESC LIMIT 1")
    suspend fun latest(): TemperatureReadingEntity?

    @Query("SELECT AVG(valueC) as avg, MIN(valueC) as min, MAX(valueC) as max, COUNT(*) as count FROM reading_temperature WHERE measuredAt BETWEEN :dayStart AND :dayEnd")
    suspend fun dailyAggregate(dayStart: Long, dayEnd: Long): DailyAggregateDouble
}

data class DailyAggregateDouble(val avg: Double?, val min: Double?, val max: Double?, val count: Int)

@Dao
interface FallRiskLogDao {
    @Insert
    suspend fun insert(entity: FallRiskLogEntity): Long

    @Query("SELECT * FROM fall_risk_log ORDER BY computedAt DESC LIMIT 1")
    suspend fun latest(): FallRiskLogEntity?

    @Query("SELECT * FROM fall_risk_log WHERE computedAt BETWEEN :fromMs AND :toMs ORDER BY computedAt DESC LIMIT :limit")
    suspend fun recent(fromMs: Long, toMs: Long, limit: Int): List<FallRiskLogEntity>
}

@Dao
interface FallEventDao {
    @Insert
    suspend fun insert(entity: FallEventEntity): Long

    @Query("SELECT * FROM fall_event ORDER BY detectedAt DESC LIMIT 1")
    suspend fun latest(): FallEventEntity?

    @Query("SELECT * FROM fall_event WHERE detectedAt BETWEEN :fromMs AND :toMs ORDER BY detectedAt DESC LIMIT :limit")
    suspend fun recent(fromMs: Long, toMs: Long, limit: Int): List<FallEventEntity>
}

@Dao
interface EmergencyContactDao {
    @Insert
    suspend fun insert(entity: EmergencyContactEntity): Long

    @Query("UPDATE emergency_contact SET name = :name, phone = :phone WHERE id = :id")
    suspend fun update(id: Long, name: String, phone: String)

    @Query("DELETE FROM emergency_contact WHERE id = :id")
    suspend fun delete(id: Long)

    @Query("SELECT * FROM emergency_contact ORDER BY createdAt ASC")
    suspend fun all(): List<EmergencyContactEntity>

    @Query("SELECT COUNT(*) FROM emergency_contact")
    suspend fun count(): Int
}

@Dao
interface StepsSnapshotDao {
    @Insert
    suspend fun insert(entity: StepsSnapshotEntity): Long

    @Query("SELECT * FROM reading_steps_snapshot WHERE syncedAt IS NULL ORDER BY capturedAt ASC LIMIT :limit")
    suspend fun unsyncedBatch(limit: Int): List<StepsSnapshotEntity>

    @Query("SELECT COUNT(*) FROM reading_steps_snapshot WHERE syncedAt IS NULL")
    suspend fun unsyncedCount(): Int

    @Query("UPDATE reading_steps_snapshot SET syncedAt = :syncedAt WHERE id IN (:ids)")
    suspend fun markSynced(ids: List<Long>, syncedAt: Long)

    @Query("SELECT * FROM reading_steps_snapshot WHERE capturedAt BETWEEN :fromMs AND :toMs ORDER BY capturedAt ASC LIMIT :limit")
    suspend fun snapshotsBetween(fromMs: Long, toMs: Long, limit: Int): List<StepsSnapshotEntity>

    @Query("SELECT * FROM reading_steps_snapshot ORDER BY capturedAt DESC LIMIT 1")
    suspend fun latest(): StepsSnapshotEntity?

    // Steps/calories/distance are cumulative-to-date counters, not per-cycle deltas —
    // the day total is the snapshot with the highest step count, never a SUM across snapshots.
    @Query("""
        SELECT steps, caloriesKcal, distanceM, capturedAt FROM reading_steps_snapshot
        WHERE capturedAt BETWEEN :dayStart AND :dayEnd ORDER BY steps DESC LIMIT 1
    """)
    suspend fun dailyMax(dayStart: Long, dayEnd: Long): DailyStepsAggregate?
}
