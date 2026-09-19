# Migration Plan — From Frontend State to Engines

## Order (priority per requirement: SleepEngine first)

1. **Docs** (done) — `docs/engining/*.md`
2. **Pure utils** — `utils/date_keys.dart`, `formatters.dart`, `hourly_aggregator.dart`, `trend_math.dart`, `scrub_helper.dart` — low-risk, no behavior change, replaces 16 `_fmt`, 7 `trendXLabels`, 10 bucketings.
3. **SleepEngine** (PRIORITY) — `sleep_screen.dart:216-437` move, add `test/sleep_engine_test.dart` (new-proto `d>1e9` vs duration, old `sleepStart`, `cursor` shift, `total<=0` fallback).
4. **Activity/Temp/Cycle** — `activity_engine.dart`, `temperature_engine.dart`, `cycle_engine.dart` (phaseName flex).
5. **BP alias + wrappers delete + BleProvider alerts → HealthEngine** — `ble_provider.dart:1190-1464` `_maybeAlert` thresholds use `HealthEngine severity`, `supabase_service.dart:363` `_stressLabel` → engine.
6. **HistoryService & MeasurementFlow** — generic `getDaySeries/getTrendSeries` + manual `runManual` to replace 21 cache-then-cloud and 6×40-line manual flows; collapse `RealTimeBPCard` 102-line dup etc. to `RealTimeCard`.

## Each PR Checklist

* Replace `State` method with engine call, keep `setState` + `IncidentService` catch in widget.
* Delete old method + import engine.
* Update callers that constructed `GoalTargets(10000...)` fallback to `DateKeys`/`GoalPrefs.defaults`.
* `dart analyze`, `flutter test` (add engine tests, suite now 123).

## Rollback

Engines are additive; original widget method kept as deprecated shim for one PR if needed. `bp_staging.dart` alias ensures 3 importers not broken.

## DESIGN.md Compliance

* No new glass/radius/blur/colors; `HealthEngine._colorForKey` already maps `success/danger/amber` to `AppTheme`.
* `CLAUDE.md:4` reuse `GlassCard`/`MetricStatCard`/`ScrubbableChart` — engines never import `material.dart` (except `HealthEngine` which already imports for `Color` — `models.dart` will split `HealthSeverity` pure).
