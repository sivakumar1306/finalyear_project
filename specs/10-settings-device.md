# 10 — Settings, Device Controls & Account

| Field | Value |
|-------|-------|
| **Status** | Partial (core shipped; some stubs) |
| **Key code** | `lib/screens/settings/*` (27 files), OTA, FAQ, legal screens |
| **QRing parity ref** | `qc_setting_*` 42 ids (`aapt dump` `0x7f0904f4`); `goal_setting_*` ×5; `ring_setting_gesture/touch` |
| **Release signing** | `debug` → `MYAPP_UPLOAD_*` (`android/gradle.properties`) — open (see SET-50) |

---

## 1. Purpose

Central place for device configuration, health intervals, account management, safety features, and support content.

---

## 2. Settings hub

`settings_screen.dart` — ring info card + navigation list into sub-screens.

Must surface connection/battery summary consistent with `BleProvider`.

The 27 settings files (`lib/screens/settings/`):

| # | File | Domain |
|---|------|--------|
| 1 | `settings_screen.dart` | Hub |
| 2 | `device_settings_screen.dart:96` | Index nav |
| 3 | `display_settings_screen.dart:145` | Display |
| 4 | `advanced_settings_screen.dart:104,114` | Advanced |
| 5 | `touch_control_screen.dart:170` | Touch |
| 6 | `gesture_settings_screen.dart:227,488` | Gestures (`PalmScreenReq`) |
| 7 | `find_device_screen.dart:499` | Find |
| 8 | `ring_camera_screen.dart:317` | Camera |
| 9 | `target_profile_screen.dart:232` | Targets/profile |
| 10 | `health_settings_screen.dart:521` | Health loop |
| 11 | `notification_settings_screen.dart:115` | Notifications |
| 12 | `select_notifications_screen.dart:131` | Alert-type picker — STUB |
| 13 | `alarms_notifications_screen.dart` | Alarms/modes/sleep reminder |
| 14 | `sleep_schedule_screen.dart` | Sleep schedule |
| 15 | `focus_schedule_screen.dart` | Focus schedule |
| 16 | `prayer_schedule_screen.dart` | Prayer schedule |
| 17 | `goal_setting_screen.dart:454` | Goals |
| 18 | `health_connect_screen.dart` | Health Connect bridge |
| 19 | `fall_detection_screen.dart` + `fall_detection_widgets.dart` | Fall |
| 20 | `background_protection_screen.dart` | OEM whitelist |
| 21 | `account_system_settings_screen.dart` | Account/system |
| 22 | `profile_edit_screen.dart` | Profile |
| 23 | `privacy_policy_screen.dart` | Legal |
| 24 | `terms_of_service_screen.dart` | Legal |
| 25 | `faq_screen.dart:46,379` | FAQ (QRing verbatim, Sundr dark skin) |
| 26 | `about_screen.dart:96` | About/version |
| 27 | OTA screen (`ota:424`, `DfuHandle`) | Firmware |

---

## 3. Device & ring settings

| Screen / route | Requirements | Status |
|----------------|--------------|--------|
| Device settings index | Navigation only | Shipped |
| Display settings | Brightness, screen-on duration, clock style, 24h, wrist orientation | Shipped |
| Advanced settings | Battery saving, AGPS, touch, intelligent settings, prayer reminder flags | Shipped |
| Touch control | Enable sensor; live gesture log; client double-tap synthesis (~400ms) | Shipped |
| Gesture settings | Configure ring gestures | Shipped |
| Find device | Trigger ring find/alert if SDK supports | Shipped / SDK-dependent |
| Ring camera | Camera shutter integration via ring events | Shipped / partial |
| Target profile | Daily steps/calories/sleep/distance targets + body profile to ring | Shipped |
| Health settings | Per-vital monitor toggle + intervals | Shipped |
| Notification settings | ANCS, DND window, per-app, music control | Shipped |
| Select notifications | Alert-type picker, persisted (`NotificationPrefs`) and honored by live phone alerts | Partial (ring-side persist open) |
| Drink / sedentary | See [09](./09-phone-modes-reminders.md) | Shipped |
| OTA | Pick `.bin`, confirm, progress bar via events | Shipped |
| Fall detection | See [05](./05-fall-detection-safety.md) | Partial |
| Health Connect | Android Health Connect bridge (`health` package `13.3.2`): 8 types read/write (steps, HR, HRV, SpO2, sleep, BP, temperature, menstruation) | Partial (enabled-subset auth; verify Android 14+ UX on device) |
| Measurement log | Per-vital History entry + flag-gated settings entry (`AppConfig.includeMeasurementLog`) | Shipped |
| Sugar & lipids | Ring monitor-state reads + channel toggles (`get/setHealthSettings`) | Shipped (continuous-glucose BLE itself is a `"[]"` stub) |
| Background protection | OEM battery whitelist guidance | Shipped / OEM-specific |
| Card settings | Home card layout prefs | Shipped |
| Goal setting | Goals prefs | Shipped |
| Alarms & notifications | Modes + sleep reminder + session history | Shipped |
| Prayer schedule | Schedule prefs | Shipped |

