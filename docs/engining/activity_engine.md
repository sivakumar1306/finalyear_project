# ActivityEngine & TemperatureEngine & CycleEngine

## ActivityEngine `lib/services/health_engine/activity_engine.dart`

* Pure: `parseIntervalJson(String json) -> DaySnapshot` handling obfuscated `d/f/e/g` vs `timeIndex/walkSteps/calorie/distance`, `totalCalRaw>=1000?~/1000:>0?1:0` (`steps_screen:231-288`), `normalizeCalories(raw,steps)` `raw>=500&&steps<4000?~/1000` (`supabase 344`), `distributeSteps(curSteps, nowSlot)` `activeSlotsCount=(nowSlot-28).clamp(1,96)` `stepsPerSlot=curSteps/activeSlotsCount` (`steps_screen:169`), `toHourlyInt/Dbl(slots)` `sublist(h*4).fold` (`803-811`).
* Service: `calcScoreWithGoals` already in `HealthEngine` but pure core moves here; service wrapper `HealthEngine.calcActivityScoreWithGoals` will delegate.

## TemperatureEngine `temperature_engine.dart`

* Pure: `parseTempReadings(String json, DateTime base)` list vs map `{mValues/d, mTimeSpan/b, a/b}` `val>100/10` (`temperature_screen:547-605`), `disp(double c, TempUnit)` wrapper for `UnitPrefs.celsiusToFahrenheit`.

## CycleEngine `cycle_engine.dart`

* Pure: `phaseName(day,cycleLen,periodLen)` `<=pLen menstruation, <=13 follicular, <=16 ovulating else luteal` (`home_compact_cards:180`, `home_vitals_cards:94`, `WomensHealthMiniCard:180`), flex ratios `13-pLen/3/len-16` (`CyclePhaseBar 344-387`), `cycleDay = now.diff(periodStart).inDays+1 clamp`. Removes duplication between `CompactWomensHealthCardState._loadCycle` and `WomensHealthMiniCard`.

## Delegation

UI keeps `GlassIconButton`/`SidePanel` etc. After extraction, widgets call `ActivityEngine.parseIntervalJson(...)` and `HourlyAggregator` instead of inline loops.

## Tests

* `parseIntervalJson` with `d/f/e/g` vs clear keys, `totalCalRaw 2142 for 547 steps → 2 kcal`, `distributeSteps 0 steps → 0 slots`.
* `parseTempReadings` `mTime/mValue` vs `a/b` vs `mValues/d`, `val 365 →36.5`.
