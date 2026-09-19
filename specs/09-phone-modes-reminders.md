# 09 — Phone Modes & Reminders (INTEGRATED)

| Field | Value |
|-------|-------|
| **Status** | Shipped on Android; iOS DND unsupported. Prayer session/history/summary live; Qibla/Quran/Friends/Nutrition stubs live (glass, offline-capable where noted); muslim_goal_v2 offset dialog pending; `lover_links` + `worship_times` tables absent |
| **Key code** | `AlarmModeProvider` (`PhoneMode focus/base/prayer`, `PhoneModeResult applied/needsDndAccess/unsupported`, `setMode`), `PhoneModePlugin.kt` (~130 lines, `PRAYER_DND_AUTO_OFF_MS=60_000L`, `Handler(Looper.getMainLooper())`, `setInterruptionFilter`), `PhoneModeNotifier.kt` (`showFocus`/`showPrayer`/`cancel`), `BleProvider.getPhoneModeSessionsToday`, `prayer_session_screen.dart` (~651 lines), `prayer_history_screen.dart` (~620 lines), `prayer_summary_screen.dart` (~280 lines), `providers/prayer_session_provider.dart` (`dispose`, 5 s sample, `_sessionCooldownMs=30000`), `services/prayer_schedule_prefs.dart` (ints-as-strings), `services/qibla_service.dart` (`bearing`, `Geolocator`, `FlutterCompass`), `screens/quran/quran_screen.dart` + `assets/quran/quran.json` (117321 bytes) + `screens/quran/qibla_screen.dart` (`CustomPainter`, gold `#C9A86E`), `screens/social/friends_screen.dart` (ranking/`LoverSpace`/`MyQrCode`), `models/nutrition_model.dart` (`NutritionLog`) + `screens/nutrition/nutrition_screen.dart` (`MetricChartCard`), `BleProvider.syncFriendsDataToServer` (stub), reminder screens + `get/setDrinkReminder`/`get/setSedentaryReminder` |
| **Key docs** | `docs/qring/phase-3-social-religious.md`, `docs/archive/eval/01-CONFIRMED-BUGS-LOGIC.md` §1.6/1.14, `docs/archive/eval/02-STUBS-PLACEHOLDERS-DEMO-DATA.md` §2.5, `docs/archive/eval/05-BACKEND-DATA-PERSISTENCE.md` §5.5/5.7, `docs/changes-18/summary.md` + `implementation-details.md` §3, `docs/qring/README.md` |

---

## 1. Phone modes (Focus / Prayer / Base)

### Purpose

Automate phone interruption filter (Do Not Disturb) based on user-selected mode for focus or short prayer sessions.

### Modes

| Mode | Product intent | Native behavior (Android) |
|------|----------------|---------------------------|
| **Base** | Normal interruptions (default) | `INTERRUPTION_FILTER_ALL`, cancel ongoing notif |
| **Focus** | DND / reduced interruptions for deep work | Silent ringer mode + `INTERRUPTION_FILTER_PRIORITY`, live stopwatch notif (no fixed end) |
| **Prayer** | Short DND window; auto-off after ~1 minute | `INTERRUPTION_FILTER_PRIORITY` then auto `INTERRUPTION_FILTER_ALL` after `PRAYER_DND_AUTO_OFF_MS=60_000L` via process-wide `Handler` (survives Flutter engine death while process lives) |

### Requirements

