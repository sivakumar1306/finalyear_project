# 07 — Health Connector Spike (health 13.3.2 → health_connector 3.10.0)

> Spike evaluated 2026-09-02, **reverted / never merged**: `pubspec.yaml` still has `health: ^13.3.2` only (zero `health_connector` hits in `pubspec.yaml`/`pubspec.lock`; `health_connect_service.dart` still `import 'package:health/health.dart'` + `Health()`), and `android/app/build.gradle.kts` has no `compileSdkExtension`. The analysis below is kept for reference.

## Why spike?
* `health 13.3.2` is latest stable (2 weeks old) but still `android/build.gradle:25 kotlin-android` → `flutter build` fails if `android.builtInKotlin=true` (AGP 9). `health_connector 3.10.0` changelog: `Support built-in Kotlin` + `health_connector_hc_android` built-in, `compileSdkExtension 19` for Health Connect 1.2.0-alpha03.
* Keeping `health` blocks `builtInKotlin=true` for entire app. Spike evaluates port cost vs waiting.

## What was evaluated (reverted — see header)
* ~~`pubspec.yaml:26` added `health_connector: ^3.10.0` (kept `health: ^13.3.2` for fallback) — `flutter pub get` → 5 new deps, build still `√ Built 66.8MB` with health.~~ Never merged; no trace in `pubspec.*`.
* ~~`android/app/build.gradle.kts:3` added `compileSdkExtension = 19` (required for health_connector 3.9.0 / Health Connect 1.2.0-alpha03)~~ — not present in the file.
* **Bulk permission + sleep sync already fixed via `health`** (`health_connect_service.dart:417`, `health_connect_screen.dart:62`):
  - `_connect()` now `requestAuthorization(HealthSyncType.values.toSet())` — one sheet for all 8 types.
  - `_toggle()` now `requestAuthorization({type})` granular, reverts if denied.
  - `tryWriteSleep` dayKey local `YYYY-MM-DD`, `fetchToday` now sums sleep via `dateTo-dateFrom` minutes and `totalSleep = asleep ?: deep+light+rem`.

## API gap (spike analysis, not yet ported)
`health` vs `health_connector` are not drop-in:

| `health` (old) | `health_connector` (new) |
|---|---|
| `Health().configure()` | `HealthConnector.create()` |
| `isHealthConnectAvailable()` | `HealthConnector.getHealthPlatformStatus() == available` |
| `installHealthConnect()` | `HealthConnector.launchHealthAppPageInAppStore()` |
| `hasPermissions(all, READ_WRITE)` | `connector.getGrantedPermissions()` subset check |
| `requestAuthorization(all, READ_WRITE)` + `requestHealthDataHistoryAuthorization` | `connector.requestPermissions([... HealthDataType.steps.readPermission, writePermission, HealthPlatformFeature.readHealthDataHistory.permission, etc])` |
| `writeHealthData(value, HEART_RATE, start, end)` | `connector.writeRecord(HeartRateRecord(beatsPerMinute: Number(bpm), ...))` |
| `writeBloodOxygen` / `writeBloodPressure` | `OxygenSaturationRecord(percentage: Percentage(pct))`, `BloodPressureRecord(systolic: Pressure(mmHg), diastolic: ...)` |
| `getTotalStepsInInterval` | `HealthDataType.steps.aggregateSum(start, end)` |
| `getHealthDataFromTypes` | `connector.readRecords(HealthDataType.steps.readInTimeRange(...))` + pagination |
| Sleep: `SLEEP_LIGHT/DEEP/REM/AWAKE` with `value 0` | `SleepSessionRecord` + `SleepStageRecord(stage: SleepStageType.lightDeepRemAwake, ...)` |

Port requires rewriting `health_connect_service.dart:119` entire `HealthSyncType → Permission` mapping + all `tryWrite*` (`StepsRecord`, `HeartRateRecord`, `HeartRateVariabilityRmssdRecord`, `OxygenSaturationRecord`, `SleepStageRecord`, `BloodPressureRecord`, `BodyTemperatureRecord`, `MenstrualFlowRecord`) + `fetchToday` via `readRecords`/`aggregate` + `fetchHistoricalBaselines`.

## Recommendation
* Keep `health` + `health_connector` side-by-side for one sprint. Implement `health_connect_service_v2.dart` using `health_connector` for one metric (e.g., Steps) behind a feature flag, verify on API 26 device with Health Connect app.
* If spike passes, remove `health: ^13.3.2` from `pubspec.yaml`, delete legacy `health` code, then flip `android.builtInKotlin=true` + remove `id("org.jetbrains.kotlin.android")` from `android/app/build.gradle.kts:6` per `02` — this will finally clear `health` from KGP warning list.
* Otherwise keep `health` and tolerate `builtInKotlin=false` until upstream `health` publishes built-in Kotlin build (watch https://pub.dev/packages/health/changelog).

## Tracker update
* `speech_to_text: 7.0.0 → 7.1.0` bumped (`pubspec.yaml:22`) — still warns KGP (7.1.0 changelog only fixed deprecated build settings, not AGP 9). No newer.
* `firebase_core 4.14.0` latest already migrated native to Kotlin per pub.dev, warning likely from transitive `_flutterfire_internals` — keep as is, no fork.
* `health 13.3.2` latest, still KGP — spike above is path to fix.
