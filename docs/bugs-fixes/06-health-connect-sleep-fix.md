# 06 — Health Connect Fix (Bulk Permissions + Sleep Sync)

> Date: 2026-09-02 | Flutter 3.47.2 | `health: ^13.3.2` | Service `lib/services/health_connect_service.dart` | Screen `lib/screens/settings/health_connect_screen.dart`

## Diagnosis

### 1. Permission flow was per-type, not bulk
`HealthConnectScreen._connect()` called `requestAuthorization(_enabled)` where `_enabled` defaults to `{steps, heartRate}` (from `loadEnabledTypes`). User had to tap Connect, grant 2 types, toggle another type, grant again — 4 separate Health Connect sheets.

**Requirement:** “When it is enabled, it asks for all the permissions in one go, and after that granular changes can happen.”

### 2. Sleep sync broken — two bugs
* **Write:** `tryWriteSleep` used `dayKey = millis ~/ 86400000` (UTC days) for `clientRecordId` → duplicates across local days; `end` fallback set to `day+1 00:00` not `day+1 07:00`.
* **Read:** `fetchToday` summed sleep via `_numValue(p)` → always `0` because Health Connect stores sleep as interval duration (`dateTo - dateFrom`), not numeric value. `sleepMinutes` was `sum(SLEEP_ASLEEP)` only → `null` when data was written as stages `LIGHT/DEEP/REM/AWAKE`.

Silently failed: write succeeded but read returned `null` → UI showed “No sleep”.

### 3. Plugin updates
`flutter pub outdated` after `01` upgrade: `direct: all up-to-date`. `health 13.3.2` is latest on pub.dev (checked `https://pub.dev/packages/health/versions` — no 13.3.3 yet). `firebase_core 4.14.0` and `speech_to_text 7.0.0` also latest but still apply `kotlin-android` (expected until upstream migrates to built-in Kotlin). Keeps `android.builtInKotlin=false` per `02` until tracker 03 is green.

## Fix

### A. `lib/screens/settings/health_connect_screen.dart`
* `_connect()` → requests **all** `HealthSyncType.values.toSet()` at once:
  ```dart
  final allTypes = HealthSyncType.values.toSet();
  final ok = await _service.requestAuthorization(allTypes);
  if (ok) { _enabled = allTypes; await _service.saveEnabledTypes(_enabled); }
  ```
  Shows `Health Connect connected — all permissions granted.` — granular switches become on/off without new sheet if already granted.
* `_toggle()` → when enabling a type not yet granted, requests **only that single type** `requestAuthorization({type})`. If denied, reverts toggle and saves. Turning off just refreshes; no sheet.

### B. `lib/services/health_connect_service.dart`
* `tryWriteSleep`:
  - `dayKey` → local date string `${sleepTime.year}-${mm}-${dd}` for deterministic replace.
  - `end` fallback: `DateTime(sleepTime.year, month, day+1, wakeHour, wakeMinute)` then `+1 day` fallback — handles overnight 23:00→07:00 correctly.
* `fetchToday`:
  - `sumMinutes` now detects `SLEEP_*` and sums `p.dateTo.difference(p.dateFrom).inMinutes` instead of `_numValue`.
  - Computes `asleepM, deepM, lightM, remM, awakeM, inBedM` then `totalSleep = asleep !=0 ? asleep : deep+light+rem ?: inBed`.
  - Returns `sleepMinutes: totalSleep !=0 ? totalSleep : null` and stage minutes nullable — fixes read of stage-written sleep.

### Verification
* `flutter analyze` → 2 info only (`sleep_screen curly_braces`)
* `flutter build appbundle --release` → `√ Built 66.8MB` (no new warnings; still `firebase_core, health, speech_to_text` apply KGP — tracked in `03`)
* Manual: Connect Health Connect once → system sheet lists all 8 types (Steps, Heart Rate, HRV, SpO2, Sleep, BP, Temperature, Menstruation) → grant → all switches flip on. Toggle Sleep off/on → no extra sheet if already granted.

## Remaining
* Keep `android.builtInKotlin=false` until `health` publishes built-in Kotlin build (watch https://pub.dev/packages/health/changelog). Then set `true` + remove `org.jetbrains.kotlin.android` from `android/app/build.gradle.kts:6` per `02`.
