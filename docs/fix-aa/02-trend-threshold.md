# 02 — 7-Day Trend Threshold (1 → 2+ days, BP paired)

> Files: `lib/utils/trend_math.dart:36-63`, `lib/widgets/not_enough_data_card.dart:71-91`, 7 health screens | `DESIGN.md:536-558` Trend Section

## Problem

User report: *“for all the trend cards, the trends start showing in two days itself”* — actually **worse**: code showed trends after **1 day**.

Every health detail screen gated trends with:

```dart
// lib/screens/health/heart_rate_screen.dart:760 (also SpO2:781, Stress:702, HRV:811, Temp:763, Sleep:869)
if (_trendValues.every((v) => v == 0) && !_loadingTrend && !_trendOffline)
  const NotEnoughTrendDataCard(metric: 'heart rate')
else
  ScrubbableChart(values: _trendValues, ...)
```

* `every==0` → **any** single non-zero day (out of 7) renders the bar chart (1 bar + 6 `AppTheme.div` 3 px stubs).
* Card copy `lib/widgets/not_enough_data_card.dart:86` said `4+ days` — copy **contradicted** code. User felt 2-day sparse charts were premature.

`blood_pressure_screen.dart:838` was similar but dual:
```dart
if ((_trendSbp.every((v)=>v==0) && _trendDbp.every((v)=>v==0)) && ...)
```

## Decision

Per user (2026-09-06): **threshold = 2+ days**, **BP pair = `sbp>0 && dbp>0`** (a valid day requires both arms).

* `2` shows trends earlier than `4` but hides the 1-day sparse case.
* `pair` prevents trend from days with only one arm (e.g., `SBP 130` but `DBP 0`).

## Implementation

### 1. Centralize in `lib/utils/trend_math.dart:36-63`

```dart
// Pure trend math — replaces 12× reduce(min/max) + fold avg dup.
static List<int> last7Bars(List<Map<String, dynamic>> rows) { ... } // existing 36-46

/// Minimum non-zero days required before a 7-day trend chart is shown.
/// Gates all `NotEnoughTrendDataCard` checks (2+ days per user decision).
static const kMinTrendDays = 2;

static bool hasEnoughTrendData(List<num> values, {int minDays = kMinTrendDays}) =>
    values.where((v) => v > 0).length >= minDays;

static bool hasEnoughBpTrendData(List<int> sbp, List<int> dbp, {int minDays = kMinTrendDays}) {
  final n = sbp.length < dbp.length ? sbp.length : dbp.length;
  int count = 0;
  for (int i = 0; i < n; i++) {
    if (sbp[i] > 0 && dbp[i] > 0) count++;
  }
  return count >= minDays;
}
```
* `List<num>` covers `List<int>` (HR, SpO2, Stress, HRV, Sleep) and `List<double>` (Temperature `36.5`).
* `kMinTrendDays` single source — changing `2 → 3/4` updates all 7 screens.

### 2. Update 7 screens (preserve `loading`/`offline` guards)

| Screen | Line | Before | After |
|---|---|---|---|
| `sleep_screen.dart` | `870` | `trendVals.every((v)=>v==0) && !_dbOffline` | `!TrendMath.hasEnoughTrendData(trendVals) && !_dbOffline` |
| `heart_rate_screen.dart` | `760` | `_trendValues.every((v)=>v==0) && !_loadingTrend && !_trendOffline` | `!TrendMath.hasEnoughTrendData(_trendValues) && !_loadingTrend && !_trendOffline` |
| `blood_oxygen_screen.dart` | `781` | same | same |
| `stress_screen.dart` | `702` (+`26` import) | same | same + `import trend_math.dart` |
| `hrv_screen.dart` | `811` | same | same |
| `temperature_screen.dart` | `763` (+`28` import) | `_trendValues.every((v)=>v==0)` (`List<double>`) | `!TrendMath.hasEnoughTrendData(_trendValues)` + import |
| `blood_pressure_screen.dart` | `838` (+`25` import) | `(_trendSbp.every==0 && _trendDbp.every==0)` | `!TrendMath.hasEnoughBpTrendData(_trendSbp,_trendDbp)` + import |

* Comments updated to `(2+ days)` / `(2+ paired days)`.

### 3. Copy fix `lib/widgets/not_enough_data_card.dart:86`

```dart
- Text('No $metric trend yet — 4+ days of data are needed. Keep wearing your ring.',
+ Text('No $metric trend yet — 2+ days of data are needed. Keep wearing your ring.',
```

Aligns card with code.

## Design & Reuse

* No new card: reuses `NotEnoughTrendDataCard` (`lib/widgets/not_enough_data_card.dart:71`) and `MetricChartCard`/`ScrubbableChart` (`lib/widgets/metric_chart_card.dart:8`, `chart_scrubber.dart:174`).
* No new colors/spacing; `ScrubbableChart` still renders 7 slots with `5.5px gap`/`barW max 4→9px`; zero days remain `AppTheme.div` stubs until threshold met, then chart appears with 2+ bars — future could hide stubs, out of scope.

## Verification

* `flutter analyze` 17 warnings (pre-existing), 0 errors on changed files.
* `flutter test` 113 passed (including `engines_utils_test.dart:22` TrendMath).
* Manual matrix (mock `LocalVitalsService.historyAvgSeries`):

| Non-zero days | `hasEnoughTrendData` | UI |
|---|---|---|
| 0 `[0]*7` | `false` | `NotEnoughTrendDataCard` |
| 1 `[0,0,0,0,0,0,65]` | `false` | `NotEnoughTrendDataCard` (was chart pre-fix) |
| 2 `[0,0,0,0,0,60,65]` | `true` | `ScrubbableChart` (2 bars) |
| 7 `[60]*7` | `true` | Chart |

BP:
* `[0,0,0,0,0,0,130]` / `[0,0,0,0,0,0,85]` → 1 pair → `false` → empty
* `[0,0,0,0,0,120,130]` / `[0,0,0,0,0,80,85]` → 2 pairs → `true` → chart
* Mixed `[130,130]` / `[0,85]` → 1 pair → `false` (pair semantics).

## Alternatives Rejected

* Inline `where((v)=>v>0).length <2` in each screen — duplicates magic `2` 7×.
* Keep `4+` copy and `kMinTrendDays=4` — rejected per user’s `2+` choice (earlier visibility).
* `||` for BP (`sbp>0 || dbp>0`) — rejected, would show trend with incomplete day.

## Rollback

Set `kMinTrendDays=4` and copy back to `4+` — single-line in two files.

## References

* `lib/utils/trend_math.dart:1` pure math
* `lib/utils/date_keys.dart` `trendXLabels()` (x-axis, 7 day labels)
* `lib/widgets/chart_scrubber.dart:174` `ScrubbableChart` / `ScrubbableBPChart`
