package com.sundr.myapp.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [
        MeasurementCycleEntity::class,
        MeasurementAttemptEntity::class,
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
        DailyVitalSummaryEntity::class,
        SleepNightEntity::class
    ],
    // v9: sleep_night — local sleep cache so the sleep screen paints before the ring or network.
    version = 9,
    exportSchema = false
)
abstract class QRingDatabase : RoomDatabase() {
    abstract fun measurementCycleDao(): MeasurementCycleDao
    abstract fun measurementAttemptDao(): MeasurementAttemptDao
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
    abstract fun sleepNightDao(): SleepNightDao

    companion object {
        // Additive table only. Existing vitals stay. Destructive fallback remains
        // for installs older than v8, which never had a migration path.
        val MIGRATION_8_9 = object : Migration(8, 9) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `sleep_night` (
                        `dateStr` TEXT NOT NULL,
                        `dayIndex` INTEGER NOT NULL,
                        `totalDuration` INTEGER NOT NULL,
                        `deepDuration` INTEGER NOT NULL,
                        `lightDuration` INTEGER NOT NULL,
                        `remDuration` INTEGER NOT NULL,
                        `awakeDuration` INTEGER NOT NULL,
                        `sleepScore` INTEGER NOT NULL,
                        `sleepTime` INTEGER NOT NULL,
                        `wakeTime` INTEGER NOT NULL,
                        `payloadJson` TEXT NOT NULL,
                        `source` TEXT NOT NULL,
                        `syncedAt` INTEGER,
                        `updatedAt` INTEGER NOT NULL,
                        PRIMARY KEY(`dateStr`)
                    )
                    """.trimIndent()
                )
                db.execSQL(
                    "CREATE INDEX IF NOT EXISTS `index_sleep_night_syncedAt` ON `sleep_night` (`syncedAt`)"
                )
            }
        }
        @Volatile private var INSTANCE: QRingDatabase? = null

        fun getInstance(context: Context): QRingDatabase =
            INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    QRingDatabase::class.java,
                    "qring_local.db"
                )
                    // v8 → v9 keeps existing vitals. Older installs still rebuild (no earlier migrations).
                    .addMigrations(MIGRATION_8_9)
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
