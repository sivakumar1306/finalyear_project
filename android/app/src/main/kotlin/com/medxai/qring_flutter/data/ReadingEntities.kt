package com.medxai.qring_flutter.data

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

// status: RUNNING | COMPLETED | ABORTED_DISCONNECT | SKIPPED_WORKOUT
@Entity(tableName = "measurement_cycle")
data class MeasurementCycleEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val startedAt: Long,
    val completedAt: Long? = null,
    val status: String,
    val abortedAtVital: String? = null
)

// source: "auto_cycle" | "manual" | "workout"
@Entity(tableName = "reading_heart_rate", indices = [Index("measuredAt"), Index("syncedAt")])
data class HeartRateReadingEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val valueBpm: Int,
    val measuredAt: Long,
    val cycleId: Long,
    val source: String,
    val syncedAt: Long? = null
)

@Entity(tableName = "reading_spo2", indices = [Index("measuredAt"), Index("syncedAt")])
data class Spo2ReadingEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val valuePct: Int,
    val measuredAt: Long,
    val cycleId: Long,
    val source: String,
    val syncedAt: Long? = null
)

@Entity(tableName = "reading_stress", indices = [Index("measuredAt"), Index("syncedAt")])
data class StressReadingEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val value: Int,
    val label: String? = null,
    val measuredAt: Long,
    val cycleId: Long,
    val source: String,
    val syncedAt: Long? = null
)

@Entity(tableName = "reading_blood_pressure", indices = [Index("measuredAt"), Index("syncedAt")])
data class BloodPressureReadingEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val systolic: Int,
    val diastolic: Int,
    val measuredAt: Long,
    val cycleId: Long,
    val source: String,
    val syncedAt: Long? = null
)

// Schema present now; table stays empty until Vital.HRV is enabled via MeasurementConfig.
@Entity(tableName = "reading_hrv", indices = [Index("measuredAt"), Index("syncedAt")])
data class HrvReadingEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val valueMs: Int,
    val measuredAt: Long,
    val cycleId: Long,
    val source: String,
    val syncedAt: Long? = null
)

// Schema present now; table stays empty until Vital.TEMPERATURE is enabled via MeasurementConfig.
@Entity(tableName = "reading_temperature", indices = [Index("measuredAt"), Index("syncedAt")])
data class TemperatureReadingEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val valueC: Double,
    val measuredAt: Long,
    val cycleId: Long,
    val source: String,
    val syncedAt: Long? = null
)

// One row per cycle, holding the ring's cumulative day-total as of that fetch —
// steps/calories/distance are cumulative counters, never per-cycle deltas.
@Entity(tableName = "reading_steps_snapshot", indices = [Index("capturedAt"), Index("syncedAt")])
data class StepsSnapshotEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val steps: Int,
    val caloriesKcal: Int,
    val distanceM: Double,
    val capturedAt: Long,
    val cycleId: Long,
    val source: String,
    val syncedAt: Long? = null
)
