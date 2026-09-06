# Hourly Aggregator & TrendMath & ScrubHelper

## Bucketing (10 sites)

* HR/SpO2 24-slot `sums[hour]+=v; counts[hour]++; for(h) if(counts>0) hourly[h]=round(sums/counts)` `heart_rate_screen.dart:179-202` + `stress_screen:195-218` + `temperature:200-223` double + `blood_pressure:226-256` dual SBP/DBP `hrv_screen:190-221` 48-slot `(hour*60+minute)~/30`.
* Steps 96→24 `slots.sublist(h*4,h*4+4).fold` `steps_screen.dart:803-811`.

## Extracted: `lib/utils/hourly_aggregator.dart`

```dart
abstract class HourlyAggregator {
  static List<int> aggregateInt(List<Map<String,dynamic>> readings, {required String valueKey, required String measuredAtKey, int slots=24, int Function(int hour, int minute)? slotFor}) { ... }
  static List<double> aggregateDouble(... slots=24) { ... }
  // SBP/DBP dual
  static ({List<int> sbp, List<int> dbp}) aggregateBp(List<Map<String,dynamic>> readings) { ... }
  // HRV 48-slot specialization
  static List<int> aggregateHrv(List<Map<String,dynamic>> readings) => aggregateInt(readings, valueKey:'valueMs', slots:48, slotFor:(h,m)=> (h*60+m)~/30);
  // Steps 96→24 already helper `toHourlyInt/Dbl` moves here
}
```

*Pure* — takes `readings` list, returns `List<int|double> filled`. Replaces `State` methods `_hourlyFromHrReadings 342` etc.

## TrendMath: `lib/utils/trend_math.dart`

```dart
abstract class TrendMath {
  static int avg(List<int> v) => v.isEmpty?0: v.fold(0,(a,b)=>a+b) ~/ v.length;
  static double avgDouble(List<double> v) => ...;
  static int min(List<int> v) => v.reduce((a,b)=>a<b?a:b);
  static int max(List<int> v) => v.reduce((a,b)=>a>b?a:b);
  static ({int min, int max}) minMax(List<Map<String,dynamic>> rows, String minKey, String maxKey) { ... }
  static List<int> last7Bars<T>(List<T> rows, String dateKey, String valueKey) { ... } // sleep_screen:786-800
}
```

Replaces `heart_rate_screen:376-383` `trendMin = valid.reduce((a,b)=>a<b?a:b)`, `sleep_screen:768-774` `fold`.

## ScrubHelper: `lib/utils/scrub_helper.dart`

```dart
abstract class ScrubHelper {
  static int initialIndex(List<int> values) { for(int i=values.length-1;i>=0;i--) if(values[i]>0) return i; return 0; } // chart_scrubber:243
  static int indexFromDx(double dx, double width, int count) => (dx/width*count).floor().clamp(0,count-1); // chart_scrubber:432
}
```

Small but duplicated at `ScrubbableChart` and `ScrubbableBPChart:648`.

## Chart Thresholds

Painters hard-code `maxY 120 yLines [120,100,80,60] barColor hr` (`heart_rate:752`), `maxY 100 baseline 85` (`blood_oxygen:788`), `maxY 40 baseline 34` (`temperature:788`). These `maxY/baseline/yLines` are domain thresholds — should read `HealthConfig` via `HealthEngine` but widget keeps `barColor` callback already.