### 3.1 Settings channel inventory (mapped ✅ — `docs/mappings/sdk-vs-plugin.md`)

| ID | Requirement |
|----|-------------|
| SET-01 | `get/setHeartRateSetting`, `get/setHrvSetting`, `get/setBloodOxygenSetting`, `get/setBloodPressureSetting`, `get/setPressureSetting`, `get/setTemperatureSetting` are bridged end-to-end (channel → `BleOperateManager` → Dart). |
| SET-02 | `get/setTargetAndProfile` (daily steps/calories/sleep/distance targets + body profile) is bridged; `TargetProfile` writes land on-ring. |
| SET-03 | `getHealthSettings` / `setHealthSettings` (incl. sugar & lipids monitor-state reads + channel toggles) are bridged. |
| SET-04 | `getDeviceSupport` (firmware capability flags — incl. `supportHrv` / `supportTemperatureBoth` checks), `getAdvancedSettings`, `read/setRriAutoMeasure`, `read/setEmotionAutoMeasure` are bridged. |
| SET-05 | `SettingRepository` / `DeviceSettingRepository` extended surface — `getDeviceConfig`, `getFirmwareInfo`, `getDeviceContact`, `getDeviceDisplay`, `getDeviceLocation`, `getSoftwareQrCode`, `checkOta` — ~30 toggles vs Sundr ~60% `qc_setting` coverage (phase-5 gap: fill `qc_setting_battery_warming/find_watch/album/ebook/music/wear/map/weather/time` dialogs, `layout_dialog_battery_*.xml`, `screen_light.xml`, reusing `DESIGN.md` glass). |

### 3.2 QRing `qc_setting_*` 42-id parity table (phase-5, `aapt dump` `0x7f0904f4`)

QRing ids: `qc_setting_ai_push, album, battery_warming, blood_oxygen, blood_pressure, call, call_reminder, camera, contact, dfu, disturb, disturb_manual, ebook, find_watch, gesture, gesture_light, health_analysis, heart, heart_not, hrv, light, map, message (push per package), more, music, pressure, real_time_heart, record, reminder, screen_time, system, temp, temp_alarms (×3), time, too_high_heart, too_low_heart, unit, wear, weather` + `ring_setting_gesture/touch` + `goal_setting_*` ×5.

| ID | Requirement |
|----|-------------|
| SET-06 | `advanced_settings_screen:114` carries `batterySaving, agpsEnable, touchControl, intell, muslimMode`; `notification_settings_screen:115` carries `ancsEnable, dnd`; `display_settings:145` carries brightness/screen-on/clock/24h/orientation. Missing families (`breath/ecg/quran` etc., ~15 of 42) stay explicitly out of scope until a consumer lands. |
| SET-07 | Health settings (`health_settings_screen:521`): per-vital monitor toggles + `cycleCooldown 1–15 min` (`MeasurementConfig.getCycleCooldownMs()`); toggling a vital off removes it from the loop (observable after reconnect/cycle). |
| SET-08 | `select_notifications_screen:131` STUB: 10 keys (`High/Low HR/SpO2/BP, High Temp, Step Goal, Low Battery`) persisted to local `NotificationPrefs` and honored by the live phone-alert pipeline; ring-side persist via `postHealthAlert` per-app routing (QRing `MessagePushActivity/OtherSoftwareActivity`) through `BlePlugin:344` `sendNotification` → `DeviceSetting:healthAnalysis` remains OPEN (phase-5 item 5, Not Started). |

### OTA requirements

| ID | Requirement |
|----|-------------|
| SET-10 | User selects firmware `.bin` via file picker. |
| SET-11 | Confirm destructive/time-consuming update before start. |
| SET-12 | Show live progress from native DFU state machine. |
| SET-13 | Cloud catalog table `firmware_updates` (version, URL, notes, mandatory flag) drives the in-app releases list; auto-update prompts remain future. |
| SET-14 | `ota_screen:424` `DfuHandle` is the single DFU surface; watchface installs reuse `FileHandle` OTA `startOta(filePath)` / `DownloadWithoutNotification` (phase-4). Native stubs `BlePlugin.kt:318-334` (`getDisplaySettings`, `setDisplaySetting`, `getTargetAndProfile`, `setTargetAndProfile`, `getAdvancedSettings`, `setAdvancedSetting`, `sendNotification` canned values) must be replaced with real SDK plumbing before store release. |

