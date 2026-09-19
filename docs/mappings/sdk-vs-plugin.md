# SDK ↔ Plugin ↔ Dart mapping

Source of truth, last verified 2026-09-19 from:
- AAR: `android/app/libs/qring_sdk_1.0.0.55.aar` (`javap BleOperateManager`)
- Plugin: `android/.../BlePlugin.kt` (method-channel cases + `BleOperateManager.getInstance()` calls)
- Dart: `lib/services/ble_service.dart` (incl. `fetchRingHistory` dispatcher)

Ring history buffer: `deviceHealthHistoryMaxDayIndex() == 6` → dayIndex `0..6`
(today … 6 days ago). "View all history from the ring" = range fetch `0..6`.

Legend: ✅ mapped end-to-end · 🔶 wired to UI history backfill · ⚠️ partial ·
❌ SDK-only (no channel/Dart)

## History families (getToday / getSingle(day) / getRange(start,count))

| Vital | SDK today | SDK single | SDK range | Channel | Dart | UI backfill | Status |
|---|---|---|---|---|---|---|---|
| Steps | `getTodayStepDetail` | `getStepDetail` | `getStepDetails` | `getStepsToday`/`getTodaySteps`/`getSteps`/`getStepsList` | ✅ all + `fetchRingHistory('steps')` | 🔶 `steps_screen._pullRingHistory` | ✅ |
| Heart rate | `getTodayHeartRate` | `getHeartRate` | `getHeartRates` | `getTodayHeartRate`/`getHeartRate`/`getHeartRates` | ✅ all + dispatcher | 🔶 `heart_rate_screen._pullRingHistory` | ✅ |
| Blood pressure | `getTodayBloodPressure` | `getBloodPressure` | `getBloodPressures` | all three | ✅ all + dispatcher | 🔶 `blood_pressure_screen._pullRingHistory` | ✅ |
| Pressure (stress) | `getTodayPressure` | `getPressure` | `getPressures` | `getTodayPressure`/`getPressure`/`getPressureList` | ✅ all + dispatcher | 🔶 `stress_screen._pullRingHistory` | ✅ |
| HRV | `getTodayHrv` | `getHrv` | `getHrvs` | `getTodayHrv`/`getHrv`/`getHrvList` | ✅ all + dispatcher | 🔶 `hrv_screen._pullRingHistory` | ✅ |
| Blood oxygen | `getTodayBloodOxygen` | `getBloodOxygen` | `getBloodOxygens` | all three | ✅ all + dispatcher | 🔶 `blood_oxygen_screen._pullRingHistory` | ✅ |
| Temperature | `getTodayTemperature` | `getTemperature` | `getTemperatures` | all three | ✅ all + dispatcher | ❌ blocked (see below) | ⚠️ |
| Sleep | `getTodaySleep` | `getSleep` | `getSleeps` | `getTodaySleep`/`getSleep`/`getSleepList` | ✅ all + dispatcher | 🔶 `sleep_screen._loadHistory` (pre-existing) | ✅ |
| Sport | `getTodaySport` | `getSport` | `getSports` | `getTodaySport`/`getSport`/`getSports` (+ legacy `getSportRecords`/`syncSportRecords` via `SportPlusHandle`) | ✅ all + `fetchRingHistory('sport')` | 🔶 `workouts_screen._pullRingSports` auto-merge | ✅ |
| Emotion | `getTodayEmotion` | `getEmotion` | `getEmotions` | — | — | — | ❌ no consumer in app |
| Manual HR | `getTodayManualHeartRate` | `getManualHeartRate` | `getManualHeartRates` | `getTodayManualHeartRate`/`syncManualHeartRate` only | ⚠️ single/range missing | — | ⚠️ |
| Manual SpO₂ | `getTodayManualBloodOxygen` | `getManualBloodOxygen` | `getManualBloodOxygens` | — | — | — | ❌ |
| 3-point temp | `getTodayThreeTemperature` | `getThreeTemperature` | `getThreeTemperatures` | — (`manualTemperature_POC` only) | — | — | ❌ device-dependent |
| RRI | `getRriBlockList`/`getRriBlock` | `getRriHistory` | — | — | — | — | ❌ no consumer in app |

## Verified range-payload contracts (gson, from AAR field lists)

All range APIs return `[{"dayIndex": N, "data": {…same shape as single-day…}}]`
(`day_index` snake variant also accepted Dart-side).

| Vital | `data` shape | Keys consumed |
|---|---|---|
| Steps | `List<BleStepDetails>` (same list `getStepDetail` returns) | `d/f/e/g` via `ActivityEngine.parseIntervalJson` |
| Heart rate | `ReadHeartRateRsp` map | `array`, fallback `mHeartRateArray` (signed→unsigned), keep 30–220 |
| Blood pressure | `List<BlePressure>` | `{time, sbp, dbp}`; `time` s-or-ms auto-normalized by magnitude; keep 70–250 / 40–150 |
| Pressure | `PressureRsp` map | `pressureArray` bytes (unsigned, drop 0xFF, clamp 0–100) |
| HRV | `HRVRsp` map | `d`, fallback `pressureArray` (unsigned, drop 0xFF); NOTE: provider `_parseAndSaveHrv` reads only `d`, which raw SDK gson never emits — today-HRV ring path was silently dead, history hook covers both keys |
| Blood oxygen | `BloodOxygenEntity` map | `array` + `minArray` + `maxArray`, keep 1–100 |
| Temperature | `IntervalTemperatureEntity` map | `{array, values[{value1..3}], interval}` — semantics unverified, NOT consumed |
| Sleep | `SleepDisplay` map | via `SleepEngine.parseSleepData` (pre-existing) |
| Sport | `SportPlusEntity` map | `{mSportType→name, mStartTime(s), mDuration(s), mDistance(m), mCalories, mRateAvg, steps}` → history row + `insertWorkout`; `TYPE_APP_*` deduped by start second |

## Manual-measure triggers (mapped ✅)

`manualModeHeart`, `manualModeBP`, `manualModeSpO2`, `manualModeHrv`,
`manualModePressure`, `manualTemperature`, `manualThreeTemperature`(POC),
`readHeartRate`, `insertHeartRate`, `insertHrv`, `insertSpo2`,
`insertTemperature`, `cancelHeartRate`.

## Settings (mapped ✅)

`get/setHeartRateSetting`, `get/setHrvSetting`, `get/setBloodOxygenSetting`,
`get/setBloodPressureSetting`, `get/setPressureSetting`,
`get/setTemperatureSetting`, `get/setTargetAndProfile`,
`getHealthSettings`/`setHealthSettings`, `getDeviceSupport`,
`getAdvancedSettings`, `read/setRriAutoMeasure`, `read/setEmotionAutoMeasure`.

## Connection / device (mapped ✅)

`connect`, `disconnect`, `isConnected`, `connectionState`, `startScan`,
`bleCreateBond`, `findDevice`, `getBattery`, `getFirmwareVersion`,
`setTime`, `startOta`.

## Deliberately unmapped (no app consumer — do not add without a feature)

- Emotion family, RRI family, Manual-SpO₂ family, 3-point-temp family,
  `getSports` range (sport uses the `SportPlusHandle` sync path),
  `ManualHR` single/range, `oneClickMeasurement`, `startOneKey`/`endOneKey`
  direct channels, `classicBluetooth*` / RTK-SPP APIs.
- Temperature history backfill is blocked, not unmapped: needs one live-ring
  `getTemperatureList` sample to pin `array` vs `values[]` semantics.
