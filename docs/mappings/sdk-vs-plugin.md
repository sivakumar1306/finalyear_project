# SDK ↔ Plugin ↔ Dart mapping

Source of truth, last verified 2026-09-19 from:
- AAR: `android/app/libs/qring_sdk_1.0.0.55.aar` (`javap BleOperateManager`)
- Plugin: `android/.../BlePlugin.kt` (method-channel cases + `BleOperateManager.getInstance()` calls)
- Dart: `lib/services/ble_service.dart` (incl. `fetchRingHistory` dispatcher)

Ring history buffer: `dayIndex 0..6` (today … 6 days ago), bounded Dart-side by
`kRingHistoryMaxDays = 7` (`ble_service.dart`).
"View all history from the ring" = range fetch `0..6`.

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
| Sport GPS | `SportLocation{mRateReal}` only — no lat/lng fields exist | n/a (HR samples, not coordinates) | — | — | Ring GPS impossible; phone GPS recorded during manual workouts → `user_workouts.locations` → `gps_trace_screen` | ✅ (phone-side) |
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
| HRV | `HRVRsp` map | `d`, fallback `pressureArray` (unsigned, drop 0xFF); NOTE: the *today* path (`BleProvider._parseAndSaveHrv`) reads only `d`, so it stays empty when raw SDK gson emits only `pressureArray` — the *history* hook (`hrv_screen._pullRingHistory`) covers both keys |
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
  `ManualHR` single/range, `oneClickMeasurement`, `startOneKey`/`endOneKey`
  direct channels, `classicBluetooth*` / RTK-SPP APIs.
- Temperature history backfill is blocked, not unmapped: needs one live-ring
  `getTemperatureList` sample to pin `array` vs `values[]` semantics.

## Fall / motion (no SDK surface — phone-only by design)

No continuous accelerometer/gyroscope API exists in the shipped SDK, so there
is nothing to map here. Fall detection is phone-side: `FallMotionDetector`
(50 Hz phone accel/gyro while armed) → Room `fall_event` → Dart via
`getFallEvents`; monitoring state via `getMotionSnapshot`. Do not add
ring-IMU channels without a new SDK that streams them.
