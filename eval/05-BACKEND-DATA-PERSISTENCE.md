# 05 — Backend, Data Persistence & Sync Audit (Supabase + Room)

## 5.1 Migration coverage — CRITICAL GAP (confirmed)

`supabase/migrations/` contains 6 files. Tables created by migrations:

| Table | Migration |
|---|---|
| `user_hr_readings` | `20260706000000_ring_streaming_pipeline.sql` (RLS + owner policy ✓) |
| `user_spo2_readings` | same (RLS ✓) |
| `user_hrv_readings` | same (RLS ✓) |
| `user_steps_snapshots` | same (RLS ✓) |
| `firmware_updates` | `20260802010000_firmware_updates.sql` (RLS + public read ✓) |
| `app_incidents` | `20260803000000_app_incidents.sql` (RLS, anon+auth insert, service full ✓) |

**Tables the app reads/writes that NO migration creates:**

| Table | Where |
|---|---|
| `user_profiles` | `lib/services/supabase_service.dart:110,123` |
| `user_steps` | `:146,164` |
| `user_hr` | `:183-228` |
| `user_spo2` | `:249-294` |
| `user_bp` | `:312-337` |
| `user_stress` | `:361-386` |
| `user_hrv` | `:407-440` |
| `user_temp` | `:463-510` |
| `user_workouts` | `:535,561` |
| `user_sleep` | `:586-623` |
| `user_cycles` | `:639-653` |
| `user_symptoms` | `:669-686` |
| `user_emergency_contacts` | `:711-734` |
| `workouts` (prayer) | `lib/screens/prayer/prayer_summary_screen.dart:40` |
| `messages`, `conversations`, `vital_readings`, `sedentary_alerts`, `workout_analytics`, `sleep_sessions`, `ring_sync_cache`, `activity_goals`, `sedentary_logs`, `workout_sessions`, `medical_events`, `medications`, `lab_reports`, `user_blood_panels` | referenced by `20260802000000_account_deletion.sql:24-39` (DELETE statements) |

**Impact:**
- A fresh `supabase db push` yields a DB that 404s on every vitals/profile/contact write. Someone must have created ~14 tables manually in the dashboard (they are not in the repo) — the deployment is **non-reproducible**.
- The account-deletion function `public.delete_user_account()` **deletes from tables that don't exist** → throws `relation "public.messages" does not exist` on first DELETE → account deletion is **broken** on a migration-only DB.
- **RLS exists only for the 6 migrated tables.** If the ~14 others were created manually without RLS, all users can read all vitals (see 08.2). Even if RLS was enabled manually, the config isn't versioned.

**Fix:** write migrations for every table the code references (schema + RLS + owner policies), and make `delete_user_account` delete only tables that exist.

## 5.2 Two naming eras — readings vs plain names — [MED]

Migrations: `user_hr_readings` / `user_spo2_readings` / `user_hrv_readings` / `user_steps_snapshots`.
App code: `user_hr` / `user_spo2` / `user_hrv` / `user_steps`.

Either the app is ahead (intended schema) or behind (stale). The migration naming and app naming must converge; one of the two is dead weight.

## 5.3 RLS on the migrated tables — CONFIRMED OK

`ring_streaming_pipeline.sql:64-75`: `enable row level security` + owner policy (`user_id = auth.uid()`) on the 4 reading tables; `firmware_updates` public-read; `app_incidents` anon/auth insert + service full. Good — for the 6 tables that exist.

## 5.4 Incidents spam — [MED]

`lib/main.dart:80-107,141-150` — every Flutter UI/async/zone error is reported to `app_incidents`. With `ErrorWidget.builder → SizedBox.shrink()` (line 104), errors also hide. No dev/test environment filter, no rate limit, no dedupe → the production incidents table fills with debug noise.

## 5.5 Room (LocalVitalsService) vs native Room — TWO local DBs — [HIGH]

- **Dart side:** `lib/services/local_vitals_service.dart` — a Dart Room (sqflite) DB for vitals.
- **Native side:** `android/.../data/SundrDatabase.kt` — Kotlin Room (`qring_local.db`), written by `MeasurementLoopManager`/`ReadingRepository`, with sync manager (`SupabaseSyncManager`).

The BLE pipeline (native Room → native Supabase sync) is the primary path. The Dart-side local vitals service appears **duplicative** — verify which screens read from which, and whether the two DBs can disagree (e.g., native DB has readings the Dart DB lacks). At minimum document the authority per metric.

## 5.6 Sync conflict resolution — [MED]

`SupabaseSyncManager` (native) upserts readings; Dart `SupabaseService` also upserts. On reconnect, both may push; there is no visible conflict-resolution policy (last-write-wins by `measured_at`?). Confirm dedupe keys (`measured_at` + `user_id`?) to avoid double rows — `20260706000002_fix_reinstall_collision_use_measured_at.sql` suggests this was partially addressed.

## 5.7 Prefs services — key hygiene — [LOW]

`unit_prefs`, `goal_prefs`, `home_card_prefs`, `notification_prefs`, `prayer_schedule_prefs` — separate namespaces, no central registry; audit for collisions. `prayer_schedule_prefs.dart` stores ints as strings (documented native-getInt workaround) — no native consumer yet.

## 5.8 Supabase client init — OK, but env-tied — [MED]

`lib/services/supabase_service.dart` uses `AppConfig.supabaseUrl`/`supabaseAnonKey` (`lib/config.dart:4-9`), with `String.fromEnvironment` fallback to the committed prod URL/anon key. Works, but the committed fallback means every developer (and every build without `--dart-define`) talks to the same shared project. Consider per-env projects or at least a different anon key per env.

## 5.9 Chat/LLM backend — external service — [MED]

`lib/services/chat_api_service.dart` → `https://vtialringbackendversion1-production.up.railway.app/api/v1` (`config.dart:18`). Verify: no secrets committed; 60s LLM timeout acceptable on cold Railway instances; error path doesn't hang the UI.

## 5.10 Account-deletion function — BROKEN on fresh DB — [CRIT] (see 5.1)

`20260802000000_account_deletion.sql:24-58` — deletes from 14+ tables that no migration creates → `delete_user_account()` raises on first missing table. Account deletion must be fixed and tested against the migration-only schema.

## 5.11 Seed data — none in repo — [OK]

No seed SQL found; fine.

---

## Priority actions (backed by evidence)
1. Migrations for all ~14 missing tables (+ RLS) and fix `delete_user_account` (5.1/5.10).
2. Decide single local-DB authority (5.5).
3. Dedupe sync writes between native SupabaseSyncManager and Dart SupabaseService (5.6).
4. Env-filter incident reporting (5.4).