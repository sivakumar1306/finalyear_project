# Phase 2 — Detailed Health Gaps (ECG, Breath, Blood Sugar/Lipids, Pressure)

> **Status:** IN PROGRESS `2026-08-27` — scaffolding completed, BLE/Supabase pending — 3–4 weeks est.

## QRing Reference
- **ECG:** `activity_ecg.xml/detail/guild/measure/list` 5 layouts, `EcgRepository` `qc_ecg_entity(device_address,date_str,type,data_list,avg_heart,unix_time)` `CMD_ECG_MEASURE_TIME`, `ECGSurfaceView`, `EcgYAxisRange` (`classes5.dex` `+ 1 EcgRepository.kt`, `res/layout/activity_ecg*.xml:qring_extracted`).
- **Breath:** 8 layouts `activity_breath_home/category/training/finish/record/detail/audio/setting` `BreathTrainingRepository` `breath_audio` table (`asset_path,download_status,file_size`) 30+ methods (`balance_equal`, `bellows`, `taichi`), `breath_training_record(id,method_id,average_heart_rate,inhale_seconds…)` `LargeDataHandler` not used (manual timer + ring HR).
- **Blood Sugar/Lipids:** `activity_blood_sugar.xml/data_detail/guide` `BloodSugarRepository` `app_sugar(app_heart)` `app_continuous_sugar(mac,date_str,timestamp,min_sugar,max_sugar,hour)` CGM 1/h, `BloodSugarSettingReq` (`classes5.dex` `CREATE TABLE app_continuous_sugar`).
- **Pressure interval:** QRing `pressure_detail(device_address,date_str,interval,index_str,value,unix_time)` via `PressureReq/PressureSettingReq` + `LargeDataHandler` (gap in Sundr — `BlePlugin:1769` poll only).

## Current Stub in Sundr (`specs/03-vitals-monitoring.md:28`, `specs/10:86`)
- `lib/screens/sugar_lipids/sugar_lipids_screen.dart:200` 3 toggles `temperature/rri/emotion` via `getHealthSettings{sugarLipids}`, value `--`, no chart, no `/blood-sugar` route.
- No `lib/screens/breath/*`, no `lib/screens/ecg/*`, `lib/models/breath_model.dart` missing, `ble_service.dart` has no `syncBreath/syncEcg/syncSugar`.
- `supabase/migrations` no `user_ecg/user_breath_sessions/user_blood_sugar`.

## Plan

### 2.1 Models & Migration
- `lib/models/breath_model.dart` `BreathMethod(Category, Method, audioId, inhale/hold/exhale cycle)` + `BreathRecord` same as QRing `breath_training_record`
- `lib/models/ecg_model.dart` `EcgSample(avgHeart, dataList<List<int>>, type, unixTime)`
- `lib/models/blood_sugar_model.dart` `SugarReading(timestamp,minSugar,maxSugar,hour)`
- `supabase/migrations/20260831_detailed_health.sql` tables:
  ```sql
  user_ecg (user_id,date,avg_heart, data_list jsonb, unix_time, primary key user_id,date)
  user_breath_sessions (user_id,started_at,method_id,average_hr, subjective_feeling, primary key user_id,started_at)
  user_blood_sugar (user_id,measured_at,min_sugar,max_sugar,hour) unique user_id,measured_at
  ```
  RLS owner policies + `delete_user_account()` extension (append deletes).

### 2.2 Native BLE (`android/...`)
- `BlePlugin.kt` import `EcgReq`, `IntervalBloodSugar`? Actually `app_continuous_sugar` via `BloodSugarSettingReq` + `LargeDataHandler.syncBloodSugar` if Exists else `BleOperateManager.getContinuousSugar`; add dispatch `getBloodSugar/setBloodSugar/syncBloodSugar/startEcg/parseEcgData` + `Breath` is phone-timer only (no ring BLE, but ring HR during breath via existing `manualModeHeart`).
- `ReadingRepository.kt` `insertEcg/ecgBetween`, `insertBreathRecord`, `insertSugar` + `dailyAggregate`? Use raw `readingsBetween` for charts (ECG 500Hz decimated).
- `QRingDatabase.kt` `breathDao/ecgDao/sugarDao` + `ReadingEntities.kt` `@Entity` with `@SerializedName`.

