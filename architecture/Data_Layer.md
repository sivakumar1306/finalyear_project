# Data Layer and Synchronization

The data architecture is designed for "Offline-First" reliability with seamless cloud synchronization.

## Local Persistence (Room Database)

The native Android layer uses Room to store all health readings locally. This ensures that:
- Data is never lost if the internet is down.
- The app can provide instant feedback by reading from the local DB.
- Background analysis (like Fall Risk) can run without network dependency.

### Database Components (`data` package)
- **`QRingDatabase`**: The main database class.
- **`ReadingEntities`**: Data classes for `HeartRateReading`, `Spo2Reading`, `StepsReading`, etc.
- **`ReadingDaos`**: Data Access Objects for querying and inserting metrics.
- **`ReadingRepository`**: An abstraction layer used by the managers to interact with the database.

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