| ID | Requirement |
|----|-------------|
| MODE-01 | User selects mode from Home segment and/or Alarms & Notifications settings (`AlarmModeProvider.setMode`, `_channel com.sundr.myapp/phone_mode`). |
| MODE-02 | On Android, mode applies system interruption filter when `isDndAccessGranted`, else returns `PhoneModeResult.needsDndAccess` and prompts `_promptDndAccess` → `openDndAccessSettings`. Methods: `isDndAccessGranted`, `openDndAccessSettings`, `setInterruptionFilter(PRIORITY/ALL)`. |
| MODE-03 | Prayer auto-off is **native** (`PhoneModePlugin` `handler.postDelayed(runnable, durationMs)`, `pendingDndOff` dedupe: `removeCallbacks` before re-post, no stacking) so it survives Flutter engine death while process lives. Duration: `autoOffAfterOneMinute ? PRAYER_DND_AUTO_OFF_MS : custom`; notifier countdown (`showPrayer(context, now + PRAYER_DND_AUTO_OFF_MS)`) reflects real DND-off time, not fake timer. |
| MODE-04 | Today's mode sessions listed for feedback (`BleProvider.getPhoneModeSessionsToday()` → `_ble.getPhoneModeSessions(fromDayStartMs, toDayStartMs)` over local midnight→now; native `phone_mode_session` table via `ReadingRepository`; single authority `qring_local.db`). |
| MODE-05 | iOS: no public DND API — UI keeps local state only; never claim system DND (`PhoneModeResult.unsupported` path). |
| MODE-06 | Sleep reminder scheduling coexists without corrupting SharedPreferences types: `PrayerSchedulePrefs` stores `prayer_mode_start_hour/minute`, `prayer_mode_end_hour/minute` as **strings** (`setString`/`int.tryParse`), defaults 22:30→06:30, because Android `shared_preferences` stores Dart ints as Long and native `getInt()` would crash (eval 01.14; harmless until native consumer exists; `load()` returns `(start,end)`). |
| MODE-07 | Notifier parity: `PhoneModeNotifier.showFocus` (title "Focus mode", `COLOR_FOCUS=0xFFE08A4A`), `showPrayer` (title "Prayer mode", `COLOR_PRAYER=0xFF34D399`, `endsAtMs`), `cancel()`, channel "Shows the active Focus/Prayer mode with a live timer" (`ensureChannel`, `launchIntent` PendingIntent). Colors match `AppTheme.focus/success` in Flutter Alarms card. |
| MODE-08 | `AlarmModeProvider` initial `_mode = PhoneMode.focus`; `setMode` branches `focus` (silent), `prayer` (loads `PrayerSchedulePrefs.load()` window), `base` (cancel); ongoing colorized notification mirrors mode (stopwatch vs countdown vs none). |

### Prayer feature surfaces (live)

- `prayer_session_screen.dart` (~651 lines) — active session UX + live 13-metric tracking (`PrayerMetricSnapshot{timestamp,heartRate,hrv,spo2,bpSystolic,bpDiastolic,skinTempC,stressIndex,steps,calories,distanceMeters,restRate,respirationRate,calmnessScore}`), calmness rating (`≥85 Serene & Deep Rest`, `≥70 Calm & Peaceful`, `≥50 Relaxing`, else `Restless`), `startWorkout('Prayer', nowMs)`.
- `prayer_summary_screen.dart` (~280 lines) — end summary; writes `.from('workouts').insert(...)` (eval 01.6/02.5 ✅ fixed: `workouts` table created in `20260806000000_missing_tables.sql` with RLS + owner policy; squashed into `00000000000000_init.sql`).
- `prayer_history_screen.dart` (~620 lines) — past sessions; `.from('workouts').select(...).order('created_at')` (was `started_at` — fixed; summary writes `created_at`).
- `prayer_schedule_screen.dart` / `PrayerSchedulePrefs` — schedule config (see MODE-06).
- `PrayerSessionProvider` (`prayer_session_provider.dart`): 5 s sample interval (`_sampleInterval=5s`, was 1 s with 7 Room reads + notify per tick — battery fix), `_sessionCooldownMs=30000` (never zero; zero bypasses native 30 s floor and makes loop continuous), `_maxSnapshots=1000`, `startSession(ble)` (baseline steps, elevated ring mode), `dispose()` override cancels `_timer`, calls `_bleService.stopWorkout()` + `setCycleCooldownMs(180000)` if session active (changes-18 §3/§4 ✅ fixed leak; 180000 = restore value, 30000 = session value — both intentional).

| ID | Requirement |
|----|-------------|
| MODE-10 | Prayer session elevates (not continuous) ring measurement (`setCycleCooldownMs(30000)` + `startWorkout('Prayer')`); on `dispose`/`endSession` restores `setCycleCooldownMs(180000)` + `stopWorkout()`. |
| MODE-11 | Prayer summary/history round-trip via Supabase `workouts` table (RLS owner); history orders by `created_at`; empty DB no longer 404s. `prayer_session_screen.dart:537` 'Simulated Data' label path stays correctly labeled. |
| MODE-12 | `muslimMode` toggle (`advanced_settings_screen:104`) gates Muslim surfaces only; no behavior change to modes. |

---

## 2. Drink reminder

| ID | Requirement |
|----|-------------|
| REM-10 | User enables/disables drink reminder. |
| REM-11 | Configure time window + interval; push to ring via `get/setDrinkReminder`. |
| REM-12 | Settings readable after reconnect. |

