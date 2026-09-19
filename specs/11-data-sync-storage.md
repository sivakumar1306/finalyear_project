# 11 — Data, Sync & Storage (INTEGRATED)

| Field | Value |
|-------|-------|
| **Status** | Shipped (single squashed `supabase/migrations/00000000000000_init.sql`, 34 tables, verified 2026-09-19; Room `qring_local.db` single authority; native + Dart dual writers; `user_records` pending) |
| **Key docs** | `architecture/Data_Layer.md`, `docs/engining/migration_plan.md`, `docs/engining/date_keys_and_formatters.md`, `docs/engining/overview.md`, `docs/health-eng/config.md`, `docs/archive/eval/05-BACKEND-DATA-PERSISTENCE.md`, `docs/archive/eval/08-SECURITY-PRIVACY-PERMISSIONS.md`, `docs/qring/README.md`, `docs/qring/phase-5-system-polish.md` |
| **Key code** | Room (`QRingDatabase`, `ReadingEntities.kt` 216 lines 14 entities, `ReadingDaos.kt`, `ReadingRepository` incl. `daySummaryFromRaw`), `SupabaseSyncManager.kt:142-318`, `SupabaseService` (`supabase_service.dart:110-734`), `BleService`/`BlePlugin` (`getDaySummary`/`getLocalHistory`/`cacheCloudDaySummary`/`getLocalDbStats`/`getReadings`/`getTodaySummary`/`configureSync`), `LocalVitalsService` (`getDaySummary`/`getHistory`/`hasData`), `HistoryService` (`last7IntSeries`/`minMaxForKey`/`splitDelta`), `MeasurementFlow` (`isValidHr`/`errorMessage`/`emptyMessage`/`extractInt`), `RealTimeCard` (+ `RealTimeBPCard` 102-line dup collapsed), `DateKeys` (`fmt`/`isToday`/`sameDay`/`dateOnly`/`dateKey`/`dayIndexFor`/`isFuture`/`trendXLabels`/`trendDayLabelsShort`/`dayStartMs`/`dayEndMs`), `Formatters` (`sleepDuration`/`sleepTimeLabel`/`hourLabel`/`halfHourLabel`/`fmtTime`), `HealthConfig` (`load`/`refresh`, `kDefaultConfig`, `kCacheTtl=5min`, `health_engine_config_json`), `IncidentService` (`reportIncident`, PII scrub, `app_env`), `ChatApiService` (timeouts 60/120/15 s), `PushNotificationService` (`user_push_tokens`), `HealthConnectService` (`requestAuthorization`/`revokeAll`) |

---

## 1. Principles

1. **Offline-first for continuous vitals:** Room `qring_local.db` is on-device source of truth (eval 05.5 📋 resolved: no sqflite in `pubspec.yaml`; `LocalVitalsService` is thin proxy over `ble` channel `getDaySummary`/`getLocalHistory`/`getReadings`/`cacheCloudDaySummary`).
2. **Cloud for durability & trends:** Supabase Postgres with RLS (`auth.uid() = user_id`, `id = auth.uid()` for `user_profiles`).
3. **Two independent writers:** Dart interactive (`supabase_flutter`) + native Kotlin background batch (`SupabaseSyncManager` via PostgREST).
4. **Idempotent upserts** keyed by business time (`user_id` + `measured_at`/`captured_at`/`date`), **not** local autoincrement IDs (reinstall-safe). `Prefer: resolution=merge-duplicates`, last-write-wins per timestamp.
5. **No fake buckets:** do not inject `hourly[now.hour]=avg` when no slot; leave gap. Hero = latest, stats = avg/min/max; stale pill `avg · no fresh reading` after 30 min (qring README).
6. **QRing blob fidelity:** ring logs autonomous interval blobs even when phone off (`heart_rate_detail` 1/day `interval/index_str/value TEXT`); phone polling (`MeasurementLoopManager` 3-min round-robin, adaptive 3→15 min) is sparse — backfill via `LargeDataHandler` (4 families: HR/SpO₂/Temp/Sleep; was 7/9 in earlier draft — recounted 2026-09-19).

