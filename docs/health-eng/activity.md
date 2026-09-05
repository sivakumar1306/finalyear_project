# Activity — Goal-Aware Scoring

Activity Score was previously hard-coded as

```
steps/8000*60 + calories/250*25 + distanceM/5000*15
```

in two places (`lib/screens/home/home_screen.dart:176` and `lib/screens/health/steps_screen.dart:554`). It ignored the user’s own targets from Goal Setting (`GoalPrefs`) and diverged from their configured `steps/calories/distanceKm`. It is now owned by `HealthEngine` and goal-aware.

## Formula (Weights fixed, denoms from GoalPrefs)

Weights are product-fixed (can be tuned via config but defaults stable):

```
stepsW = 60  (config thresholds.activity.stepsWeight)
calW   = 25
distW  = 15   // stepsW+calW+distW == 100
```

Denominators at runtime:

```
goalSteps = GoalPrefs.load().steps        // default 10000
goalCals  = GoalPrefs.load().calories     // default 1000
goalDistM = GoalPrefs.load().distanceKm * 1000  // default 5.0*1000
-- fallback if GoalPrefs empty: config thresholds.activity.stepsDenom etc.
```

Score:

```
s = (steps / goalSteps * stepsW).clamp(0, stepsW)
c = (cals  / goalCals  * calW  ).clamp(0, calW)
d = (distM / goalDistM * distW ).clamp(0, distW)
score = (s + c + d).round().clamp(0,100)
```

This preserves the old “full credit at X” semantics but X is now the user’s goal, not a magic 8000/250/5km.

* Example: user sets Steps 12 000, Calories 600, Distance 8 km → 12 000 steps = 60 pts, 300 cals = 12 pts (300/600*25), 6 km = 11 pts (6000/8000*15) → 83.
* Legacy hardcoded 8000/250/5000 remain as config fallbacks for fresh install before any `GoalPrefs.save`.

## API

```dart
// sync, caller supplies goals (avoids async in build)
int HealthEngine.instance.calcActivityScoreWithGoals(
  steps: 7342, calories: 312, distanceM: 5420,
  goals: GoalTargets(steps:10000, calories:1000, distanceKm:5.0),
);

// async convenience (loads GoalPrefs + config internally)
Future<int> HealthEngine.instance.calcActivityScore(
  steps: 7342, calories: 312, distanceM: 5420,
);
```

Home + Steps both call the engine. Home’s compact badge `activityScoreLabel(score)` is now `HealthEngine.instance.activityLabel(score)`. `ActivityDescriptionScreen`’s blurb and weight chips also read weights from the engine so Studio can retune `60/25/15` without code.

## Labels

Same cut-offs centralised (from `steps_screen.dart:560`):

```
score == 0 → Lack of exercise  (AppTheme.danger)
score < 25 → Sedentary
score < 50 → Lightly active   (AppTheme.tempColor)
score < 75 → Moderately active (AppTheme.spo2Color)
else       → Highly active     (AppTheme.success)
```

`activityLabel` and `activityLabelColor` are on the engine.

## Wiring

* `lib/screens/home/home_screen.dart:176` `_computeActivityScore` → `HealthEngine.calcActivityScoreWithGoals` (loads goals via `GoalPrefs.load()` cached in `HealthConfig`; Home’s `build` becomes `FutureBuilder` or uses `context.watch<GoalPrefsProvider>` — added as lightweight wrapper).
* `lib/screens/health/steps_screen.dart:554` `_activityScore` getter → same.
* `lib/screens/health/activity_description_screen.dart:58` description text `"It blends steps (up to 60 pts at 8,000) …"` → `HealthEngine.instance.activityDescription()` which interpolates the actual goal denoms + weights from config + user goals, so copy never lies after goal change.
* `lib/screens/settings/goal_setting_screen.dart:39` after `GoalPrefs.save` → `await HealthConfig.notifyGoalChanged()` / `HealthEngine.instance.invalidateActivityCache()` so next Home build reflects new goals without restart.

## Config

```json
{
  "thresholds": {
    "activity": {
      "stepsWeight": 60, "caloriesWeight": 25, "distanceWeight": 15,
      "stepsDenom": 10000, "caloriesDenom": 1000, "distanceDenomM": 5000
    }
  }
}
```

Only the weights/denoms are in config; the *effective* denom at call time is `GoalPrefs`. If a user never opened Goal Setting, denom falls back to `stepsDenom`.

## Testing

* `test/health_engine_activity_test.dart`: matrix of `(steps,cal,dist,goals)` → score, including clamping, zero, overflow (>goal).
* Golden: with default goals `(10000,1000,5.0)` the legacy case `8000/250/5000` should score `48+25+15=88?` Actually 8000→48 (8000/10000*60), 250→6 (250/1000*25), 5000→15 → 69, showing the shift from legacy 8000 assumption — documented as intentional goal-aware change.

