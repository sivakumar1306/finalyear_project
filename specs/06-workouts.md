# 06 — Workouts

| Field | Value |
|-------|-------|
| **Status** | Shipped (per-type ring trace depth + watchface/album/ebook/music stubs pending) |
| **Key code** | `WorkoutProvider`, `WorkoutService.kt`, `lib/screens/workouts/*` (`workouts_screen` 1219 lines, `active_workout` 412, `sport_type_detail_screen`, `gps_trace_screen`), `lib/models/workout_model.dart:338`, `lib/services/ble_service.dart`, `BlePlugin.kt:99,2123` (`SportPlusHandle`, `syncSportRecords`) |

---

## 1. Purpose

Let users start guided sports sessions with live ring metrics, end sessions with a summary, and browse history stored in Supabase. Close QRing vs Sundr `91/240` activities gap for sport/media (Phase 4). Ring has no coordinates — GPS is phone-side.

---

## 2. Categories & metrics

**12 categories mapping QRing 20 sport types (130+ specific sports strings in pickers):**

QRing reference: `activity_aerobics.xml/running/cycling/swimming/hiking/yoga/…` 20 `newy` activities + `activity_sport.xml/detail_calorie/distance/go/prepare/running` + `fragment_day_sport/week/month/year` + `SportPlusRepository sport_plus_detail(device_address,date_str,start_time,sport_type,duration,distance,calories,steps,rate_value,avg_rate)` + `gps_detail` + `BleSport` + `AppSportRsp` (`classes5.dex` +20).

| Category | Typical live metrics |
|----------|----------------------|
| Running | HR, steps, distance, calories |
| Cycling | HR, distance, calories |
| Swimming | HR, calories |
| Outdoor Sports | HR, distance, calories |
| Gym & Fitness | HR, calories |
| Yoga | HR, calories |
| Dance | Category-defined |
| Combat Sports | Category-defined |
| Ball Sports | Category-defined |
| Water Sports | Category-defined |
| Winter Sports | Category-defined |
| Leisure & Recreation | Category-defined |

Metric set is driven by `WorkoutCategory.metrics` in `workout_model.dart`. UI must only show cards for metrics relevant to the active category. Extend `WorkoutCategory.sports` (already covers QRing 20 → 12) + `perSportTarget` map (`workout_model.dart`) for per-type goals. Per-type detail: `lib/screens/workouts/sport_type_detail_screen.dart` (stub exists; ring trace depth pending) parses `ReadDetailSportDataReq` via `SportPlusHandle` (existing import `BlePlugin:99`); native `getSportDetail(type,date)` → `BleService.getSportDetail` → cache to `user_workouts` with `workout_type` (ring-stored `sport_plus_detail`, not Room).

Watchface/album/ebook/music (stubs exist, depth pending): `watchface_store_screen.dart` grid (`WatchMarketFragment`; DIY omitted first cut; reuse `FileHandle` OTA `startOta(filePath)` / `DownloadWithoutNotification`; install progress via `ota_screen:424` `DfuHandle`; QRing `WatchFaceInstallActivity`, `PlateFragment/diy/Market`, `WatchFaceRepository http://api2.qcwxkjvip.com/download/watchface`); `album_screen.dart` (local `albumRepository`, device-local, no Supabase; `scanMediaFile` passthrough; QRing `AlbumActivity/PhotoGallery`, `AlbumToDeviceActivity`, `ContactActivity`, `CameraActivity` — `CameraReq` already in `BlePlugin:200+`, `ring_camera_screen:317` shutter only); `ebook_screen.dart` stub (`EbookManager` font); `music_album_screen.dart` (`MusicRepository`; `gesture_settings:227 toggleMediaPlayPause` only); display `display_settings_screen:145` brightness/clockStyle/orientation. GPS needs `ACCESS_FINE_LOCATION` (already `AndroidManifest`); map key risk noted.

---

## 3. User flow

1. Open Workouts hub (`/workouts` or nav).  
2. Pick category → sport sheet → pre-start info.  
3. `WorkoutProvider.startWorkout()`:
   - Persist resume state to SharedPreferences.
   - Start native `WorkoutService` foreground session (dedicated foreground service distinct from BLE monitor service).
   - Navigate to `ActiveWorkoutScreen`.  
4. Live polling of metrics: `hrLoop()` 4s interval + `stepsLoop()` 2s interval (`while (_isWorkoutActive)`, `Future.wait` fire-and-forget). Baseline pre-synced before start; stale-baseline recovery if ring unreachable at start; `runSteps` counted from `getTodaySteps` deltas; sub-1000 kcal floor (same `~/1000` 小卡→kcal convention as steps); `ringUnreachable` pill when deltas unavailable. Native keys fixed (`workout_sport/category`, safe double parsing).  
5. Back press / end → confirm "End Workout?".  
6. `stopWorkout()` computes deltas, shows summary, inserts Supabase `user_workouts` (or equivalent) with `user_id` RLS (+ `locations` jsonb for outdoor, `workout_type` for ring-merged).

---

## 4. Functional requirements