### 3.3 LargeData interval families (4 landed, 2 missing)

| ID | Requirement |
|----|-------------|
| SET-15 | `LargeDataHandler` interval families implemented: HR, SpO₂, Temperature, Sleep (4 families, ~22 s transfer each) feeding `BlePlugin syncInterval*Detail` (see BLE-28). Missing: Blood Sugar, ECG; HRV interval gated on firmware `supportHrv`; Temperature/Pressure/HRV interval semantics partly unverified — verify Temperature float handling (`IntervalTemperatureEntity$IntervalTemperature value1`) with a unit test mocking `List<Float> 36.5f`. |

### 3.4 Health Connect bridge (`health: ^13.3.2`, `docs/bugs-fixes/06`)

| ID | Requirement |
|----|-------------|
| SET-16 | 8 types read/write via `lib/services/health_connect_service.dart` + `health_connect_screen.dart`: steps, heart rate, HRV (`tryWriteHrv`, `ble_provider:545,579` `_pushToHealthConnect('hrv')`), SpO₂, sleep, BP, temperature, menstruation. |
| SET-17 | `_connect()` requests the **enabled subset** (`requestAuthorization(_enabled)`, narrowed from the bulk-all-types proposal after review); `_toggle()` saves the set + refreshes grants/today (`saveEnabledTypes` + `_refreshGrantedAndToday`), no single-type sheet; denial recomputes toggle state from refreshed grants with snackbar ("permission not granted — nothing will sync"); `revokeAll()` on disconnect. |
| SET-18 | `tryWriteSleep`: `dayKey` is the local date string `YYYY-MM-DD` (`${sleepTime.year}-${mm}-${dd}`, deterministic replace — never UTC `millis ~/ 86400000`); `end` fallback `DateTime(year, month, day+1, wakeHour, wakeMinute)` +1 day handles overnight 23:00→07:00. |
| SET-19 | `fetchToday`: `sumMinutes` detects `SLEEP_*` and sums `p.dateTo.difference(p.dateFrom).inMinutes` (never `_numValue`, which yields 0 for interval sleep); computes `asleepM, deepM, lightM, remM, awakeM, inBedM`, `totalSleep = asleep != 0 ? asleep : deep+light+rem ?: inBed`; returns `sleepMinutes: totalSleep != 0 ? totalSleep : null`. |
| SET-20 | `health_connector 3.10.0` migration is a REVERTED spike (never merged: `pubspec.yaml`/`pubspec.lock` still `health: ^13.3.2` only, `health_connect_service.dart:119` still `import 'package:health/health.dart'` + `Health()`, no `compileSdkExtension` in `app/build.gradle.kts`): the `health`→`health_connector` API gap (`Health().configure()`→`HealthConnector.create()`, `isHealthConnectAvailable()`→`getHealthPlatformStatus()`, `installHealthConnect()`→`launchHealthAppPageInAppStore()`, `hasPermissions`→`getGrantedPermissions()`, `writeHealthData`→`*Record` types incl. `HeartRateRecord/OxygenSaturationRecord/BloodPressureRecord/HeartRateVariabilityRmssdRecord/SleepSessionRecord+SleepStageRecord/BodyTemperatureRecord/MenstrualFlowRecord/StepsRecord`, `getTotalStepsInInterval`→`aggregateSum`, `getHealthDataFromTypes`→`readRecords`+pagination) requires a full `health_connect_service_v2.dart` behind a flag + API-26 device verification before `health` is removed and `android.builtInKotlin=true` is flipped. |
| SET-21 | QRing reference declares Health Connect `WRITE_STEPS`, `WRITE_HEART_RATE`, `WRITE_SLEEP`, `WRITE_TOTAL_CALORIES_BURNED`; this app additionally writes SpO₂, HRV, BP, temperature. Android 14+ 30-day history unlock requested best-effort (`health_connect_service.dart:214-219`). |

### 3.5 Social / religious settings context (phase-3)

| ID | Requirement |
|----|-------------|
| SET-22 | `advanced_settings_screen:104` exposes the `muslimMode` toggle (only Muslim setting in Advanced today); full Muslim expansion (`qibla_service.dart` `SensorManager TYPE_ROTATION_VECTOR` + `Geolocator` + `adhan2 Qibla` → bearing ±5° of QRing `lastQiblaAngle`; `quran_screen` + `assets/quran/quran.json` bookmark `is_collection`; `QiblaScreen` compass `CustomPainter` gold `#C9A86E`; `muslim_goal_v2_screen` offset dialog from `layout_dialog_muslim_offset_time.xml` — PENDING; `user_quran_bookmarks` landed, `user_worship_times` never created) is tracked in social/religious specs, not here. |
| SET-23 | `qc_goal_*` ×5 nutrition/goal ids map to `goal_setting_screen:454` (steps/calories/sleep only today) + `nutrition_screen` stub (`NutritionLog(date, calories, carbs, protein)`, `user_nutrition_logs(user_id,date,calories)` unique); per-sport targets (`perSportTarget`) live in workout specs. |

