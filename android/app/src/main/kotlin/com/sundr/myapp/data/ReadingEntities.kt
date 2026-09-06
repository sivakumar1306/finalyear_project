package com.sundr.myapp.data

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

// Unified per-attempt audit for Measurement Log screen (Settings → Measurement Log).
// Local-only, not cloud-synced. One row per vital attempt, grouped by cycleId.
// status: success|failed|timeout|yielded|rejected|aborted_disconnect|skipped_workout|sdk_guard_open|skipped_disabled|RUNNING
@Entity(
    tableName = "measurement_attempt",
    indices = [Index("cycleId"), Index("vital"), Index("status"), Index("startedAt"), Index("source")]
)
data class MeasurementAttemptEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") val id: Long = 0,
    @SerializedName("vital") val vital: String,
    @SerializedName("source") val source: String,
    @SerializedName("cycleId") val cycleId: Long,
    @SerializedName("startedAt") val startedAt: Long,
    @SerializedName("endedAt") val endedAt: Long? = null,
    @SerializedName("status") val status: String,
    @SerializedName("error") val error: String? = null,
    @SerializedName("valueJson") val valueJson: String? = null
)

// source: "auto_cycle" | "manual" | "workout" | "demo_seed" | "cloud_cache"
// deviceAddress / extraJson enrich offline detail without requiring cloud.
@Entity(tableName = "reading_heart_rate", indices = [Index("measuredAt"), Index("syncedAt")])
data class HeartRateReadingEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") val id: Long = 0,
    @SerializedName("valueBpm") val valueBpm: Int,
    @SerializedName("measuredAt") val measuredAt: Long,
    @SerializedName("cycleId") val cycleId: Long,
    @SerializedName("source") val source: String,
    @SerializedName("syncedAt") val syncedAt: Long? = null,
    @SerializedName("deviceAddress") val deviceAddress: String? = null,
    @SerializedName("extraJson") val extraJson: String? = null
)

@Entity(tableName = "reading_spo2", indices = [Index("measuredAt"), Index("syncedAt")])
data class Spo2ReadingEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") val id: Long = 0,
    @SerializedName("valuePct") val valuePct: Int,
    @SerializedName("measuredAt") val measuredAt: Long,
    @SerializedName("cycleId") val cycleId: Long,
    @SerializedName("source") val source: String,
    @SerializedName("syncedAt") val syncedAt: Long? = null,
    @SerializedName("deviceAddress") val deviceAddress: String? = null,
    @SerializedName("extraJson") val extraJson: String? = null
)

@Entity(tableName = "reading_stress", indices = [Index("measuredAt"), Index("syncedAt")])
data class StressReadingEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") val id: Long = 0,
    @SerializedName("value") val value: Int,
    @SerializedName("label") val label: String? = null,
    @SerializedName("measuredAt") val measuredAt: Long,
    @SerializedName("cycleId") val cycleId: Long,
    @SerializedName("source") val source: String,
    @SerializedName("syncedAt") val syncedAt: Long? = null,
    @SerializedName("deviceAddress") val deviceAddress: String? = null,
    @SerializedName("extraJson") val extraJson: String? = null
)

@Entity(tableName = "reading_blood_pressure", indices = [Index("measuredAt"), Index("syncedAt")])
data class BloodPressureReadingEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") val id: Long = 0,
    @SerializedName("systolic") val systolic: Int,
    @SerializedName("diastolic") val diastolic: Int,
    @SerializedName("measuredAt") val measuredAt: Long,
    @SerializedName("cycleId") val cycleId: Long,
    @SerializedName("source") val source: String,
    @SerializedName("syncedAt") val syncedAt: Long? = null,
    @SerializedName("deviceAddress") val deviceAddress: String? = null,
    @SerializedName("extraJson") val extraJson: String? = null
)

@Entity(tableName = "reading_hrv", indices = [Index("measuredAt"), Index("syncedAt")])
data class HrvReadingEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") val id: Long = 0,
    @SerializedName("valueMs") val valueMs: Int,
    @SerializedName("measuredAt") val measuredAt: Long,
    @SerializedName("cycleId") val cycleId: Long,
    @SerializedName("source") val source: String,
    @SerializedName("syncedAt") val syncedAt: Long? = null,
    @SerializedName("deviceAddress") val deviceAddress: String? = null,
    @SerializedName("extraJson") val extraJson: String? = null
)