---

## 2. Local storage (Room `qring_local.db`)

| Concern | Requirement |
|---------|-------------|
| LOC-01 | Store HR, SpO2, HRV, steps snapshots, BP, stress, temp, sleep, workouts, fall logs (`fall_risk_log`/`fall_event`), `emergency_contact`, `phone_mode_session`, `daily_vital_summary`, `measurement_*` as designed entities (`ReadingEntities.kt`, `QRingDatabase` schema v7+; `DailyVitalSummaryEntity(vital,dayEpochMs)` PK, `origin local\|cloud_cache`; raw entities carry `source`, `syncedAt`, optional `deviceAddress`/`extraJson`). |
| LOC-02 | Written by measurement loop, workouts, fall stack (`FallRiskAnalyzer`, `FallMotionDetector`), phone mode as applicable. |
| LOC-03 | Exposed to Flutter via BlePlugin/Channel (`getTodaySummary`, `getReadings`, `getDaySummary`, `getLocalHistory`, `cacheCloudDaySummary`, `getLocalDbStats`, `getFallRiskScore`, `getFallEvents`, `getMotionSnapshot`, `getPhoneModeSessions`). |
| LOC-04 | Pre-release may use destructive migrations; **before production**, real migrations required (no wipe). |
| LOC-05 | Authority per metric (all native Room via `ReadingRepository`): raw vitals, daily rollups (`daySummaryFromRaw`), steps, sleep, workouts, emergency contacts, fall events, phone-mode sessions. Dart `SharedPreferences` holds only non-vital settings. Retention: raw synced ~90 days (unsynced always kept), local rollups ~400 days, cloud-cached rows ~400 days. |

---

## 3. Cloud schema (34 tables, squashed `00000000000000_init.sql`)

### Daily aggregates (charts)

- `user_hr(user_id,date,...)` unique `(user_id,date)`; `user_spo2` same; `user_hrv` same; `user_steps` same; `user_sleep(user_id,date,...)` unique `(user_id,date)`.

### Raw streaming (native Room path)

- `user_hr_readings(user_id,measured_at,...)` unique `(user_id,measured_at)`; `user_spo2_readings` same; `user_hrv_readings` same; `user_steps_snapshots(user_id,captured_at,...)` unique `(user_id,captured_at)`.

### Event tables

