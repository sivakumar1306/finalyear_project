# Health Engine — Overview

> Single Source of Truth for every health determination, band, color, score, range, tip and comment shown anywhere in the app. Fall prediction stays in its own engine (`lib/services/fall_prediction/`).

## Why

Before `HealthEngine` each metric duplicated pure logic inside widgets:

* `lib/screens/home/home_screen.dart:151` `_spo2Status` vs `blood_oxygen_screen.dart:646`
* `lib/screens/health/sleep_screen.dart:765` `_quality` (`85/70/55`) vs `home_screen.dart:192` (`80/60/40`) — caused **Good inside / Excellent on Home** bug
* Activity score `steps/8000*60` duplicated in `home_screen.dart:176` and `steps_screen.dart:554`
* Every `VitalNoteScreen` hard-coded `intro/ranges/tips/didYouKnow` per caller

Drift is invisible to the compiler. `lib/utils/bp_staging.dart:40` was the only metric that was already centralised — the model to follow for every metric.

## What it owns

* **Thresholds** — all numeric bands (`sleep excellent 80`, `hr below 60`, `spo2 normal 95`, `hrv 20/40/60/80`, `stress 40/60/80`, `bp 120/80 130/80 140/90`, `temp 36/37.2/38`, `activity 60/25/15` weights). Stored in one dict (`HealthConfig`) updatable via Supabase.
* **Scores** — `calcSleepScore`, `calcActivityScore` (goal-aware, see `activity.md`).
* **Assessments** — `assessSleep(score) → Assessment{label, color, severity}` etc. Replaces every `static String _xxxStatus`.
* **Advice / literals** — `noteFor(Metric.sleep) → VitalNoteData{title, heading, intro, ranges, tips, didYouKnow}`. Same dict as thresholds, so copy changes ship via Supabase without app update. Detail screens’ existing copy was moved verbatim into the dict.
* **Insights** — trend → headline helpers now delegate to the same BP/stage cut-offs.

## Architecture

```
lib/services/health_engine/
  health_config.dart      // one dict {thresholds, literals, ranges} + Supabase fetch + SharedPrefs cache
  health_engine.dart      // singleton facade `HealthEngine.instance`
  models.dart             // Assessment, VitalNoteData, VitalRangeData, TipData, Severity
docs/health-eng/
  overview.md  (this file)
  thresholds.md
  advice.md
  config.md    // Supabase remote dict contract + migration
  activity.md  // goal-aware scoring
```

UI never stores thresholds. Widgets call:

```dart
final a = HealthEngine.instance.assessSleep(score);
Text(a.label, style: TextStyle(color: a.color));
```

```dart
final note = HealthEngine.instance.noteFor(HealthMetric.sleep);
Navigator.push(..., VitalNoteScreen.fromData(note));
```

## Single dict contract

One JSONB row `health_engine_config.config` (`supabase/migrations/20260905000000_health_engine_config.sql`). Keys:

```json
{
  "version": 1,
  "thresholds": { "sleep": {"excellent":80,"good":60,"fair":40}, "hr": {...}, ... },
  "advice": { "sleep": {"title":"Sleep","heading":"About Sleep","intro":"...","didYouKnow":"...","tips":[...]}, ... },
  "ranges": { "sleep": [{"label":"Poor","range":"0–39","color":"danger"}, ...], ... }
}
```

`HealthConfig` deep-merges remote over `kDefaultConfig` so missing keys fall back, never crash offline. See `config.md`.

## Non-goals

* Fall prediction — stays in `lib/services/fall_prediction/fall_prediction_engine.dart`.
* Color tokens — still `AppTheme.*` (`DESIGN.md`), engine only *references* them via `colorKey → AppTheme` map.
* DB schema for vitals — unchanged.

## How to change a band or copy

1. Edit Supabase `health_engine_config` row (`config` JSONB) or `health_config.dart:kDefaultConfig` for bundled fallback.
2. No screen file needs editing.
3. Add edge test in `test/health_engine_test.dart` (e.g. score 79→Good, 80→Excellent).