Screen: `drink_reminder_screen.dart` (`/drink-reminder`).

---

## 3. Sedentary reminder

| ID | Requirement |
|----|-------------|
| REM-20 | User enables/disables sedentary reminder. |
| REM-21 | Configure window, interval, step threshold. |
| REM-22 | Persist via `get/setSedentaryReminder` to ring/native. |

Screen: `sedentary_reminder_screen.dart` (`/sedentary-reminder`).

---

## 4. Sleep schedule / reminder

| ID | Requirement |
|----|-------------|
| REM-30 | User sets preferred sleep reminder time. |
| REM-31 | SharedPreferences encoding remains compatible with native `getInt`/`getString` expectations (string-encoded times for native readers; do not "fix" types without updating native readers). Namespaces isolated: `unit_prefs`, `goal_prefs`, `home_card_prefs`, `notification_prefs`, `prayer_schedule_prefs` (eval 05.7). |
| REM-32 | Sleep reminder notifier fires as local Android notification when due. |

---

## 5. Social & religious expansion (Phase-3 infused; stubs in DESIGN.md glass)

Status kickoff 2026-08-27 14:00; table refreshed 2026-09-19 (34-table squash). Preserve QRing MENA market while keeping Sundr premium dark.

### 5.1 Qibla + Quran

- `QiblaService` (`lib/services/qibla_service.dart`): `KaabaLat=21.4225`, `KaabaLng=39.8262`, `bearing(lat,lng)` haversine (`atan2(sin(dLng), cos(phi)*tan(phiK) - sin(phi)*cos(dLng))`), `getCurrentPosition()` via `Geolocator` (service check, `requestPermission`, `LocationAccuracy.medium`, 8 s `timeLimit`; caches `qibla_last_lat/lng/bearing` in SharedPreferences), `getLastKnown()`, `compassStream()` via `FlutterCompass.events` (`e.heading ?? 0`, `distinct()`; `Stream.value(0)` fallback-only), `qiblaOffsetStream(qiblaBearing) = (bearing - heading + 360) % 360`. QRing ref: `Adhan calculateQiblaDirection` + `QiblaDirection(lastQiblaAngle)`; acceptance: bearing within ±5° of QRing `lastQiblaAngle`. (Task lists `TYPE_ROTATION_VECTOR` — current code uses `flutter_compass` abstraction over it; sensor intent identical.)
- `QiblaScreen` (`lib/screens/quran/qibla_screen.dart`): compass `CustomPainter`, reuse gold `#C9A86E`; demo `Riyadh→Kaaba`; `GlassCard` + `QiblaService.bearing`.
- `quran_screen.dart` + `assets/quran/quran.json` (117321 bytes, `qring_extracted/quran.json`) + `QuranChapterDetail`; bookmark `is_collection` mirrors `quran_entity(content_uuid,title_json,is_collection)`; offline chapter list required.
- `muslim_goal_v2_screen.dart` + `MuslimOffsetTimeDialog` (mirrors `layout_dialog_muslim_offset_time.xml`) — ⬜ Not Started.
- Supabase: `user_quran_bookmarks(user_id,chapter_index,is_collection default true,created_at)` PK `(user_id,chapter_index)` ✅ present; `user_worship_times` mirror of `worship_time_entity(worship_uuid,date_str,worship_time,is_selected,offset_time)` ❌ absent (never created) — must create if worship times ship.

| ID | Requirement |
|----|-------------|
| MODE-20 | Qibla bearing via `QiblaService.bearing` + `Geolocator` + compass; ±5° vs QRing; gold CustomPainter; Riyadh→Kaaba demo allowed only as stub placeholder. |
| MODE-21 | Quran offline list from `assets/quran/quran.json` (117321 bytes); bookmark persists `is_collection` to `user_quran_bookmarks`. |
| MODE-22 | `muslim_goal_v2` offset dialog pending; `user_worship_times` table absent — do not ship worship-times UI until migration lands. |

### 5.2 Friends / Lover (reuse caregiver)

- QRing ref: `activity_friends_home/ranking/lover_space/memorial`, `FriendsRepository/LoverRepository`, `RingStepUpdateEvent`, `syncFriendsDataToServer(StepModel/LunchSleep)`.
- Sundr: `friends_screen.dart` ranking + `LoverSpace` memorial + `MyQrCode` `QRCodeScan` (existing `qr_code_scan` dep); routes `/friends`; `GlassCard`; invite via QR works without ring (pure cloud) — acceptance.
- `BleProvider.syncFriendsDataToServer` stub calls `FriendsRepository.sync` (not wired).
- Supabase: `user_friends(user_id,friend_user_id,status default 'pending',created_at)` PK `(user_id,friend_user_id)` ✅ present; `lover_links` ❌ absent (reuse `caregiver_links` type column proposed, never built); link-request UI not built.

