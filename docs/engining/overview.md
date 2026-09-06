# Engining — Frontend Business Logic Extraction

> Goal: no business logic lives in `StatefulWidget`/`build()`. All scoring, thresholds, date math, aggregations, parsers live in pure/service engines under `lib/utils/` and `lib/services/health_engine/`. UI only does layout, navigation, theming per `DESIGN.md` and `CLAUDE.md:4`.

## Why

Audit found **37 duplication clusters (~210 blocks, ~620 line-groups)** across 7 health screens:

* `sleep_screen.dart:326-437` `_parseSegments` 112 lines, `steps_screen.dart:231-288` `_parseIntervalJson` obfuscated keys, `temperature_screen.dart:547-605` `_parseTempReadings` — each screen reimplements protocol parsing.
* Hourly 24/48/96 bucketing `sums/counts → round` 10 sites; trend `reduce(min/max)` 12 sites; `_fmt yyyy-MM-dd` 16 sites; `_hourLabel` 4 sites; `dayStartMs` 6 sites; manual flow 40 lines ×6.
* Activity/sleep formulas, HRV/stress/BP/temp/SpO2 brackets duplicated via thin wrappers.

Leak causes drift (sleep `85/70/55` vs `80/60/40` bug), hard-to-test `State` methods, and Supabase `_stressLabel 40/60/80` diverging from `HealthEngine`.

## What is Engine vs UI

| Engine (pure/service) | UI (stays) |
|---|---|
| `DateKeys.fmt/isToday/sameDay/dayIndex/isFuture`, `Formatters.sleepDuration/hourLabel/trendLabels`, `HourlyAggregator`, `TrendMath`, `ScrubHelper`, `SleepEngine.parseSegments`, `ActivityEngine.parseIntervalJson`, `TempEngine.parseReadings`, `CycleEngine.phaseName`, `HealthEngine.calc*/assess*`, `HistoryService` | `AppTypography.inter`, `AppTheme.glassCard/border blur28 radius20`, `BlurOrb`, `GlassCard`/`MetricStatCard`/`ScrubbableChart`, `CustomPainter` canvas, `DateScrollRow` scroll offset, `RealTimeCard` glass CTA, `Navigator`/`SnackBar`/`HapticFeedback` |

Fall prediction `lib/services/fall_prediction/*` already isolated and stays separate — it will eventually consume `HealthEngine` thresholds as inputs.

## Two Flavors (per requirement "do both")

* **Pure engines** — `lib/utils/*.dart`, `lib/services/health_engine/*_engine.dart` — functions `Inputs → Outputs`, no `BuildContext`/`SharedPreferences`/`Supabase`. Fully unit-tested.
* **Service-engines** — same pure core wrapped by convenience that internally calls `HealthConfig`/`GoalPrefs`/`SupabaseService`/`LocalVitalsService`. UI calls service flavor for brevity; tests call pure flavor with injected values. Example: `ActivityEngine.calcScorePure(steps,goals)` vs `HealthEngine.calcActivityScoreWithGoals` service.

## Structure

```
lib/utils/date_keys.dart              # pure date predicates
      /formatters.dart                # pure string formatters
      /hourly_aggregator.dart         # 24/48/96 bucketing
      /trend_math.dart                # avg/min/max, last7Bars
      /scrub_helper.dart              # initialIndex, indexFromDx

lib/services/health_engine/
  health_engine.dart                  # facade (already) — now delegates to sub-engines
  health_config.dart                  # thresholds remote JSONB
  models.dart
  sleep_engine.dart                   # PRIORITY — parseSleepData/parseSegments/efficiency/syntheticSegs
  activity_engine.dart                # parseIntervalJson/normalizeCalories/distributeSteps
  temperature_engine.dart             # parseTempReadings
  cycle_engine.dart                   # phaseName + flex ratios

lib/services/history_service.dart     # cache-then-cloud generic (future phase)
lib/services/measurement_flow.dart    # manual flow (future phase)

lib/utils/bp_staging.dart             # aliased to HealthEngine after transfer
```

## Docs in this folder

* `architecture.md` — layering & injection
* `sleep_engine.md` — sleep parsing (priority)
* `date_keys_and_formatters.md`
* `hourly_aggregator.md`
* `activity_engine.md`
* `bp_staging.md` — alias plan
* `migration_plan.md` — phased rollout
