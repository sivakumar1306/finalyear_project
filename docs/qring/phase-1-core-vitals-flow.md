# Phase 1 — Core Vitals Unified Flow (COMPLETED 2026-08-26)

> **Goal:** Unfreeze HR `87` and homogenize HR/SpO₂/HRV/Temp data flow so every surface (Home, Detail, Chat card, Health Connect, Supabase) shows `latest` hero + correct `avg/min/max` + interval backfill.

## Evidence
- **QRing:** `CREATE TABLE heart_rate_detail(device_address,date_str,interval,index_str,value TEXT,unix_time)` 1 blob/day + `app_heart(mac,timestamp,heart)` per-point + `manual_heart_entity` JSON/day, `LargeDataHandler.syncIntervalHeartRateWithCallback(0, IIntervalHeartRateCallback)` bulk, `HeartRateDetailRepository` discrete dots (`classes5.dex`).
- **Sundr before:** `ReadingEntities.kt:28` single `reading_heart_rate(valueBpm,measuredAt,source)` + `MeasurementLoopManager.kt:59` round-robin `7 vitals` `180s` cooldown → `~1 HR/4min`, display `AVG` (`BleProvider:1081 todayAvgHr`, `heart_rate_screen:85 _displayAvg`), `sorted[size/2]` upper-median + `|Δ|≤8` pinning `87`, cloud `user_hr(avg_hr,count:1)` `~/2` blend, fake `hourly[now.hour]=avg` (`heart_rate_screen:204`).

## Changes (file:line — absolute)

### Provider `lib/providers/ble_provider.dart`
- `:44-51` HR `latestHr/_latestHrMeasuredAt/isLatestHrStale(30m)`
- `:53-56` SpO₂ `latestSpo2/_latestSpo2MeasuredAt` + `isLatestSpo2Stale`
- `:68-71` HRV `latestHrv/_latestHrvMeasuredAt`, `todayMin/MaxHrv`
- `:188-210` getters `latestHr/spo2/hrv` + helpers
- `:273-310` `updateHrLatest/updateSpo2Latest/updateHrvData/updateHrvLatestDetailed`
- `:545-573` `_onNewReadingEvent` HRV now `unawaited(_pushToHealthConnect('hrv'))`
- `:579-605` `_pushToHealthConnect` added `hrv` `tryWriteHrv`
- `:1081-1145` `_refreshHrFromLocal` captures `lastValue/lastMeasuredAt` + fallback `getLatestReading` when `count==0`
- `:1147-1178` `_refreshSpo2FromLocal` same
- `:1379-1391` `_refreshHrvFromLocal` same
- `:1546-1656` `_initThenSync` `setHeartRateSetting(true,10)` + `syncAllFromRing` 6-step `HRV→Sleep→TempAuto→HR interval→SpO₂ interval→Temp interval` (`0.33→0.66→0.90→0.92→0.96→1.0`) with `_refresh*`.

### Native `android/app/src/main/kotlin/com/sundr/myapp/data/ReadingRepository.kt`
- `:67-84` `insertHeartRateAt(bpm,measuredAt,cycleId,source)`
- `:87-99` `insertSpo2At`
- `:122-141` `insertHrvAt`
- `:134-151` `insertTemperatureAt`

### Native `BlePlugin.kt:449,2819-2855,993-1151`
- Dispatch `insertHeartRate/insertSpo2/insertHrv/insertTemperature` + `syncInterval*Detail`
- `insert*` → `repo.startCycle → insert*At → completeCycle → EventBus NewReadingEvent`
- `syncIntervalHeartRateDetail` inflates `IntervalHeartRateEntity{dayIndex,interval,array}` → `dayStart+idx*interval*60k+30k` `insertHeartRateAt(source=interval_sync)` ±30s dedup, `syncIntervalSpo2Detail` (`bigData.IntervalBloodOxygenEntity`, `IIntervalBloodOxygenCallback`) same, `syncIntervalTemperatureDetail` handles `array:List<Float>` + `values:List<IntervalTemperature>` (`value1`) → `valueC/10` normalized `30-45` range.

### Dart bridge `lib/services/ble_service.dart:663-682`
- `insertHeartRate/insertSpo2/insertHrv/insertTemperature/syncIntervalHeartRateDetail/syncIntervalSpo2Detail/syncIntervalTemperatureDetail`