| ID | Requirement |
|----|-------------|
| MODE-23 | Friends ranking + LoverSpace + MyQrCode stub in glass; QR invite cloud-only. |
| MODE-24 | `lover_links` absent — do not claim lover-link persistence; caregiver-link reuse undecided. |

### 5.3 Nutrition

- `NutritionLog{date,calories,carbs default 0,protein default 0,fat default 0}` (`lib/models/nutrition_model.dart`), `fromMap/toMap(userId)` with `yyyy-MM-dd` date key; `nutrition_screen.dart` reuses `MetricChartCard` (+ `GlassCard`, `_kLocalKey='nutrition_logs_v1'` SharedPreferences fallback, Supabase `user_nutrition_logs` select `order date limit 30`); routes `/nutrition`.
- Supabase: `user_nutrition_logs(user_id,date,calories,carbs default 0,protein default 0,fat default 0,created_at)` PK `(user_id,date)` ✅ present (unique per day).

| ID | Requirement |
|----|-------------|
| MODE-25 | Nutrition log CRUD via `NutritionLog` + `MetricChartCard`; cloud PK `(user_id,date)`; local cache key `nutrition_logs_v1`. |

### Phase-3 completion snapshot (2026-08-27 14:00)

| # | Item | Location | Status |
|---|------|----------|--------|
| 1 | `qibla_service.dart` Geolocator + adhan bearing | `lib/services/qibla_service.dart` | ✅ Completed (`FlutterCompass.events`; `Stream.value(0)` fallback-only) |
| 2 | `quran_screen.dart` + quran.json bookmark | `lib/screens/quran/quran_screen.dart` | ✅ Completed (stub, GlassCard + placeholder, 117321 bytes) |
| 3 | `QiblaScreen` CustomPainter gold | `lib/screens/quran/qibla_screen.dart` | ✅ Completed (stub, Riyadh→Kaaba) |
| 4 | `muslim_goal_v2` offset dialog | `lib/screens/prayer/muslim_goal_v2_screen.dart` | ⬜ Not Started |
| 5 | `user_quran_bookmarks` (+ worship absent) | `00000000000000_init.sql` | 🟡 Partial |
| 6 | `user_friends` (+ lover absent) | `00000000000000_init.sql` | 🟡 Partial |
| 7 | friends ranking + LoverSpace + MyQrCode | `lib/screens/social/friends_screen.dart` | ✅ Completed (stub, `/friends`) |
| 8 | Nutrition model + screen | `lib/models/nutrition_model.dart` + `lib/screens/nutrition/nutrition_screen.dart` | ✅ Completed (stub, `MetricChartCard`, `/nutrition`) |
| 9 | Routes `/quran /qibla /friends /nutrition` | `lib/app.dart` (47 routes, was 28) | ✅ Completed |

Risks: keep `faq_screen.dart:46` QRing FAQ verbatim but Sundr dark; avoid light `qring_extracted` bg.

---

## 6. Acceptance criteria

- [ ] Android: Focus changes interruption filter (with notification policy access); needs-access path prompts settings.
- [ ] Prayer returns to Base after ~1 minute (`PRAYER_DND_AUTO_OFF_MS=60_000L`) even if UI closed (native Handler).
- [ ] Drink/sedentary round-trip after restart with ring connected.
- [ ] iOS does not crash on toggle (local state only).
- [ ] Prayer session → summary → history round-trips via `workouts` ordered by `created_at`; dispose restores 180000 cooldown, no timer leak.
- [ ] Qibla ±5°; Quran offline; friends QR without ring.
- [ ] Prefs namespaces isolated; ints-as-strings preserved for native `getInt` safety.
- [ ] `flutter analyze` no `qc_setting` orphans (phase-5 cross-check).

---

## 7. Related

- [04-home-dashboard.md](./04-home-dashboard.md), [10-settings-device.md](./10-settings-device.md)
- `docs/qring/phase-3-social-religious.md`, `docs/changes-18/*`, `docs/archive/eval/01*` §1.6/1.14, `02*` §2.5, `05*` §5.5/5.7
