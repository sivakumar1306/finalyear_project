# DateKeys & Formatters — Pure Utils

## Duplication

* `_fmt yyyy-MM-dd padLeft` `heart_rate_screen.dart:114` ×16 (`supabase_service.dart:147`, `local_vitals_service.dart:28`, `sleep_screen:607`, `steps_screen:135`).
* `_isToday year/month/day` `heart_rate_screen.dart:82` ×7, `dayIndexFor today.difference(sel).inDays` `steps_screen:140`, `_isTodayTimestamp` `ble_provider.dart:1254`.
* `_hourLabel 12am/pm` `heart_rate_screen:639` ×4, `trendXLabels days[weekday-1]` `heart_rate_screen:630` ×7, `_trendDayLabels M/T/W` `sleep_screen:804`.

## Extracted: `lib/utils/date_keys.dart`

```dart
abstract class DateKeys {
  static String fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  static bool isToday(DateTime d) { final n=DateTime.now(); return d.year==n.year && d.month==n.month && d.day==n.day; }
  static bool sameDay(DateTime a, DateTime b) => a.year==b.year && a.month==b.month && a.day==b.day;
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static String dateKey(DateTime d) => fmt(dateOnly(d));
  static int dayIndexFor(DateTime d) { final today=dateOnly(DateTime.now()); return today.difference(dateOnly(d)).inDays; }
  static bool isFuture(DateTime d) => dateOnly(d).isAfter(dateOnly(DateTime.now()));
  static List<String> trendXLabels() { const days=['Mon','Tue','Wed','Thu','Fri','Sat','Sun']; final now=DateTime.now(); return List.generate(7,(i){ final d=now.subtract(Duration(days:6-i)); return days[d.weekday-1];}); }
  static List<String> trendDayLabelsShort() { const n=['M','T','W','T','F','S','S']; final now=DateTime.now(); return List.generate(7,(i){ final d=now.subtract(Duration(days:6-i)); return n[d.weekday-1];}); }
  static int dayStartMs(DateTime d) => DateTime(d.year,d.month,d.day).millisecondsSinceEpoch;
  static int dayEndMs(DateTime d) => DateTime(d.year,d.month,d.day,23,59,59,999).millisecondsSinceEpoch;
}
```

`SupabaseService._dateStr` `675` and `LocalVitalsService.dayStartMs/dayEndMs` `18-26` will delegate to `DateKeys`.

## Formatters: `lib/utils/formatters.dart`

```dart
abstract class Formatters {
  static String sleepDuration(int secs) { if(secs<=0) return '--'; final h=secs~/3600,m=(secs%3600)~/60; if(h>0&&m>0) return '${h}h ${m}m'; if(h>0) return '${h}h'; return '${m}m'; } // home_screen:196 + sleep_screen:739 merge, 60*60 vs 60*60 exact
  static String sleepTimeLabel(int ts) { if(ts<=0) return '--'; final dt=DateTime.fromMillisecondsSinceEpoch(ts*1000); ... 12:$m$am/pm } // sleep_screen:747
  static String hourLabel(int h) { if(h==0) return '12am'; if(h<12) return '${h}am'; if(h==12) return '12pm'; return '${h-12}pm'; }
  static String halfHourLabel(int slot) { final m=slot*30,h=m~/60,mm=m%60; ... } // hrv_screen:669
  static String fmtTime(DateTime dt) { ... h12:$m $ampm } // hrv_screen:125
}
```

*Pure, no `BuildContext`.* Widgets keep `_inter/_t` `AppTypography.inter` (UI typography per `DESIGN.md:394-455`).

## Verification

`test/date_keys_test.dart` — `fmt` zero-pad, `isToday` true/false across midnight, `dayIndexFor` 0 today, `hourLabel` 0→12am, 12→12pm, 13→1pm, `trendXLabels` length 7 Monday-Sunday.
