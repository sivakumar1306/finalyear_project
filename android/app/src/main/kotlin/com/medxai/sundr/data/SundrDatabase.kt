package com.medxai.sundr.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(
    entities = [
        MeasurementCycleEntity::class,
        HeartRateReadingEntity::class,
        Spo2ReadingEntity::class,
        StressReadingEntity::class,
        BloodPressureReadingEntity::class,
        HrvReadingEntity::class,
        TemperatureReadingEntity::class,
        StepsSnapshotEntity::class,
        FallRiskLogEntity::class,
        FallEventEntity::class,
        EmergencyContactEntity::class,
        PhoneModeSessionEntity::class,
        DailyVitalSummaryEntity::class
    ],
    // v7: daily_vital_summary offline rollups + richer reading metadata fields
    version = 7,
    exportSchema = false
)
abstract class QRingDatabase : RoomDatabase() {
    abstract fun measurementCycleDao(): MeasurementCycleDao
    abstract fun heartRateDao(): HeartRateReadingDao
    abstract fun spo2Dao(): Spo2ReadingDao
    abstract fun stressDao(): StressReadingDao
    abstract fun bloodPressureDao(): BloodPressureReadingDao
    abstract fun hrvDao(): HrvReadingDao
    abstract fun temperatureDao(): TemperatureReadingDao
    abstract fun stepsSnapshotDao(): StepsSnapshotDao
    abstract fun fallRiskLogDao(): FallRiskLogDao
    abstract fun fallEventDao(): FallEventDao
    abstract fun emergencyContactDao(): EmergencyContactDao
    abstract fun phoneModeSessionDao(): PhoneModeSessionDao
    abstract fun dailyVitalSummaryDao(): DailyVitalSummaryDao

    companion object {
        @Volatile private var INSTANCE: QRingDatabase? = null

        fun getInstance(context: Context): QRingDatabase =
            INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    QRingDatabase::class.java,
                    "qring_local.db"
                )
                    // No migrations exist yet anywhere in this DB — app is still pre-release,
                    // so a destructive rebuild on schema bump is an accepted tradeoff over
                    // writing a migration for a single additive table.
                    .fallbackToDestructiveMigration(dropAllTables = true)
                    .build().also { INSTANCE = it }
            }

        // Used by logout's full data wipe (BlePlugin.clearPersonalData): close the open
        // handle and drop the singleton so the next getInstance() rebuilds from a fresh DB.
        fun destroy() {
            synchronized(this) {
                INSTANCE?.close()
                INSTANCE = null
            }
        }
    }
}
