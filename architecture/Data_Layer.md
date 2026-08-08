# Data Layer and Synchronization

The data architecture is designed for "Offline-First" reliability with seamless cloud synchronization.

## Local Persistence (Room Database)

The native Android layer uses Room (`qring_local.db`) as the **offline-first source of truth**. This ensures that:
- Data is never lost if the internet is down.
- The app can provide instant feedback by reading from the local DB.
- Background analysis (like Fall Risk) can run without network dependency.
- Past-day picks and 7-day trends prefer local rollups; cloud is a fill-in + write-through cache.

### Database Components (`data` package)
- **`QRingDatabase`**: The main database class (schema v7+).
- **`ReadingEntities`**: Raw samples for HR, SpO2, stress, BP, HRV, temperature, steps — each with `source`, `syncedAt`, optional `deviceAddress` / `extraJson`.
- **`DailyVitalSummaryEntity`**: Per-day rollups (`daily_vital_summary`) rebuilt on every insert and retained longer than raw rows so multi-day charts work offline after purge. `origin` is `local` or `cloud_cache`.
- **`ReadingDaos`**: Data Access Objects for querying and inserting metrics.
- **`ReadingRepository`**: Facade used by managers + BlePlugin (`getDaySummary`, `getLocalHistory`, `cacheCloudDaySummary`, `getLocalDbStats`).

### Retention
| Layer | Default |
|-------|---------|
| Raw synced samples | ~90 days (unsynced always kept) |
| Local day rollups | ~400 days |
| Cloud-cached day rows | ~400 days |

### Flutter access
- `BleService` MethodChannel methods: `getDaySummary`, `getLocalHistory`, `cacheCloudDaySummary`, `getLocalDbStats`.
- `LocalVitalsService` (`lib/services/local_vitals_service.dart`): local-first helper used by vitals screens.

## Cloud Storage (Supabase)

Supabase acts as the centralized storage for user profiles, historical data, and cross-device synchronization.
- **Tables**: Mirrored structure to the local Room entities (e.g., `user_hr`, `user_spo2`, `user_steps`).
- **Security**: Row-Level Security (RLS) ensures users can only access their own data.

## Synchronization Strategy: `SupabaseSyncManager`

A critical component that bridges the local Room DB and the Supabase cloud.

### How it works:
1. **Trigger**: When the `MeasurementLoopManager` saves a new reading to Room, the `SupabaseSyncManager` is notified.
2. **Batching**: It collects readings and attempts to push them to Supabase in batches.
3. **Flutter-Native Handshake**: 
    - Upon login in Flutter, the Supabase credentials (URL, Anon Key, Access Token) are passed to the native side via `MethodChannel`.
    - The native `SupabaseSyncManager` uses these credentials to perform HTTP POST/UPSERT requests directly to the Supabase REST API (PostgREST).
4. **Resilience**: If a sync fails, the manager retries or leaves the data in Room to be synced later.

## Data Schema Consistency

The application maintains strict schema consistency between:
1.  **Room Entities** (Kotlin)
2.  **Supabase Tables** (PostgreSQL)
3.  **Dart Models** (Flutter)

This ensures that data flows smoothly from the ring, through the native service, into the cloud, and back to the Flutter UI.
