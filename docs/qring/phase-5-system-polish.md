# Phase 5 — System Polish & `qc_setting_*` Parity

> **Status:** IN PROGRESS `2026-08-27` — 4 interval families, 34 tables (single squashed migration) — 2 weeks + release hardening.

## QRing `qc_setting_*` 42 ids (`aapt dump` `0x7f0904f4`)
`qc_setting_ai_push, album, battery_warming, blood_oxygen, blood_pressure, call, call_reminder, camera, contact, dfu, disturb/manual, ebook, find_watch, gesture/light, health_analysis, heart/not, hrv, light, map, message(push per package), more, music, pressure, real_time_heart, record, reminder, screen_time, system, temp/alarms(3), time, too_high/low_heart, unit, wear, weather` + `ring_setting_gesture/touch` + `goal_setting_*5`.

## Sundr Now `lib/screens/settings` 27 files
`device_settings_screen:96`, `advanced_settings:114` (`batterySaving, agpsEnable, touchControl, intell, muslimMode`), `notification_settings:115` (`ancsEnable, dnd`), `select_notifications:131` **STUB** 10 keys (`High/Low HR/SpO2/BP, High Temp, Step Goal, Low Battery`) not ring-persisted, `display:145`, `target_profile:232`, `health_settings:521` per-vital toggles + `cycleCooldown 1-15m`, `gesture:488` `PalmScreenReq`, `find_device:499`, `ota:424` `DfuHandle`, `ring_camera:317`, `touch_control:170`, `faq:379` QRing verbatim.

### Gaps
- `LargeDataHandler` interval families implemented: HR, SpO₂, Temperature, Sleep (4 families) — Temperature/Pressure/HRV interval semantics partly unverified, `Blood Sugar`, `ECG` missing.
- `SettingRepository/DeviceSettingRepository` `getDeviceConfig/getFirmwareInfo/getDeviceContact/getDeviceDisplay/getDeviceLocation/getSoftwareQrCode/checkOta` 30 toggles vs Sundr 60% `qc_setting`.
- Supabase 34 tables in the single squashed migration vs QRing `40+` (covered: `user_ecg/breath/blood_sugar/nutrition/friends/watchface/quran`).
- Release signing `debug` (`specs/00-product-overview.md` stub list), `architecture/` folder exists (`architecture/Overview.md` + 5 more).

## Plan

### 5.1 Settings Parity
- Wire `select_notifications_screen` to ring `postHealthAlert` per-app routing (QRing `MessagePushActivity/OtherSoftwareActivity`) — persist `NotificationPrefs` to `DeviceSetting:healthAnalysis` via `BlePlugin:344` `sendNotification`.
- Fill `qc_setting_battery_warming/find_watch/album/ebook/music/wear/map/weather/time` dialogs (`layout_dialog_battery_*.xml`, `screen_light.xml`) — reuse `DESIGN.md` glass.

### 5.2 LargeData & Sync
- Verify `Temperature` interval float handling (`IntervalTemperatureEntity$IntervalTemperature value1`) — add unit test with mocked `List<Float> 36.5f`.
- Add `HRV LargeData` if firmware `supportHrv` flag true (check `getDeviceSupport` `0x7f...`).

### 5.3 Cloud Tables (landed in squashed `00000000000000_init.sql`)
- `user_records(user_id, record_type, subtitle)`, ensure `delete_user_account()` loop covers all new `user_*` via `to_regclass` guard.

### 5.4 Release
- Keystore `android/gradle.properties` `MYAPP_UPLOAD_*`, `architecture/` already present (`Overview.md` etc.) — update `specs/README`.

### Completion Table (2026-08-27)

| # | Item | Location | Status | Notes |
|---|------|----------|--------|-------|
| 1 | `qc_setting_*` 42 ids parity | `lib/screens/settings` 27 files | 🟡 Partial 60% | 15 families missing (breath/ecg/quran/etc.) |
| 2 | `LargeDataHandler` interval families | `BlePlugin.kt` | 🟡 4 families (`HR/SpO₂/Temp/Sleep`) | Still missing `Blood Sugar/ECG, HRV interval` |
| 3 | Supabase tables | `supabase/migrations/00000000000000_init.sql` | 🟡 34 tables (squashed, incl. `ecg/breath/sugar/nutrition/friends/watchface/quran`) | QRing `40+` as reference |
| 4 | Release signing debug → `MYAPP_UPLOAD_*` | `android/gradle.properties` | ⬜ Not Started |  |
| 5 | `select_notifications_screen` ring persist `postHealthAlert` | `lib/screens/settings/select_notifications_screen.dart:131` | ⬜ Not Started | Local `NotificationPrefs` only |

### Next: `Temperature` float unit test mocked `36.5f`, `HRV LargeData` flag check, `user_records` migration, keystore.

### Acceptance
- `flutter analyze` no `qc_setting` orphan ids, `gradle :app:assembleRelease` signed.