### 2.3 Screens (reuse `DESIGN.md` card `rgba(255,255,255,0.06) blur 28px radius 20` + `MetricChartCard`)
- `lib/screens/health/breath_screen.dart` `BreathHome` method picker horizontal `BreathAudioRepository` asset + `BreathingTraining` countdown (` AnimatedCircularProgress`), live HR from `BleProvider.latestHr`, save to `user_breath_sessions` + Health Connect `tryWriteHrv` bonus.
- `lib/screens/health/ecg_screen.dart` `EcgMeasure` 30s `ECGSurfaceView` placeholder (webview or `fl_chart` polyline), `EcgHistory` list from `user_ecg`.
- `lib/screens/health/blood_sugar_screen.dart` replace stub: 24h bar `MetricBarPainter(maxY:300)` continuous sugar `app_continuous_sugar` + manual spot, interval via `LargeDataHandler` if firmware supports.
- `lib/screens/health/pressure_screen.dart:702` extend to `PressureInterval` LargeData backfill similar to Phase 1 `syncInterval*` (add `insertPressure`).

### 2.4 Sync & Provider
- `BleProvider syncAllFromRing` step `Blood Sugar` after `Temperature interval`; `_refreshEcgFromLocal` etc.
- `HealthConnect` add `tryWriteEcg` if `HealthDataType.ELECTROCARDIOGRAM`.

### 2.5 Acceptance
- Breath 2-min session persists, HR delta shown, offline list.
- ECG 30s capture mocked without ring (demo seed) shows chart.
- Sugar daily trend from `app_continuous_sugar` seed.

### Completion Table (2026-08-27)

| # | Item | Location | Status | Notes |
|---|------|----------|--------|-------|
| 1 | `breath_model.dart` `BreathMethod` catalog 4 methods + `BreathSession` | `lib/models/breath_model.dart:1` | ✅ Completed |  |
| 2 | `ecg_model.dart` `EcgSample` | `lib/models/ecg_model.dart:1` | ✅ Completed |  |
| 3 | `blood_sugar_model.dart` `BloodSugarReading` | `lib/models/blood_sugar_model.dart:1` | ✅ Completed |  |
| 4 | Migration `user_ecg/breath_sessions/blood_sugar` + RLS + `delete_user_account` | `supabase/migrations/20260901000000_phase2_detailed_health.sql:1` | ✅ Completed |  |
| 5 | `breath_screen.dart` glass + `MetricChartCard` + `BreathMethod` chip + `Timer` + Supabase save | `lib/screens/health/breath_screen.dart:1` | ✅ Completed | `flutter analyze` No issues |
| 6 | `ecg_screen.dart` `+HealthConnect` | `lib/screens/health/ecg_screen.dart:1` | ✅ Completed | Mock 120 pts `Random` |
| 7 | `blood_sugar_screen.dart` `+HealthConnect` `DateScrollRow` 24h min/max | `lib/screens/health/blood_sugar_screen.dart:1` | ✅ Completed | `MetricBarPainter maxY15` |
| 8 | Routes `/breath /ecg /blood-sugar` | `lib/app.dart:28,84` | ✅ Completed | 24 routes |
| 9 | `BleService` stubs `getContinuousSugar/startEcgMeasure` | `lib/services/ble_service.dart:663` | ✅ Completed |  |
| 10 | `BlePlugin` dispatch `getContinuousSugar/startEcgMeasure` | `BlePlugin.kt:449` | ✅ Completed |  |
| 11 | `SupabaseService` wrappers `getEcgHistory/getBreathHistory/getSugarHistory` | `lib/services/supabase_service.dart:905` | ✅ Completed |  |
| 12 | Native `EcgReq` + `LargeDataHandler.syncBloodSugar` real BLE | `BlePlugin.kt` | ⬜ Not Started | Needs ring `supportEcg` flag test |
| 13 | `ReadingRepository` `insertEcg/insertSugar` + `QRingDatabase` dao | `data/` | ⬜ Not Started |  |
| 14 | Pressure interval LargeData backfill `insertPressure` | `BlePlugin.kt` | ⬜ Not Started |  |
| 15 | Home dashboard cards for Breath/ECG/Sugar | `home_screen.dart` | ⬜ Not Started |  |
| 16 | `HealthConnect` `tryWriteEcg` | `health_connect_service.dart` | ⬜ Not Started |  |

### Risks
- ECG hardware may be subset of rings (check `DeviceSupport` `supportEcg` flag via `getDeviceSupport` `qring_extracted` `ActivitySpec`).
- Sugar CGM only on premium ring — gate via `getDeviceSupport`.

### Next Steps (to complete Phase 2)
1. Wire `BlePlugin` `EcgReq` + `getContinuousSugar` to `ReadingRepository` + `SupabaseSyncManager` 6h.
2. Add `pressure_screen.dart` interval inflate + `insertPressure` + Home card.

