# Per-vital history coverage (ring → app)

Ring buffer: 7 days (`dayIndex 0..6`, `deviceHealthHistoryMaxDayIndex() == 6`).
"View all history from the ring" = range fetch `startDay=0, count=7` via
`BleService.fetchRingHistory(vital)` (`lib/services/ble_service.dart`,
`kRingHistoryMaxDays = 7`).

## Status per vital (verified 2026-09-19)

| Vital | Range channel | Full 0..6 pull on demand | Notes |
|---|---|---|---|
| Sleep | `getSleepList` | ✅ `sleep_screen._loadHistory` → `getSleepList(0, 7)` | Reference implementation (pre-existing) |
| Steps | `getStepsList` | ✅ `_pullRingHistory` → `_parseIntervalJson` + `_saveToDb` per day | Wired 2026-09-19 |
| Heart rate | `getHeartRates` | ✅ `_pullRingHistory` → `array`/`mHeartRateArray` (unsigned, 30–220) → `upsertHr` per day | Wired 2026-09-19 |
| Blood pressure | `getBloodPressures` | ✅ `_pullRingHistory` → `{time,sbp,dbp}` → `insertBp(…, source: ring_history)` | time s/ms auto-normalized; wired 2026-09-19 |
| Pressure (stress) | `getPressureList` | ✅ `_pullRingHistory` → `pressureArray` bytes (unsigned, drop 0xFF, 0–100) → `insertStress` per day | Byte→stress per oudmon convention; wired 2026-09-19 |
| HRV | `getHrvList` | ✅ `_pullRingHistory` → `d` or `pressureArray` → `upsertHrv` per day | Wired 2026-09-19 |
| Blood oxygen | `getBloodOxygens` | ✅ `_pullRingHistory` → `array`/`minArray`/`maxArray` (1–100) → `upsertSpo2` per day | Wired 2026-09-19 |
| Temperature | `getTemperatureList` | ❌ blocked: `IntervalTemperatureEntity{array,values[{value1..3}]}` semantics unverified; `TemperatureEngine` Map-case keys don't match | Needs one live-ring sample — log `getTemperatureList` output once and map it |
| Sport | `SportPlusHandle` sync | ❌ sync-on-open only; no history screen consumes records | No day-range API wired |
| Breath / ECG / Sugar | n/a (app-side data) | n/a | No ring history; sugar channel is a `"[]"` stub |

## Standard wiring pattern (all `_pullRingHistory` hooks)

1. Return early when `BleProvider.isConnected` is false.
2. `await _ble.fetchRingHistory('<vital>')` — bounded by the `BleService`
   Dart-side timeouts (10–15 s per call, cf. sleep fix).
3. Decode `List`, per entry read `dayIndex`/`day_index` (skip outside 0..6),
   take `data`, parse with the vital's proven keys (see `sdk-vs-plugin.md`
   contract table), skip empty days.
4. Persist per day through the existing `SupabaseService` upsert/insert
   (`upsertHr/Spo2/Hrv/Steps`, `insertBp/Stress` with `source: ring_history`).
5. On any write, quietly reload the trend (`_load7DayTrend(quiet: true)` —
   skips the spinner) or refresh the visible day (steps: `_loadDay(force: true)`).
6. Whole body in `try/catch (_) {}` — expected-offline stays silent, no
   incidents. Steps additionally generation-guards via `_loadGen`.

## Payload shape (all range APIs)

```json
[{"dayIndex": 0, "data": { /* same shape as the single-day fetch */ }}]
```

`day_index` snake_case variant also accepted by parsers.
