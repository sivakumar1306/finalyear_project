# SleepEngine — Priority Extraction

> Largest leak: `lib/screens/health/sleep_screen.dart:216-437` (~220 lines) parsing lives in `State`. Must move to `lib/services/health_engine/sleep_engine.dart`.

## Current Widget Code

* `29-42` stage const `0=deep,1=light,2=awake,3=REM` + `_stageColors` — enum belongs in engine, colors stay UI.
* `216-324` `_parseSleepData(jsonStr, {date})` — detects `totalSleepDuration` vs new-proto `st/et/list {d,t}`, recomputes `calcTotal/calcDeep/Light/Rem/Awake` via `switch(type)`, calls `_calcScore`.
* `326-437` `_parseSegments(rawList,st,et)` — heuristic `firstD>1e9` → timestamp vs duration; `d<500 →*60`, `d<10000→seconds`, `cursor` reconstruction, `st==0` shift `et-last.end`, old-proto `sleepStart/sleepEnd/type`.
* `439-440` `_calcScore` already delegates `HealthEngine.calcSleepScore`.
* `757-762` `_efficiency` `total/(wake-sleep)*100`; `764-766` `_quality` delegates; `768-811` `_avgHistory*`, `_last7Bars`, `_trendDayLabels`.
* `1267-1376` `_syntheticSegs` + `_yPos 0.05/0.35/0.62/0.88` — synthetic data engine, painter is UI.

## Extracted API

```dart
class SleepEngine {
  // Pure
  static ({int total, int deep, int light, int rem, int awake}) calcTotals(List<Map<String,int>> segs);
  static List<Map<String,int>> parseSegments(dynamic rawList, int st, int et);
  static ({int total, int deep, int light, int rem, int awake, int st, int et, List<Map<String,int>> segs}) parseSleepData(String jsonStr);
  static double efficiency(int total, int st, int et);
  static List<Map<String,int>> syntheticSegs({required int total, required int deep, required int light, required int rem, required int awake, required int st});
  // Service (wraps HealthEngine scoring)
  static int calcScore(int total, int deep, int rem, int st, int et) => HealthEngine.instance.calcSleepScore(total: total, deep: deep, rem: rem, st: st, et: et);
}
```

`parseSleepData` handles both new-proto `st/et/list d/t` and old `totalSleepDuration/deepDuration` plus fallback `IncidentService` reporting moved to caller (widget catches). Keeps heuristic `d>1e9` and `d<500` exactly.

## Widget After

```dart
final parsed = SleepEngine.parseSleepData(jsonStr);
setState(() { _totalDuration=parsed.total; _deepDuration=parsed.deep; ... _sleepScore=parsed.score; _segments=parsed.segs; });
_saveToDb(...);
```

`_inter`, `build` glass cards, `_HypnogramPainter` paint remain UI; `_yPos` stays in painter or provided via engine `stageYFraction(type)`.

## Tests

* New-proto timestamp `d=1_700_000_000` vs duration `d=30` (`*60`→1800s) vs `d=5000` seconds.
* `st==0` shift, old-proto `sleepStart`, `calcTotal` path, `total<=0 → loadDayFromDb` fallback, `_syntheticSegs` length.