- `user_bp(user_id,measured_at,...)` unique `(user_id,measured_at)` + `user_bp_local_reading_idx(local_reading_id)`; `user_stress` same; `user_temp` same. Dedupe keys guaranteed on fresh DBs by `20260807000000_fix_delete_user_account.sql` (previously only live DB via `20260706000002`; fresh DB 400'd `42P10: no unique constraint matching ON CONFLICT` — eval 05.6 ✅ verified).

### Product data

- `user_profiles(user_id|id,...)` owner `id = auth.uid()`; `user_workouts`; `workouts` (prayer: summary insert, history `order created_at`); `user_cycles(user_id,period_start,...)` unique `(user_id,period_start)`; `user_symptoms(user_id,logged_date,...)` unique `(user_id,logged_date)` (+ `upsertSymptoms` includes `user_id` or RLS rejects — eval 01.6 ✅ fixed); `user_emergency_contacts(user_id,local_id,...)` unique `(user_id,local_id)`.
- Fall split topology: `fall_risk_log`, `fall_event` — **local Room only**, purged 90 days (`RETENTION_RAW_DAYS`), never synced, read via `getFallRiskScore`/`getFallEvents`/`getMotionSnapshot`; `falls(id,user_id,timestamp,severity,created_at)` **Supabase only** (365-day trailing source, index `(user_id,timestamp desc)`; nothing native writes it; Flutter Layer-3 merges native primary + `falls` secondary at score time).
- Safety/alerting: `emergency_alerts`, `emergency_alert_deliveries`, `caregiver_links`, `caregiver_link_requests`, `user_push_tokens` (see spec 05 §9 for columns).
- Detail/phase-2/3: `user_ecg`, `user_breath_sessions`, `user_blood_sugar`, `user_quran_bookmarks(user_id,chapter_index,is_collection default true)` PK `(user_id,chapter_index)`, `user_friends(user_id,friend_user_id,status default 'pending')` PK `(user_id,friend_user_id)`, `user_nutrition_logs(user_id,date,calories,carbs default 0,protein default 0,fat default 0)` PK `(user_id,date)`, `user_watchface(user_id,installed_name,installed_at)` PK `(user_id)`, `health_engine_config(id=1,config jsonb default '{}',updated_at)` (see §7).
- `user_records(user_id,record_type,subtitle)` — **pending** (phase-5 §5.3; ensure `delete_user_account()` loop covers via `to_regclass` guard when added).
- Intentionally **not** created (eval 05.1): `messages`, `conversations`, `vital_readings`, `sedentary_*`, `workout_analytics`, `sleep_sessions`, `ring_sync_cache`, `activity_goals`, `workout_sessions`, `medical_events`, `medications`, `lab_reports`, `user_blood_panels` — no code reads/writes them (chat on Railway); old delete fn skips missing tables. `lover_links`, `user_worship_times` absent (see spec 09).

### Platform

- `firmware_updates` — public read release metadata (`Allow public read access`); `app_incidents` — crash ingest (anon + auth insert, service full, no bulk read); `delete_user_account()` — full wipe RPC (SECURITY DEFINER, `auth.uid()` only; deletes only tables that exist **and** carry expected key via `to_regclass(format('public.%I',t))` + `information_schema` + dynamic SQL; `messages` before `conversations` when both exist; identical on live vs migration-only DB — eval 05.10 ✅ fixed; covers `emergency_alert_deliveries/alerts`, `caregiver_links/requests` guards).
- Migrations: dated files (`20260706…`, `20260806…_missing_tables`, `20260807…`) squashed into single `00000000000000_init.sql` (34 tables). Older migrations guarded `ALTER/CONSTRAINT` behind `to_regclass('public.user_bp') is not null` (fresh `db push` died at #1 `relation "public.user_bp" does not exist` — ✅ fixed).
- Two naming eras coexist deliberately (eval 05.2 📋 resolved): raw `_readings`/`_snapshots` (native streaming, `(user_id,measured_at/captured_at)`) vs daily `user_hr/spo2/hrv/steps` (Dart chart shape, `(user_id,date)`); `SupabaseSyncManager.kt:142-318` documents raw push + aggregate recompute per cycle so both writers converge.

| ID | Requirement |
|----|-------------|
| DATA-01 | Squashed migration is source of truth (34 tables above); fresh `supabase db push` converges to live schema. |
| DATA-02 | Raw vs daily eras coexist; native recompute-upsert keeps aggregates convergent. |
| DATA-03 | `delete_user_account()` wipes all `user_*` + `workouts` + alerting/linking tables present, skips absent via `to_regclass`; never fails with `relation ... does not exist`. |
| DATA-04 | `user_records` migration pending — must extend delete loop when added. |

---

## 4. Sync paths

### 4.1 Native background push (`SupabaseSyncManager`)

| ID | Requirement |
|----|-------------|
| SYN-01 | Runs inside foreground service lifecycle (`BleConnectionService`). |
| SYN-02 | Credentials (URL, anon key, user id, access token) supplied by Flutter via `configureSync` on login + every auth change; logout clears `user_logged_in` + reconfigures (no logged-out sync). `SupabaseConfig.accessToken` cached for edge-fn Bearer use. |
| SYN-03 | Pushes unsynced Room rows on schedule (hourly with more frequent checks); `forceSyncNow()` after `saveStepsSnapshot`. |
| SYN-04 | PostgREST upsert `on_conflict=user_id,measured_at` (raw) / `user_id,captured_at` (steps) / `user_id,date` (aggregates) + `Prefer: resolution=merge-duplicates`. `seedDemoData` rows (`source='demo_seed'`) excluded from every `unsyncedBatch` push query (`ReadingDaos.kt`, all 7 tables) — never reach Supabase (eval 02.2 ✅ fixed). |
| SYN-05 | After raw push, recompute/upsert today's daily aggregates so chart queries keep working. |
| SYN-06 | Failures leave rows unsynced for retry; no silent loss. `clearPersonalData` (logout wipe) stops loops, drops DB, clears native prefs, cancels notifications. |

### 4.2 Dart interactive path

| ID | Requirement |
|----|-------------|
| SYN-10 | Auth, profile, manual measure merges (`MeasurementFlow` validation + incremental avg/min/max/count merge, not blind overwrite), workouts, WH data, prayer (`workouts`), Quran/friends/nutrition/watchface use `supabase_flutter`. |
| SYN-11 | Past-day + multi-day reads use Supabase when online; `HistoryService.last7IntSeries(rows,valueKey)` builds 7-day avg oldest→newest via `DateKeys.fmt` + `firstWhere date==fmt`; `minMaxForKey` delegates `TrendMath.minMax`; `splitDelta` half-split delta feeds `InsightsService` trends. Replaces 7× `_load7DayTrend` hand-rolled `List.generate(7...)` + `reduce(min/max)`. |
| SYN-12 | `MeasurementFlow` (`hrMin=30`, `hrMax=220`, `isValidHr`, `errorMessage` BUSY/TIMEOUT mapping, `emptyMessage(vital,raw)`, `extractInt(m,keys)` trying `value/spo2/bloodOxygen` etc.) replaces 6×40-line `_startMeasurement` copies. Blocking native measurement 8–90 s by vital (HRV 50–60 s); updates `BleProvider` latest; manual + workout coordinate via `MeasurementCoordinator` (no double-drive). |
| SYN-13 | `RealTimeCard` glass CTA is canonical live-measurement card; `RealTimeBPCard` 102-line dup collapsed into it. |

### 4.3 Local-first read pattern (UI)

| ID | Requirement |
|----|-------------|
| SYN-20 | Vitals detail "today" prefers Room (`LocalVitalsService.getDaySummary(vital,date)` → `_ble.getDaySummary(dayStartMs,dayEndMs)`; `hasData` = `count>0 \|\| steps>0 \|\| avg>0`; `getHistory(vital,days,end)` → `_ble.getLocalHistory(fromDayStartMs,toDayStartMs)` keyed by `dateStr`). |
| SYN-21 | Trends prefer Supabase; `LocalVitalsService` delegates date math to `DateKeys` (`dayStartMs/dayEndMs/dateStr`); `SupabaseService._dateStr:675` delegates to `DateKeys.fmt`. `DateKeys`: `fmt yyyy-MM-dd padLeft`, `isToday`, `sameDay`, `dateOnly`, `dateKey`, `dayIndexFor (today-sel inDays)`, `isFuture`, `trendXLabels (Mon..Sun, 7)`, `trendDayLabelsShort (M/T/W...)`, `dayStartMs`, `dayEndMs`. `Formatters`: `sleepDuration`, `sleepTimeLabel`, `hourLabel (0→12am,12→12pm,13→1pm)`, `halfHourLabel`, `fmtTime`. Replaces 16× `_fmt`, 7× `_isToday`/`trendXLabels`, 10× bucketing, 6× `dayStartMs`. `test/date_keys_test.dart` covers zero-pad, midnight, dayIndex 0, hour labels, 7 labels. |
| SYN-22 | Network errors classified for `OfflineNotice` vs empty state; `NotEnoughDataCard(measuring)` stays enabled during measuring (spinner + Cancel, same as `RealTimeCard`); hero shows `···` only when truly empty. |
| SYN-23 | `cacheCloudDaySummary` writes cloud fill-in back into Room (`origin=cloud_cache`) so multi-day charts work offline after purge. |

---

## 5. Security (eval 08 infused)

| ID | Requirement |
|----|-------------|
| SEC-01 | RLS: users own rows (`auth.uid() = user_id`, `id = auth.uid()` for profiles); all 20+ tables `enable row level security` + owner policy; `firmware_updates` public-read; `app_incidents` anon/auth insert + service full, no bulk read. Verify live once: `select relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and relname like 'user_%' and not relrowsecurity;` must return zero (eval 08.2). |
| SEC-02 | Anon key may ship (`lib/config.dart:4-13` committed prod URL + anon as `String.fromEnvironment` fallback); **never** service role. Publishable only because RLS versioned for every table (eval 05.8/08.1 📋 documented). Per-env projects future deployment concern, not blocker. |
| SEC-03 | Prefer compile-time defines (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `CHAT_API_BASE_URL`, `FIREBASE_*`, `APP_ENV`, `INCLUDE_MEASUREMENT_LOG`) over hardcoding for release hygiene. |
| SEC-04 | Account deletion removes personal cloud rows + auth user (`delete_user_account()` §3). |
| SEC-05 | Incident logs insert-only; no user bulk-read of others'. Client hardens: `IncidentService` strips PII (phone `/\+?\d[\d\s\-().]{7,}\d/`, email, JWT `/eyJ.../`, `Bearer` tokens) from message (cap 2000) + stack (cap 8000); `app_env` marker (`production`/`development`/`APP_ENV` override, `device_info`); rate-limit 10/60 s per source (`_rateWindow`, `_rateLimitPerSource`, `_sourceTimestamps`); dedupe identical `source\|message` 60 s (`_dedupeWindow`, `_recent`); `main.dart:80-107,141-150` Flutter UI/async/zone reporting stays bounded. Anon INSERT intentional (pre-login crashes); server-side insert rate-limit (security-definer RPC/trigger) future hardening. |
| SEC-06 | Permissions trimmed (eval 08.5 ✅ fixed): removed `READ_CALL_LOG`, `READ_SMS`, `RECEIVE_SMS`, `READ_CONTACTS` (contacts manual + Room), `ACCESS_BACKGROUND_LOCATION` (no bg location code), `POST_PROMOTED_NOTIFICATIONS`, `READ/WRITE_EXTERNAL_STORAGE` + `requestLegacyExternalStorage` (OTA via SAF, app-private storage). Justified set: `SEND_SMS` (`EmergencySmsSender`), `CALL_PHONE`+`READ_PHONE_STATE` (`EmergencyAutoCaller` + `BlePlugin:2989`), `RECORD_AUDIO` (`speech_to_text` voice sheet), `FINE/COARSE_LOCATION` (BLE scan < Android 12 via `main.dart:43-52`), Health Connect per-metric READ/WRITE, `ACCESS_NOTIFICATION_POLICY` (DND/phone-mode), `ACTIVITY_RECOGNITION` (steps `health_connect_service:198-203`). `main.dart:22-32` requests bluetooth/scan/connect/advertise, locationWhenInUse, notification, sms, phone. |
| SEC-07 | Network: HTTPS only (Supabase + Railway); no `usesCleartextTraffic`. |
| SEC-08 | SharedPreferences plaintext OK: no vitals in prefs (vitals in Room); keys (`device_address`, `user_logged_in`, `low_battery_prompt_enabled`, sleep times string-encoded, workout resume, kill-switches/config, `chat_conversation_id_{userId}`, `health_engine_config_json`, `qibla_last_*`, `nutrition_logs_v1`, `qring_emergency_sms` ledger) documented with Dart/Kotlin type parity (`SYN-30`). |
| SEC-09 | Privacy policy in-app (`privacy_policy_screen.dart`, Settings → About → Privacy, `about_screen:96`, updated July 25 2026); legal review + hosted URL for Health Connect `ACTION_SHOW_PERMISSIONS_RATIONALE` remain product tasks. |
| SEC-10 | Health Connect consent UX ✅ verified: `health_connect_screen.dart` availability + Play install (`_install`), first-run OS sheet via `requestAuthorization` (`_connect` enabled-subset, `_toggle` granular incl. per-metric re-grant), denial snackbar ("permission not granted — nothing will sync"), `revokeAll()` on disconnect, Android 14+ 30-day history best-effort (`health_connect_service:214-219`), 8 types (Steps, HR, HRV, SpO2, Sleep, BP, Temp, Menstruation), `requestHealthDataHistoryAuthorization`, deterministic `clientRecordId`. |

---

## 6. SharedPreferences cross-layer

Critical keys (illustrative): `device_address`, `user_logged_in`, `low_battery_prompt_enabled`, sleep times (string-encoded), workout resume, measurement kill-switches/config, `chat_conversation_id_{userId}` (+ `NEW_CHAT` sentinel), `health_engine_config_json` + `health_engine_config_updated_at`, `qibla_last_lat/lng/bearing`, `nutrition_logs_v1`, `prayer_mode_start/end_hour/minute` (strings), `qring_emergency_sms` ledger (`active/send_at_ms/reason/last_sent_at/last_sent_count/last_error/last_canceled_at/send_in_progress/send_started_at/pending_receipts_json/receipt_request_code/last_queued/delivered/failed/per_contact_json`).

| ID | Requirement |
|----|-------------|
| SYN-30 | Document type of each key; Dart and Kotlin readers match (`PrayerSchedulePrefs` strings vs native `getInt` crash guard; `HealthConfig` JSON string; SMS ledger Long/Boolean/String). Prefs namespaces isolated (`unit_prefs`, `goal_prefs`, `home_card_prefs`, `notification_prefs`, `prayer_schedule_prefs`). |

---

## 7. Health-engine config (remote-tunable thresholds/copy; `docs/health-eng/config.md` verbatim)

Table (`20260905000000_health_engine_config.sql`, idempotent `if not exists`, safe on live DB; `delete_user_account()` does **not** touch it — global, not per-user):

```sql
create table if not exists public.health_engine_config (
  id int primary key,
  config jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.health_engine_config enable row level security;
insert into public.health_engine_config (id, config) values (1, '{}'::jsonb)
on conflict (id) do nothing;
create policy "health_engine_config_read" on public.health_engine_config
  for select using (auth.role() = 'authenticated' or auth.role() = 'anon');
create policy "health_engine_config_write" on public.health_engine_config
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');
create or replace function public.touch_health_engine_config()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;
drop trigger if exists trg_touch_health_engine_config on public.health_engine_config;
create trigger trg_touch_health_engine_config
  before update on public.health_engine_config
  for each row execute function public.touch_health_engine_config();
```

(Squashed migration simplifies read policy to `for select using (true)`; intent identical — authenticated/anon read, service_role write. Do not grant authenticated write or any user retunes medical bands.)

JSON shape (`health_config.dart:kDefaultConfig`; remote deep-merges over it; partial updates allowed e.g. `{"thresholds":{"sleep":{"excellent":85}}}`):

```json
{
  "version": 1,
  "thresholds": {
    "sleep": {"excellent":80,"good":60,"fair":40},
    "hr": {"belowNormal":60,"aboveNormal":100},
    "spo2": {"normal":95,"borderline":90},
    "hrv": {"veryLow":20,"low":40,"moderate":60,"good":80},
    "stress": {"relaxed":40,"normal":60,"elevated":80},
    "bp": {"normalSbp":120,"normalDbp":80,"elevatedSbp":130,"stage1Sbp":140,"stage1Dbp":90},
    "temp": {"low":36.0,"normal":37.2,"elevated":38.0},
    "activity": {"stepsWeight":60,"caloriesWeight":25,"distanceWeight":15,"stepsDenom":10000,"caloriesDenom":1000,"distanceDenomM":5000}
  },
  "advice": {
    "sleep": {"title":"Sleep","heading":"About Sleep","intro":"...","didYouKnow":"...","tips":[{"icon":"bedtime_rounded","color":"sleepColor","title":"Aim for 7–9 hours","tip":"..."}]},
    "heartRate": {"title":"Heart Rate","heading":"About Heart Rate","intro":"...","didYouKnow":"...","tips":[...]},
    "spo2": {}, "hrv": {}, "stress": {}, "temperature": {}, "bloodPressure": {}, "activity": {}
  },
  "ranges": {
    "sleep": [{"label":"Poor","range":"0–39","color":"danger"},{"label":"Fair","range":"40–59","color":"amber"},{"label":"Good","range":"60–79","color":"sleepColor"},{"label":"Excellent","range":"80–100","color":"success"}],
    "heartRate": [{"label":"Below normal","range":"<60 bpm","color":"hrvColor"}],
    "activity": {"weights":"Steps 60 / Calories 25 / Distance 15"}
  }
}
```

Fetch: `HealthConfig.load()` once in `main.dart` before `runApp` (`client.from('health_engine_config').select('config').eq('id',1).maybeSingle()`); cache success to `health_engine_config_json` + `health_engine_config_updated_at`; failure/offline loads cache; miss uses `kDefaultConfig`; deep-merge remote over default. `refresh()` on `BleProvider`/Home pull-to-refresh + `didChangeAppLifecycleState.resumed` if stale > `kCacheTtl=5min`. No polling; Realtime `config` channel optional v2. Studio: Table Editor → row `id=1` → `config` JSONB editor → save → next resume/refresh picks up (bump `version` to force). Safety: `HealthEngine` clamps nonsense (e.g. `excellent` outside 0–100 falls back to default), logs via `IncidentService` on parse fail; airplane mode never shows `--` purely from config miss.

| ID | Requirement |
|----|-------------|
| DATA-10 | Singleton `health_engine_config(id=1)` RLS read anon/authenticated, write service_role only; `touch_health_engine_config()` trigger maintains `updated_at`. |
| DATA-11 | `HealthConfig.load/refresh` TTL 5 min, SharedPrefs cache, deep-merge, bundled fallback; Studio workflow per above. |
| DATA-12 | Engine clamps + `IncidentService` log on bad remote JSON. |

---

## 8. Chat backend note (integrated)

`ChatApiService` → Railway (`config.dart:15-19` default `https://vtialringbackendversion1-production-a3e4.up.railway.app/api/v1`); no secrets; timeouts `_chatTimeout 60 s`, `_insightsTimeout 120 s` (eval 05.9 quoted 20 s — code truth is 120 s), others 15 s (`chat_api_service.dart:12-24`); errors surface to UI. See spec 08 for contracts.

---

## 9. Acceptance criteria

- [ ] Airplane mode: today accumulates in Room when ring connected; `HealthConfig` fallback prevents `--`.
- [ ] Network restore: background sync uploads pending rows without duplicate aggregate corruption (recomputed convergently).
- [ ] Reinstall + re-login does not overwrite unrelated-time cloud samples (`measured_at`/`captured_at` conflict keys); demo seeds never sync.
- [ ] Logout stops authenticated sync (`user_logged_in` cleared, `configureSync` revoked, `clearPersonalData` thorough).
- [ ] Delete account removes profile + vitals + workouts + alerting/linking rows for that user (live + migration-only DB).
- [ ] Fresh `db push` builds all 34 tables with RLS + dedupe keys; RLS verify SQL returns zero.
- [ ] History: `last7IntSeries`/`minMaxForKey`/`splitDelta` replace hand-rolled trends; `DateKeys`/`Formatters` replace 16/7/10 dup sites; `MeasurementFlow` replaces 6×40-line flows; `RealTimeCard` canonical.
- [ ] Seed data: none in repo (eval 05.11 ✅ OK).
- [ ] Incidents env-filtered, rate-limited, deduped, PII-scrubbed, capped.

---

## 10. Related

- `architecture/Data_Layer.md`, `supabase/migrations/00000000000000_init.sql`
- [05-fall-detection-safety.md](./05-fall-detection-safety.md) (fall/alerting tables), [08-assist-chat.md](./08-assist-chat.md) (chat timeouts), [09-phone-modes-reminders.md](./09-phone-modes-reminders.md) (prayer `workouts`, prefs namespaces)
- `docs/engining/*`, `docs/health-eng/config.md`, `docs/archive/eval/05*` + `08*`, `docs/qring/README.md` + `phase-5-system-polish.md`
