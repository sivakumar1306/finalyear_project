# 05 — Backend, Data Persistence & Sync Audit (Supabase + Room)

> Refs are `file:line`. All confirmed by direct read.
>
> Status legend: ✅ fixed · 📋 addressed/documentary · ⏸️ deferred by decision · ❌ still open
> Status as of **2026-08-07**.
>
> Note (2026-09-19): the dated migration files named below (`20260706…`,
> `20260806…_missing_tables`, `20260807…`) were later squashed into a single
> `supabase/migrations/00000000000000_init.sql` (34 tables). File names below
> are historical; table coverage is unchanged.

## 5.1 Migration coverage — CRITICAL GAP — ✅ fixed

> **Fix (2026-08-06):** `supabase/migrations/20260806000000_missing_tables.sql` creates every
> table the app reads/writes (`user_profiles`, `user_steps`, `user_hr`, `user_spo2`,
> `user_hrv`, `user_bp`, `user_stress`, `user_temp`, `user_workouts`, `user_sleep`,
> `user_cycles`, `user_symptoms`, `user_emergency_contacts`, `workouts`-prayer) with the
> exact column shapes used by `supabase_service.dart` / `SupabaseSyncManager.kt`, plus RLS
> and owner policies.
>
> **Fix (2026-08-07, fresh-DB reproducibility):** the older migrations
> (`20260706000000`, `...0001`, `...0002`) contained unguarded `ALTER TABLE` /
> `ADD CONSTRAINT` statements against `user_bp`/`user_stress`/`user_temp` — tables only
> created by the *later* `missing_tables` migration (on the live DB they existed because
> they were created manually in the dashboard). A fresh `supabase db push` therefore died
> at migration #1 with `relation "public.user_bp" does not exist`. All three migrations
> now guard those statements behind `to_regclass('public.user_bp') is not null` checks, and
> `20260807000000_fix_delete_user_account.sql` adds the `(user_id, measured_at)` unique
> constraints those tables need for the native `on_conflict` pushes (see 5.6) plus the
> fixed delete function (5.10). A migration-only database now converges to the same schema
> as the live DB.

Tables created by migrations:

| Table | Migration |
|---|---|
| `user_hr_readings` | `20260706000000_ring_streaming_pipeline.sql` (RLS + owner policy ✓) |
| `user_spo2_readings` | same (RLS ✓) |
| `user_hrv_readings` | same (RLS ✓) |
| `user_steps_snapshots` | same (RLS ✓) |
| `firmware_updates` | `20260802010000_firmware_updates.sql` (RLS + public read ✓) |
| `app_incidents` | `20260803000000_app_incidents.sql` (RLS, anon+auth insert, service full ✓) |
| `user_profiles`, `user_steps`, `user_hr`, `user_spo2`, `user_hrv`, `user_bp`, `user_stress`, `user_temp`, `user_workouts`, `user_sleep`, `user_cycles`, `user_symptoms`, `user_emergency_contacts`, `workouts` | `20260806000000_missing_tables.sql` (all RLS + owner policies ✓) |

Remaining note: the legacy tables listed in the original eval (`messages`, `conversations`,
`vital_readings`, `sedentary_*`, `workout_analytics`, `sleep_sessions`, `ring_sync_cache`,
`activity_goals`, `workout_sessions`, `medical_events`, `medications`, `lab_reports`,
`user_blood_panels`) are **intentionally not created** — no current app code reads or
writes them (chat history lives on the external Railway backend). They are only referenced
by the old account-deletion function, which now skips missing tables (see 5.10).

## 5.2 Two naming eras — readings vs plain names — 📋 resolved by design

`user_hr_readings` / `user_spo2_readings` / `user_hrv_readings` / `user_steps_snapshots`
(raw per-reading streaming tables, written by native `SupabaseSyncManager`) and
`user_hr` / `user_spo2` / `user_hrv` / `user_steps` (daily aggregates, written by both
native recompute-upsert and Dart `SupabaseService`) now coexist deliberately:

- **Raw tables** (`_readings`/`_snapshots`) — the native Room streaming path,
  idempotent on `(user_id, measured_at)` / `(user_id, captured_at)`.
- **Daily aggregate tables** — the pre-existing Dart chart/history shape, keyed
  `(user_id, date)`.

Not dead weight on either side; `SupabaseSyncManager.kt:142-318` documents the split
(raw push + aggregate recompute per cycle).

## 5.3 RLS on the migrated tables — ✅ confirmed

All 20 tables now have `enable row level security` + an owner policy
(`user_id = auth.uid()`, `id = auth.uid()` for `user_profiles`); `firmware_updates`
public-read; `app_incidents` anon/auth insert + service full (see 08.4 for hardening).

## 5.4 Incidents spam — ✅ fixed

