# 05 — Measurement Log Screen (Last 3 Days, Grouped, Failed Filter)

## Schema (additive Room 7→8, local-only)

* `ReadingEntities.kt:197` `MeasurementAttemptEntity(id, vital HEART_RATE|..., source auto_cycle|manual|interval_sync, cycleId FK, startedAt, endedAt, status success|failed|timeout|yielded|rejected|aborted_disconnect|skipped_workout|sdk_guard_open|skipped_disabled, error, valueJson)`.
* `ReadingDaos.kt:21` `MeasurementAttemptDao(attemptsBetween, failedBetween, attemptsForCycle, cyclesWithCountsBetween, purgeOlderThan)`.
* `QRingDatabase.kt:9,29` add entity, bump 7→8.
* `ReadingRepository.kt:35` `startAttempt/finishAttempt/...` + purge 30d.

## Instrument

* `MeasurementLoopManager:59 walkSequence`: `startAttempt(vital, auto_cycle, cycleId)` before `measure`; exits `finishAttempt(...)` for disabled/disconnect/workout/yielded/timeout/rejected/exception. `BlePlugin:2953` phantom cycles: `id>0→success else rejected`.

## Bridge + Dart

* `BlePlugin:275` add `getMeasurementAttempts`, `getFailedMeasurementAttempts`, `getMeasurementLogGrouped` (Gson like `getMeasurementCycleHistory:3384`); `ble_service.dart:759` wrappers; new `measurement_log_service.dart` grouped parser + `isFailed`.

## UI `settings/measurement_log_screen.dart`

* `AppBar GlassBackButton`, `AppTheme.bg`, `AppTypography`, `FooterSpacer`. Filter `All | Failed only` + `Last 3 days` (`from=now-2d 00:00`). `FutureBuilder<GroupedCycle>` sorted `startedAt DESC`. `GlassCard:13` header `Started–Completed (dur)` + `5/7 success` pill, rows per attempt: vital icon (`hrColor` etc), status chip, duration, error `textSec 11px`. Empty `Icons.history`. `RefreshIndicator`, subscribe `BleService.events newReading`.
* Settings entry `settings_screen:433` after `Measurement Intervals`: `_SettingsRow.arrow(Icons.receipt_long, Measurement Log → /measurement-log)` + `health_settings_screen:538` History card. Route `app.dart:67`.

## Sync

Local-only, no `SupabaseSyncManager` push. Burst >3/hr → `IncidentService.reportUnhandled(source:measurement_loop)`.