### 3.6 Multimedia / device settings context (phase-4)

| ID | Requirement |
|----|-------------|
| SET-24 | Watchface (`watchface_store_screen` grid `WatchMarketFragment`, DIY omitted first cut, route `/watchface`), Album (`album_screen`, device-local `albumRepository`, `scanMediaFile` passthrough), Ebook (`ebook_screen` stub reader, font), Music (`music_album_screen`, `MusicRepository`, `gesture_settings:227 toggleMediaPlayPause` only today), Display (`ScreenLightActivity` ↔ `display_settings_screen:145`), Camera (`CameraActivity`/`CameraReq` `BlePlugin:200+` ↔ `ring_camera_screen:317` shutter) are stubbed behind routes; sport-type detail (`sport_type_detail_screen`, ring per-type trace via `SportPlusHandle` `BlePlugin:99`, `getSportDetail(type, date)` → cache `user_workouts`) depth is pending. GPS trace is phone-`geolocator` polyline (`gps_trace_screen`, `user_workouts.locations` jsonb, no `google_maps_flutter` dep) — ring has no coordinates. |

---

## 4. Account & profile

| Screen | Requirements | Status |
|--------|--------------|--------|
| Account & system | Profile nav, logout, factory reset, delete account | Partial (some placeholders historically) |
| Profile edit | Edit name/gender/age/height/weight → Supabase upsert | Shipped |
| Privacy policy | Static legal content | Shipped |
| Terms of service | Static legal content | Shipped |
| FAQ | Support content | Shipped |
| About | Version / branding | Shipped |

| ID | Requirement |
|----|-------------|
| SET-30 | Logout clears session and native login/sync flags. |
| SET-31 | Delete account calls server RPC and returns user to auth. |
| SET-32 | Factory reset of ring (if exposed) must confirm and only when connected. |
| SET-33 | Cloud tables landed in squashed `supabase/migrations/00000000000000_init.sql` (34 tables incl. `user_ecg/breath/blood_sugar/nutrition/friends/watchface/quran`, `user_records(user_id, record_type, subtitle)`); `delete_user_account()` loop covers all new `user_*` via `to_regclass` guard (QRing 40+ as reference). |

---

## 5. Stub / incomplete (explicit, verified 2026-09-19)

| Feature | Expected completion |
|---------|---------------------|
| Select notifications → ring | Persist choices on-ring and honor in ring alert pipeline (phone pipeline already honors them) |
| Continuous-sugar / ECG BLE | Real SDK calls (`getContinuousSugar` returns `"[]"` stub, `startEcgMeasure` returns `"{}"` stub) |
| Sport type detail depth | Parse ring per-type trace fields beyond current stub screen |
| Records index | No such screen exists — remove from scope or spec it as new work |
| `muslim_goal_v2` offset dialog | Build `MuslimOffsetTimeDialog` from `layout_dialog_muslim_offset_time.xml` |
| Release signing | Migrate `debug` keystore → `MYAPP_UPLOAD_*` (`android/gradle.properties`); fail release build when `key.properties` absent |

---

## 6. Acceptance criteria

- [ ] Health settings toggle disables a vital in the loop (observable after reconnect/cycle).  
- [ ] Display setting change reflects on ring UI.  
- [ ] OTA progress advances during a test firmware transfer on supported hardware.  
- [ ] Profile edit updates Home greeting/name.  
- [ ] Logout requires re-authentication to access Home data.  
- [ ] `flutter analyze` shows no `qc_setting` orphan ids; `gradle :app:assembleRelease` signed (once SET-50 lands).  
- [ ] Health Connect: connect once → one system sheet → grant → all switches flip; sleep written overnight reads back staged minutes.  

---

## 7. Related

- [02-device-pairing-ble.md](./02-device-pairing-ble.md)  
- [01-auth-onboarding.md](./01-auth-onboarding.md)
- `docs/qring/phase-5-system-polish.md`, `docs/qring/phase-3-social-religious.md`, `docs/qring/phase-4-multimedia-sport.md`
- `docs/bugs-fixes/06-health-connect-sleep-fix.md`, `docs/bugs-fixes/07-health-connector-spike.md`