// Schema present now; table stays empty until Vital.TEMPERATURE is enabled via MeasurementConfig.
@Entity(tableName = "reading_temperature", indices = [Index("measuredAt"), Index("syncedAt")])
data class TemperatureReadingEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") val id: Long = 0,
    @SerializedName("valueC") val valueC: Double,
    @SerializedName("measuredAt") val measuredAt: Long,
    @SerializedName("cycleId") val cycleId: Long,
    @SerializedName("source") val source: String,
    @SerializedName("syncedAt") val syncedAt: Long? = null,
    @SerializedName("deviceAddress") val deviceAddress: String? = null,
    @SerializedName("extraJson") val extraJson: String? = null
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
    @SerializedName("syncedAt") val syncedAt: Long? = null,
    @SerializedName("deviceAddress") val deviceAddress: String? = null,
    @SerializedName("extraJson") val extraJson: String? = null
)

// Phase 1 of the fall-risk feature — computed silently on every NewReadingEvent and logged
// here for later correlation against real fall/near-fall reports. Not surfaced as a live
// alert yet; see FallRiskAnalyzer. componentsJson is a Gson-serialized breakdown of which
// signals contributed, kept as a string since Room can't store a Map directly.
@Entity(tableName = "fall_risk_log", indices = [Index("computedAt")])
data class FallRiskLogEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") val id: Long = 0,
    @SerializedName("score") val score: Int,
    @SerializedName("tier") val tier: String,
    @SerializedName("triggerVital") val triggerVital: String,
    @SerializedName("componentsJson") val componentsJson: String,
    @SerializedName("computedAt") val computedAt: Long
)

// Phase 2 — a candidate fall detected by FallMotionDetector's phone-accelerometer three-phase
// signature (free-fall -> impact -> stillness), corroborated against a concurrent vitals
// signal where possible. Logged silently, same as fall_risk_log — no user-facing alert yet.
@Entity(tableName = "fall_event", indices = [Index("detectedAt")])
data class FallEventEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") val id: Long = 0,
    @SerializedName("confidence") val confidence: Float,
    @SerializedName("corroborated") val corroborated: Boolean,
    @SerializedName("corroborationSource") val corroborationSource: String,
    @SerializedName("metadataJson") val metadataJson: String,
    @SerializedName("detectedAt") val detectedAt: Long,
    @SerializedName("eventType") val eventType: String = "DETECTED" // "DETECTED" | "PREDICTED"
)

// Persisted natively (not just Flutter widget state) so a future caregiver-push or
// "call emergency contact" notification action can read a contact without the Dart engine
// being alive. Order shown in the UI follows createdAt ascending.
@Entity(tableName = "emergency_contact", indices = [Index("createdAt")])
data class EmergencyContactEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") val id: Long = 0,
    @SerializedName("name") val name: String,
    @SerializedName("phone") val phone: String,
    @SerializedName("createdAt") val createdAt: Long
)

// One row per Focus/Prayer activation — endedAt is null while the mode is still active.
// Logged by PhoneModePlugin.syncModeNotification, which is called once per user-initiated
// mode change, so this mirrors exactly what the Alarms card/notification show. Base mode
// isn't logged (no "usage" to track), it just closes whatever was open.
@Entity(tableName = "phone_mode_session", indices = [Index("startedAt")])
data class PhoneModeSessionEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") val id: Long = 0,
    @SerializedName("mode") val mode: String,
    @SerializedName("startedAt") val startedAt: Long,
    @SerializedName("endedAt") val endedAt: Long? = null
)

// Offline-first daily rollups. Recomputed from raw Room readings on insert, and can also
// cache cloud day-rows so 7-day trends / past-day picks work without network.
// Primary key is (vital, dayEpochMs) where dayEpochMs is local-midnight start.
@Entity(
    tableName = "daily_vital_summary",
    primaryKeys = ["vital", "dayEpochMs"],
    indices = [Index("vital"), Index("dayEpochMs"), Index("dateStr")]
)
data class DailyVitalSummaryEntity(
    @SerializedName("vital") val vital: String,
    @SerializedName("dayEpochMs") val dayEpochMs: Long,
    @SerializedName("dateStr") val dateStr: String,
    @SerializedName("avg") val avg: Double? = null,
    @SerializedName("min") val min: Double? = null,
    @SerializedName("max") val max: Double? = null,
    @SerializedName("count") val count: Int = 0,
    // BP secondary (diastolic) or unused for single-value vitals
    @SerializedName("avgSecondary") val avgSecondary: Double? = null,
    @SerializedName("minSecondary") val minSecondary: Double? = null,
    @SerializedName("maxSecondary") val maxSecondary: Double? = null,
    // Steps-only extras
    @SerializedName("steps") val steps: Int? = null,
    @SerializedName("caloriesKcal") val caloriesKcal: Int? = null,
    @SerializedName("distanceM") val distanceM: Double? = null,
    // local = derived from Room raw rows; cloud_cache = mirrored from Supabase for offline
    @SerializedName("origin") val origin: String = "local",
    @SerializedName("updatedAt") val updatedAt: Long = System.currentTimeMillis()
)