| ID | Requirement |
|----|-------------|
| WO-01 | User can browse categories and sports and start a session only when ring connection policy is satisfied (document UX if disconnected). 20 sport types selectable; detail shows `duration/distance/calories` from ring trace not just generic. |
| WO-02 | Active workout uses a dedicated native foreground service (`WorkoutService.kt:294`) distinct from the BLE monitor service. |
| WO-03 | Measurement loop and workout coordinate to avoid SDK command collisions (`MeasurementCoordinator`; `YIELDED_TO_MANUAL` / `skipped_workout` attempt status; `WORKOUT_RECHECK_MS` 15s resume). |
| WO-04 | App process death mid-workout: on relaunch, restore active workout UI from SharedPreferences. |
| WO-05 | Main shell tab bar cannot abandon an active workout (workout lock). |
| WO-06 | Completed sessions appear in history (e.g. 90-day window), grouped by date. |
| WO-07 | Spotlight cards for most recent sessions on hub. |
| WO-08 | History load handles offline via `OfflineNotice` pattern. |
| WO-09 | Ring sport buffer auto-merges on page open (`workouts_screen._pullRingSports`): `getSports 0..6` (range `0..6`, `kRingHistoryMaxDays=7`; legacy `getSportRecords`/`syncSportRecords` via `SportPlusHandle`, `BlePlugin:2123` raw-JSON stub → normalized) → normalize `SportPlusEntity{mSportType→name, mStartTime(s), mDuration(s), mDistance(m), mCalories, mRateAvg, steps}` → history row + `insertWorkout` for unseen, RING badge, `TYPE_APP_*` start-second dedupe. `mCalories` kcal-vs-小卡 auto (`≥10000 → ÷1000`; `~/1000` intentional, eval 1.9; `workout_provider:345-361`, `steps_screen:254`). `SportLocation{mRateReal}` only — no lat/lng fields exist (ring GPS impossible). |
| WO-10 | Manual outdoor workouts sample phone GPS (ring has no coordinates) → `user_workouts.locations` jsonb → polyline in `gps_trace_screen`. Phone `geolocator` sampled per 10s tick; custom polyline (`google_maps_flutter` is **not** a dependency); `locations` column already in schema (`00000000000000_init.sql`, no manual migration). |
| WO-11 | WorkoutProvider lifecycle: `dispose()` sets `_isWorkoutActive = false` before `_uiTimer?.cancel()` so `hrLoop`/`stepsLoop` exit gracefully (fixes fire-and-forget leak after disposal). `PrayerSessionProvider.dispose()` cancels 1s `_timer`, stops workout + restores `setCycleCooldownMs(180000)` if session active. |
| WO-12 | Workout metrics honesty: baseline pre-sync + stale-baseline recovery, `runSteps` counted, sub-1000 kcal floor, `ringUnreachable` pill (`history-coverage.md:21`). Distinguish `user_workouts` (sport incl. ring-merged) from `workouts` (prayer; `created_at` write/order — `started_at` was non-existent, fixed; table `20260806000000_missing_tables.sql` + RLS + `delete_user_account` wipe). |
| WO-13 | Per-type detail + media stubs must reuse `DESIGN.md` glass tokens only (`GlassCard` + route `/watchface` etc.); no new patterns per `CLAUDE.md:4`. |

---

## 5. Data (completed session)

Persist at least:

- Sport / category identity (`workout_type` incl. ring `mSportType→name`)  
- Start / end timestamps (`mStartTime(s)` s-or-ms normalize by magnitude), duration (`mDuration(s)`), distance (`mDistance(m)`), calories (`mCalories` ÷1000 when `≥10000`), steps, HR avg (`mRateAvg`) as applicable  
- `user_id` with RLS  
- Outdoor: `locations` jsonb (10s phone ticks)  
- Ring-merged: RING badge source flag; `TYPE_APP_*` dedupe by start second  

---

## 6. Acceptance criteria

- [ ] Start running workout shows HR (and other running metrics) while ring connected (`hrLoop` 4s / `stepsLoop` 2s ticking; baseline pre-synced).
- [ ] Ending workout saves row visible after relaunch (online).
- [ ] Kill app mid-workout → reopen → resumes active workout screen.
- [ ] Tab switch mid-workout is blocked.
- [ ] History lists past sessions when Supabase reachable.
- [ ] Ring sport buffer merges without duplicates (reopen page twice → single rows; `TYPE_APP_*` start-second dedupe; RING badge shown).
- [ ] GPS trace renders a real polyline for an outdoor manual workout (10s ticks → `locations` → `gps_trace_screen`; no `google_maps_flutter` dep).
- [ ] Dispose mid-workout stops loops (no leaked `hrLoop`/`stepsLoop`); prayer dispose restores 180s cooldown.
- [ ] 20 sport types selectable; per-type detail shows ring `duration/distance/calories`; watchface install progress via existing `DfuHandle`.

---

## 7. Related

- [02-device-pairing-ble.md](./02-device-pairing-ble.md)  
- [04-home-dashboard.md](./04-home-dashboard.md)
- `docs/qring/phase-4-multimedia-sport.md`, `docs/mappings/history-coverage.md`, `docs/mappings/sdk-vs-plugin.md`, `docs/changes-18/*`, `docs/archive/eval/01-02`
