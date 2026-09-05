# Thresholds

All numeric bands live in `HealthConfig` (`lib/services/health_engine/health_config.dart:kDefaultConfig`) and are overridable via Supabase `health_engine_config.config.thresholds`.

## Sleep (score 0–100)

Formula (unchanged, now centralised):

```
window = (st>0 && et>0) ? (et - st) : total
efficiency = total/window*100  clamp 0..100
deepPct    = deep/total*100    clamp 0..40
remPct     = rem/total*100     clamp 0..30
score = (efficiency*0.4 + deepPct*1.0 + remPct*0.5).round() clamp 0..100
```

Bands — canonical `80/60/40` (Home + VitalNote were already 80/60/40; detail’s 85/70/55 was drift and is now fixed):

```
score >= excellent (80) → Excellent  (AppTheme.success)
score >= good (60)      → Good       (AppTheme.sleepColor)
score >= fair (40)      → Fair       (AppTheme.amber)
score > 0               → Poor       (AppTheme.danger)
else                    → No data    (AppTheme.textSec)
```

Config keys: `thresholds.sleep.excellent / good / fair`.

## Heart Rate (bpm)

```
v <=0        → No data
v < below    → Below normal  (60 default, AppTheme.hrvColor)
v < above    → Normal        (100 default, AppTheme.success)
else         → Above normal  (AppTheme.danger)
```

Keys: `thresholds.hr.belowNormal`, `aboveNormal`.

Ranges shown in Note: `<60`, `60–99`, `100+`.

## SpO₂ (%)

```
v <=0            → No data
v >= normal (95) → Normal      (AppTheme.success)
v >= borderline (90) → Borderline (AppTheme.amber)
else             → Low         (AppTheme.danger)
```

Keys: `thresholds.spo2.normal`, `borderline`. Note ranges `95–100 / 90–94 / <90`.

## HRV (ms)

```
v <=0          → --  (AppTheme.textSec)
v < 20         → Very Low  (AppTheme.danger)
v < 40         → Low       (AppTheme.stressColor)
v < 60         → Moderate  (AppTheme.amber)
v < 80         → Good      (AppTheme.success)
else           → Excellent (AppTheme.hrvColor)
```

Keys: `thresholds.hrv.veryLow / low / moderate / good`. Matches `hrv_screen.dart:119`.

## Stress (0–100)

```
v <=0         → -- (textSec)
v < relaxed (40)  → Relaxed  (AppTheme.success)
v < normal (60)   → Normal   (0xFFFBBF24)
v < elevated (80) → Elevated (AppTheme.stressColor)
else              → High     (AppTheme.danger)
```

Keys: `thresholds.stress.relaxed / normal / elevated`.

## Blood Pressure (mmHg)

AHA/ACC staged — `lib/utils/bp_staging.dart:40` logic now reads thresholds from config:

```
if sbp<=0||dbp<=0 → noData
if sbp<normalSbp (120) && dbp<normalDbp (80)           → Normal (success)
if sbp<elevatedSbp (130) && dbp<normalDbp              → Elevated (amber)
if sbp<stage1Sbp (140) && dbp<stage1Dbp (90)           → Stage1 (stressColor)
else                                                    → Stage2 (danger)
```

Keys: `thresholds.bp.normalSbp / normalDbp / elevatedSbp / stage1Sbp / stage1Dbp`.
`InsightsService` now delegates to this instead of ad-hoc `>=130`.

Note ranges: `<120/80`, `120–129/<80`, `130–139/80–89`, `140+/90+`.

## Temperature (°C, ring native; display converts via UnitPrefs)

```
v <=0                  → -- (textSec)
v < low (36.0)         → Low       (AppTheme.spo2Color)
v <= normal (37.2)     → Normal    (AppTheme.success)
v <= elevated (38.0)   → Elevated  (AppTheme.tempColor)
else                   → Fever     (AppTheme.danger)
```

Keys: `thresholds.temp.low / normal / elevated`. Values stay Celsius; engine exposes `barColor(double c)` re-used by charts.

## Activity (0–100)

Weights fixed per product spec (see `activity.md`):

```
stepsW=60, calW=25, distW=15  (configurable weights but fixed defaults)
score = (steps/goalSteps*stepsW).clamp(0,stepsW)
      + (cals /goalCals *calW ).clamp(0,calW)
      + (distM/(goalKm*1000)*distW).clamp(0,distW)
      round clamp 0..100
```

Goal denominators come from `GoalPrefs` (user’s Goal Setting screen), not config. Config only stores weights and legacy fallbacks (`thresholds.activity.stepsDenom=10000` etc. when no GoalPrefs yet).

Labels: `0 → Lack of exercise`, `<25 Sedentary`, `<50 Lightly active`, `<75 Moderately active`, else `Highly active`.

## Updating

Edit `health_engine_config` row in Supabase Studio (JSONB). Engine deep-merges over defaults; missing keys keep default. Pull-to-refresh on Home re-fetches (`HealthConfig.refresh()`).

Add/adjust test in `test/health_engine_test.dart` with band edges.
