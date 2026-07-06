package com.medxai.qring_flutter.data

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

// @SerializedName locks in stable JSON key names for Gson serialization (used by
// BlePlugin.getReadings/getLatestReading, consumed by Dart) regardless of what R8
// does to the actual Kotlin property/field names in a release build. Without this,
// a release build silently renamed these to single letters (a, b, c, ...), which
// broke every screen reading raw local-DB readings while leaving the separately
// server-computed today-summary (avg/min/max) unaffected — a very easy bug to miss
// since only the raw-reading JSON shape was affected.

// status: RUNNING | COMPLETED | ABORTED_DISCONNECT | SKIPPED_WORKOUT
@Entity(tableName = "measurement_cycle")
data class MeasurementCycleEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") val id: Long = 0,
    @SerializedName("startedAt") val startedAt: Long,
    @SerializedName("completedAt") val completedAt: Long? = null,
    @SerializedName("status") val status: String,
    @SerializedName("abortedAtVital") val abortedAtVital: String? = null
)

// source: "auto_cycle" | "manual" | "workout"
@Entity(tableName = "reading_heart_rate", indices = [Index("measuredAt"), Index("syncedAt")])
data class HeartRateReadingEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") val id: Long = 0,
    @SerializedName("valueBpm") val valueBpm: Int,
    @SerializedName("measuredAt") val measuredAt: Long,
    @SerializedName("cycleId") val cycleId: Long,
    @SerializedName("source") val source: String,
    @SerializedName("syncedAt") val syncedAt: Long? = null
)

@Entity(tableName = "reading_spo2", indices = [Index("measuredAt"), Index("syncedAt")])
data class Spo2ReadingEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") val id: Long = 0,
    @SerializedName("valuePct") val valuePct: Int,
    @SerializedName("measuredAt") val measuredAt: Long,
    @SerializedName("cycleId") val cycleId: Long,
    @SerializedName("source") val source: String,
    @SerializedName("syncedAt") val syncedAt: Long? = null
)

@Entity(tableName = "reading_stress", indices = [Index("measuredAt"), Index("syncedAt")])
data class StressReadingEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") val id: Long = 0,
    @SerializedName("value") val value: Int,
    @SerializedName("label") val label: String? = null,
    @SerializedName("measuredAt") val measuredAt: Long,
    @SerializedName("cycleId") val cycleId: Long,
    @SerializedName("source") val source: String,
    @SerializedName("syncedAt") val syncedAt: Long? = null
)

@Entity(tableName = "reading_blood_pressure", indices = [Index("measuredAt"), Index("syncedAt")])
data class BloodPressureReadingEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") val id: Long = 0,
    @SerializedName("systolic") val systolic: Int,
    @SerializedName("diastolic") val diastolic: Int,
    @SerializedName("measuredAt") val measuredAt: Long,
    @SerializedName("cycleId") val cycleId: Long,
    @SerializedName("source") val source: String,
    @SerializedName("syncedAt") val syncedAt: Long? = null
)

// Schema present now; table stays empty until Vital.HRV is enabled via MeasurementConfig.
@Entity(tableName = "reading_hrv", indices = [Index("measuredAt"), Index("syncedAt")])
data class HrvReadingEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") val id: Long = 0,
    @SerializedName("valueMs") val valueMs: Int,
    @SerializedName("measuredAt") val measuredAt: Long,
    @SerializedName("cycleId") val cycleId: Long,
    @SerializedName("source") val source: String,
    @SerializedName("syncedAt") val syncedAt: Long? = null
)

// Schema present now; table stays empty until Vital.TEMPERATURE is enabled via MeasurementConfig.
@Entity(tableName = "reading_temperature", indices = [Index("measuredAt"), Index("syncedAt")])
data class TemperatureReadingEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") val id: Long = 0,
    @SerializedName("valueC") val valueC: Double,
    @SerializedName("measuredAt") val measuredAt: Long,
    @SerializedName("cycleId") val cycleId: Long,
    @SerializedName("source") val source: String,
    @SerializedName("syncedAt") val syncedAt: Long? = null
)

// One row per cycle, holding the ring's cumulative day-total as of that fetch —
// steps/calories/distance are cumulative counters, never per-cycle deltas.
@Entity(tableName = "reading_steps_snapshot", indices = [Index("capturedAt"), Index("syncedAt")])
data class StepsSnapshotEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") val id: Long = 0,
    @SerializedName("steps") val steps: Int,
    @SerializedName("caloriesKcal") val caloriesKcal: Int,
    @SerializedName("distanceM") val distanceM: Double,
    @SerializedName("capturedAt") val capturedAt: Long,
    @SerializedName("cycleId") val cycleId: Long,
    @SerializedName("source") val source: String,
    @SerializedName("syncedAt") val syncedAt: Long? = null
)
