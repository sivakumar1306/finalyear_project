# 05 — Measurement Log Screen (Last 3 Days, Grouped, Failed Filter)

## Schema (additive Room 7→8, local-only)

* `ReadingEntities.kt:197` `MeasurementAttemptEntity(id, vital HEART_RATE|..., source auto_cycle|manual|interval_sync, cycleId FK, startedAt, endedAt, status success|failed|timeout|yielded|rejected|aborted_disconnect|skipped_workout|sdk_guard_open|skipped_disabled, error, valueJson)`.
* `ReadingDaos.kt:21` `MeasurementAttemptDao(attemptsBetween, failedBetween, attemptsForCycle, cyclesWithCountsBetween, purgeOlderThan)`.
* `QRingDatabase.kt:9,29` add entity, bump 7→8.
* `ReadingRepository.kt:35` `startAttempt/finishAttempt/...` + purge 30d.

## Instrument

* `MeasurementLoopManager:59 walkSequence`: `startAttempt(vital, auto_cycle, cycleId)` before `measure`; exits `finishAttempt(...)` for disabled/disconnect/workout/yielded/timeout/rejected/exception. `BlePlugin:2953` phantom cycles: `id>0→success else rejected`.

## Bridge + Dart (landed subset)

* `BlePlugin` has `getMeasurementAttempts` + `getFailedMeasurementAttempts` (dispatch only — `getMeasurementLogGrouped` was proposed but never added); `ble_service.dart` wrappers read them directly (no `measurement_log_service.dart` exists — parsing lives in the screen).

## UI `health/measurement_log_screen.dart` (landed, different wiring than proposed)

* `AppBar GlassBackButton`, `AppTheme.bg`, `AppTypography`, `FooterSpacer`. Opened per-vital from each health detail screen's History entry (`_openMeasurementLog` → `MeasurementLogScreen`, filter `All | Failed only` + last-3-days window), plus a flag-gated settings entry (`settings_screen.dart:440`, `AppConfig.includeMeasurementLog`). There is **no** `/measurement-log` named route in `app.dart` and no History card in `health_settings_screen`.

## Sync

Local-only, no `SupabaseSyncManager` push. Burst >3/hr → `IncidentService.reportUnhandled(source:measurement_loop)`.
