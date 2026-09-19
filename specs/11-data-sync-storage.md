# 11 — Data, Sync & Storage

| Field | Value |
|-------|-------|
| **Status** | Shipped |
| **Key docs** | `architecture/Data_Layer.md` |
| **Key code** | Room (`QRingDatabase`), `SupabaseSyncManager`, `SupabaseService`, `supabase/migrations/*` |

---

## 1. Principles

1. **Offline-first for continuous vitals:** Room is the on-device source of truth.  
2. **Cloud for durability & trends:** Supabase Postgres with RLS.  
3. **Two independent writers to Supabase:** Dart (interactive) and native Kotlin (background batch).  
4. **Idempotent upserts** keyed by business time (`user_id` + `measured_at` / `captured_at`), **not** local autoincrement IDs (reinstall-safe).

---

## 2. Local storage (Room)

| Concern | Requirement |
|---------|-------------|
| LOC-01 | Store HR, SpO2, HRV, steps snapshots, BP, stress, temp, fall logs, emergency contacts as designed entities. |
| LOC-02 | Written by measurement loop, workouts, fall stack, phone mode as applicable. |
| LOC-03 | Exposed to Flutter via BlePlugin methods (`getTodaySummary`, `getReadings`, …). |
| LOC-04 | Pre-release may use destructive migrations; **before production**, real migrations are required so user data is not wiped. |

Database name (conceptually): `qring_local.db`.

---

## 3. Cloud schema (product-level)

### Daily aggregates (charts)

- `user_hr`, `user_spo2`, `user_hrv`, `user_steps` — per day averages / totals.

### Raw streaming

- `user_hr_readings`, `user_spo2_readings`, `user_hrv_readings`, `user_steps_snapshots`  
- Fields: value, `measured_at`/`captured_at`, `source`, `local_reading_id` (legacy), sync timestamps.

### Event tables

- `user_bp`, `user_stress`, `user_temp`  
- Optional `local_reading_id` for native idempotent push.

### Product data

- `user_profiles`  
- `user_workouts`  
- `user_sleep`  
- `user_cycles`, `user_symptoms`  
- `user_emergency_contacts`  
- Fall tables — split topology (see fall spec §4):
  - `fall_risk_log`, `fall_event` — **local Room only**, purged after 90 days (`RETENTION_RAW_DAYS`). Never synced to cloud. Read by Flutter via `getFallRiskScore` / `getFallEvents` / `getMotionSnapshot`.
  - `falls` — **Supabase only** (365-day trailing history source). Nothing on the native side writes it today; the Flutter Layer-3 model merges native `fall_event` (primary) with `falls` (secondary) at score time.

### Platform

- `firmware_updates` — public read of release metadata  
- `app_incidents` — crash/incident ingest (auth + anon insert policies)  
- `delete_user_account()` — full user wipe RPC  

Migrations live under `supabase/migrations/` — a single squashed `00000000000000_init.sql` (34 tables, verified 2026-09-19).

---

## 4. Sync paths

### 4.1 Native background push

| ID | Requirement |
|----|-------------|
| SYN-01 | `SupabaseSyncManager` runs inside foreground service lifecycle. |
| SYN-02 | Credentials (URL, anon key, user id, access token) supplied by Flutter via `configureSync` on login and every auth change. |
| SYN-03 | Push unsynced Room rows on a schedule (e.g. hourly with more frequent checks). |
| SYN-04 | Use PostgREST upsert with `on_conflict` on (`user_id`, `measured_at`) (or equivalent after reinstall fix). |
| SYN-05 | After raw push, recompute/upsert today’s daily aggregates so existing chart queries keep working. |
| SYN-06 | Failures leave rows unsynced for retry; no silent data loss. |

### 4.2 Dart interactive path

| ID | Requirement |
|----|-------------|
| SYN-10 | Auth, profile, manual measure merges, workouts, WH data use `supabase_flutter`. |
| SYN-11 | Past-day and multi-day reads use Supabase when online. |

### 4.3 Local-first read pattern (UI)

| ID | Requirement |
|----|-------------|
| SYN-20 | Vitals detail “today” prefers Room. |
| SYN-21 | Trends prefer Supabase. |
| SYN-22 | Network errors classified for OfflineNotice vs empty state. |

---

## 5. Security

| ID | Requirement |
|----|-------------|
| SEC-01 | RLS: users only access own rows (`auth.uid() = user_id`). |
| SEC-02 | Anon key may ship in app; **never** ship service role key. |
| SEC-03 | Prefer compile-time defines for URL/keys (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) over hardcoding for release hygiene. |
| SEC-04 | Account deletion removes personal cloud rows and auth user. |
| SEC-05 | Incident logs may be insert-only for clients; no user bulk-read of others’ incidents. |

---

## 6. SharedPreferences cross-layer

Critical shared keys (illustrative):

- `device_address`  
- `user_logged_in`  
- Sleep reminder times (string-encoded for native readers)  
- Workout resume state  
- Measurement kill-switches / config  

| ID | Requirement |
|----|-------------|
| SYN-30 | Document type of each key; Dart and Kotlin readers must match. |

---

## 7. Acceptance criteria

- [ ] Airplane mode: today readings still accumulate in Room when ring connected.  
- [ ] After network restore, background sync uploads pending rows without duplicate daily aggregates corruption.  
- [ ] Reinstall + re-login does not overwrite historical cloud samples for unrelated times (measured_at conflict key).  
- [ ] Logout stops authenticated sync.  
- [ ] Delete account removes profile and vitals for that user.

---

## 8. Related

- `architecture/Data_Layer.md`  
- `supabase/migrations/*`  