> **Fix (2026-08-07):** `lib/services/incident_service.dart` now
> * adds an `app_env` marker (`production` / `development` / `APP_ENV` dart-define override)
>   inside `device_info`, so dev/test noise can be filtered,
> * rate-limits per source (10 incidents / 60 s per process),
> * dedupes identical `source|message` payloads (60 s window),
> * caps message (2000 chars) and stack trace (8000 chars) lengths,
> * scrubs PII (phone numbers, e-mails, JWTs, `Bearer` tokens) before upload.

`lib/main.dart:80-107,141-150` still reports every Flutter UI/async/zone error to
`app_incidents` — intended, but now bounded. Dev/test builds report as
`app_env: development`; release builds as `production`.

## 5.5 Room (LocalVitalsService) vs native Room — TWO local DBs — 📋 resolved (single authority)

> The eval draft assumed a Dart-side sqflite DB. **There is no sqflite dependency in
> `pubspec.yaml`.** `lib/services/local_vitals_service.dart` is a thin proxy over the
> `ble` method channel (`getDaySummary` / `getLocalHistory` / `getReadings` /
> `cacheCloudDaySummary`) that reads and writes the **native Room DB
> (`qring_local.db`)** — the single local authority for every metric.
>
> Authority per metric (all native Room via `ReadingRepository`):
> raw vitals (HR/SpO₂/HRV/temp/BP/stress), daily rollups (`daily_vital_summary`), steps,
> sleep, workouts, emergency contacts, fall events, phone-mode sessions.
> Dart `SharedPreferences` holds only non-vital settings; cloud sync is
> native → Supabase (`SupabaseSyncManager`) with Dart `SupabaseService` for profile /
> women's health / prayer / manual measures.

## 5.6 Sync conflict resolution — ✅ verified & guaranteed

- Raw pushes: `on_conflict=user_id,measured_at` (+ `Prefer: resolution=merge-duplicates`)
  — last-write-wins per measurement timestamp (`SupabaseSyncManager.kt:153-203`).
- Aggregate pushes: `on_conflict=user_id,date` (`:269-317`), recomputed from Room so both
  writers converge on the same daily numbers.
- Dedupe keys are now **guaranteed to exist on fresh DBs**:
  `20260807000000_fix_delete_user_account.sql` adds the `(user_id, measured_at)` unique
  constraints on `user_bp`/`user_stress`/`user_temp` that the native `on_conflict` targets
  (previously present only on the live DB via `20260706000002`, so a fresh DB 400'd every
  push with `42P10: no unique constraint matching the ON CONFLICT specification`).

## 5.7 Prefs services — key hygiene — 📋 documented

`unit_prefs`, `goal_prefs`, `home_card_prefs`, `notification_prefs`, `prayer_schedule_prefs`
stay in separate namespaces; no collisions found. `prayer_schedule_prefs.dart`'s
ints-as-strings workaround remains documented and is a no-op until a native consumer
exists (01.14).

## 5.8 Supabase client init — OK, but env-tied — 📋 documented decision

`lib/config.dart:4-13` keeps the committed prod URL + anon key as `String.fromEnvironment`
fallback. This is publishable **only because RLS is now versioned for every table** (5.1),
which closes the loop on 08.1/08.2. Per-env projects remain a future option; tracked as a
deployment concern, not a blocker.

## 5.9 Chat/LLM backend — external service — ✅ verified

`lib/services/chat_api_service.dart` → Railway (`config.dart:15-19`). No secrets
committed; explicit timeouts on every call (`_chatTimeout` 60 s, `_insightsTimeout` 20 s,
others 15 s — `chat_api_service.dart:12-24`); errors surface to the UI instead of hanging.

## 5.10 Account-deletion function — BROKEN on fresh DB — ✅ fixed

> **Fix (2026-08-07):** `20260807000000_fix_delete_user_account.sql` rewrites
> `public.delete_user_account()` to delete only from tables that exist **and** carry the
> expected key column (`user_id`, or `id` for `user_profiles`), via `to_regclass` +
> `information_schema` checks and dynamic SQL. It works identically on the live DB
> (legacy tables present) and a migration-only DB (legacy tables absent) — no more
> `relation "public.messages" does not exist` on the first DELETE. `messages` is still
> wiped before `conversations` when both exist.

## 5.11 Seed data — none in repo — ✅ OK

No seed SQL found; fine.

---

## Priority actions (status)

1. ✅ Migrations for all missing tables (+ RLS) and `delete_user_account` fixed (5.1/5.10) — *verify against the live dashboard once*.
2. ✅ Single local-DB authority documented (5.5).
3. ✅ Sync dedupe keys verified + guaranteed on fresh DBs (5.6).
4. ✅ Incident reporting env-filtered, rate-limited, PII-scrubbed (5.4).