### Screens
- `lib/screens/health/heart_rate_screen.dart:63-710` `latestHr/_latestHrAt`, `_displayLatestLocal`, hero `latest>avg` + `avg · no fresh reading` pill (white `0.6`), no fake bucket, cloud only when `!hasData(local)`, `_startMeasurement` `insertHeartRate` → true `AVG/MIN/MAX/COUNT` from `getTodaySummary`.
- `blood_oxygen_screen.dart:63-702` same for SpO₂ (`latestSpo2`, `insertSpo2`, cloud guard).
- `hrv_screen.dart:63-774` 48 half-hour slots, `latestHrv`, `insertHrv`, cloud guard, hero `latest`.
- `home_screen.dart:334-553` `latestHrvHome/latestSpo2Home` heroes (`latest>avg`), MiniCards, `FigmaExpandedCard` HR uses `latest`.

### Loop `MeasurementLoopManager.kt:229-327`
- Comment lower-median rationale, `|Δ|≤12` (was 8), `sorted[(size-1)/2]` (was `size/2` upper-median `87` for `[65,87]`), timeout same.

## Data Flow (after)
```
Ring interval blob (QRing) ──LargeDataHandler(22s)──► BlePlugin syncInterval*Detail ──insert*At──► Room ──safeRefreshDailySummary──► daily_vital_summary
Phone poll (MeasurementLoopManager adaptive FAST 180s / SLOW 900s) ──manualMode*──► same path (source=auto_cycle)
Manual tap (readHeartRate/manualMode) ──insert*──► same path (source=manual) ──getTodaySummary──► Provider latest+avg ──watch rebuild──► Home/Detail hero=latest (isStale pill if latest==0)
SupabaseSyncManager 6h ──unsyncedBatch──► user_*_readings + recompute daily user_hr/spo2/hrv avg
```

## Completion Table

| # | Item | Location | Status | Verified |
|---|------|----------|--------|----------|
| 1 | HR `latestHr` + `isLatestHrStale` + `updateHrLatest` | `lib/providers/ble_provider.dart:44,188,273,1081` | ✅ Completed | `flutter analyze` No issues |
| 2 | SpO₂ `latestSpo2` | `ble_provider:53,188,1147` | ✅ Completed | 123 tests (was 80 at completion) |
| 3 | HRV `latestHrv` + `todayMin/MaxHrv` | `ble_provider:68,188,1379` | ✅ Completed |  |
| 4 | `Health Connect` HRV push | `ble_provider:545,579` `tryWriteHrv` | ✅ Completed |  |
| 5 | `insertHeartRateAt/Spo2At/HrvAt/TemperatureAt` | `ReadingRepository.kt:67-151` | ✅ Completed |  |
| 6 | `BlePlugin` dispatch + `syncInterval*Detail` inflate `dayStart+idx*interval*60k+30k` dedup | `BlePlugin.kt:449,993-1151,2819` | ✅ Completed | `gradle BUILD SUCCESSFUL` |
| 7 | `BleService` bridges | `ble_service.dart:663` | ✅ Completed |  |
| 8 | Detail hero `latest>avg` + stale pill + no fake bucket + cloud only when `!hasData` | `heart_rate_screen:63, blood_oxygen_screen:63, hrv_screen:63` `home_screen:334` | ✅ Completed | Manual QA |
| 9 | `MeasurementLoopManager` `abs≤12` lower-median `[(size-1)/2]` | `MeasurementLoopManager.kt:229` | ✅ Completed |  |
| 10 | Pressure interval LargeData | — (SDK no `IntervalPressureEntity`) | ⬜ Not Needed | Acceptable poll-only |

## Not Completed / Deferred

| Item | Reason |
|------|--------|
| Pressure interval blob | SDK lacks entity — stay poll-only, revisit if firmware adds |
| Temperature `IntervalTemperatureEntity$IntervalTemperature` nested float vs `array` dual path | Needs field test with ring premium `supportTemperatureBoth` |

## Acceptance
- `flutter analyze --no-pub` → No issues (`39.7s`)
- `flutter test` → 123 passed (was 80 at completion 2026-08-26)
- `gradle :app:compileDebugKotlin` → BUILD SUCCESSFUL
- Hero shows `latest` (e.g., `65`) while `AVG` pill stays `87` → not frozen; interval backlog after 2h disconnected → `12` backfilled points hourly chart populates.
