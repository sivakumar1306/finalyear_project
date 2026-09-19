# Architecture — Engines Layer

## Layering

```
UI (StatefulWidget, build)                # glass, nav, SnackBar, CustomPainter — DESIGN.md
  ↓ calls
Service-engines (HealthEngine, ActivityEngine service)  # GoalPrefs/HealthConfig/Supabase/LocalVitalsService inside
  ↓ delegates to
Pure engines (SleepEngine, HourlyAggregator, DateKeys, TrendMath)  # inputs→outputs, no I/O
  ↓ reads
Config (HealthConfig.kDefaultConfig + health_engine_config.config JSONB)  # thresholds/advice/ranges
```

*UI never computes thresholds, scores, date keys, or bucket math directly.* It resolves `BuildContext` values (`latestHr`, `todayAvgHr`) then asks engine `assessHeartRate(bpm).label`.

## Pure vs Service

* **Pure**: `SleepEngine.parseSegments(rawList, st, et)`, `HourlyAggregator.aggregate(readings, slots)`, `DateKeys.fmt(date)`, `ActivityEngine.parseIntervalJson(json)`, `TrendMath.avg(values)`. Takes primitives, returns primitives. Test with `flutter test` without mocks.
* **Service**: `HealthEngine.calcActivityScoreWithGoals(steps,goals)` internally `GoalPrefs.load()` or `HealthConfig.intThreshold`; `SleepEngine.parseSleepData(jsonStr, {date})` that also does `HealthEngine.calcSleepScore`. UI prefers service for one-liner.

Both flavors coexist per requirement. Example:

```dart
// Pure — test
final score = SleepEngine.calcScore(25200, 5040, 3780, 1000, 29800);
// Service — UI
final score = HealthEngine.instance.calcSleepScore(total: total, deep: deep, rem: rem, st: st, et: et);
```

## Injection

Pure engines take thresholds as params (`excellent: HealthConfig.intThreshold('sleep','excellent',80)`), so tests can pass 80 vs 85 without Supabase. Service engines read `HealthConfig.current` internally.

No `BuildContext` leaks into engines. `BleProvider` remains state orchestration (holds `todayAvgHr` etc.) but its `_maybeAlert` thresholds now delegate to `HealthEngine` severity checks.

## Fall Prediction

`lib/services/fall_prediction/*` stays separate. It will read `HealthEngine` thresholds as inputs (future) but not be merged.

## Alias Strategy

`lib/utils/bp_staging.dart` after transfer becomes:

```dart
BpStage classifyBp(int sbp,int dbp) {
  final a = HealthEngine.instance.assessBloodPressure(sbp,dbp);
  return switch(a.label) { 'Normal'=>BpStage.normal, 'Elevated'=>BpStage.elevated, 'Stage 1'=>BpStage.stage1, 'Stage 2'=>BpStage.stage2, _=>BpStage.noData };
}
```

Keeps backward compat for 3 importers while single truth is `HealthConfig`.

## Deletion of Wrappers

After transfer, delete thin free funcs `lib/screens/health/*: _hrvLabel/_hrvColor`, `_stressLabel`, `_tempLabel`, `home_screen: _spo2Status/_hrStatus/_hrvStatus/_sleepStatus`, `home_card_shared: stressStatus` etc. — call sites use `HealthEngine.instance.assess*(v).label` directly.

## Testing

Each engine has `test/*_test.dart` with edge cases (sleep new-proto `d>1e9` timestamp vs `d<500→*60`, steps `d/f/e/g` obfuscated keys, midnight `23:58→00:02` tolerance).
