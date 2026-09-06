# fix-aa — Sleep Dual Empty-State Spacing & 7-Day Trend Threshold (2+ days)

> Date: 2026-09-06 | Branch: `main` post-merge `chore/health-connector-migration` | Flutter 3.47.2 / Dart 3.13.2
> Status: **Implemented** (9 files, `flutter analyze` 17 warnings pre-existing, `flutter test` 113 passed)

## TL;DR

1. **Sleep overlapping cards** — `lib/screens/health/sleep_screen.dart:699-871` had two `GlassCard`-based empty states (`NotEnoughDataCard` for daily, `NotEnoughTrendDataCard` for trend) stacked with **0 px gap** when both empty (glass blur + orb overlap). Fixed by moving the `SizedBox(height:20)` from *inside* the daily `else` to an **unconditional** `SizedBox(height:20)` at `867` between the daily section and the trend section — matching every other detail screen (`heart_rate_screen.dart:757`, `stress_screen.dart:699`, `blood_oxygen_screen.dart:778`, etc.). Reuses `DESIGN.md` tokens only.

2. **Trends appeared after 1 day** — all 7 health detail screens gated with `if (_trendValues.every((v)=>v==0))`, so a single non-zero day rendered a sparse bar chart. User wanted `2+ days` (BP: 2+ *paired* days). Centralized to `lib/utils/trend_math.dart:48-63` (`kMinTrendDays=2`, `hasEnoughTrendData`, `hasEnoughBpTrendData`) and updated 7 screens + copy `lib/widgets/not_enough_data_card.dart:86` (`4+ → 2+ days`).

## Files Touched

| File | Lines | Change |
|---|---|---|
| `lib/utils/trend_math.dart` | `48-63` | Add `kMinTrendDays=2` + 2 helpers |
| `lib/widgets/not_enough_data_card.dart` | `86` | Copy 4+ → 2+ |
| `lib/screens/health/sleep_screen.dart` | `825,867,870` | Move `SizedBox(20)` outside `else`, gate `hasEnoughTrendData` |
| `lib/screens/health/heart_rate_screen.dart` | `760` | Gate `hasEnoughTrendData` |
| `lib/screens/health/blood_oxygen_screen.dart` | `781` | Gate `hasEnoughTrendData` |
| `lib/screens/health/stress_screen.dart` | `26,702` | Add import + gate |
| `lib/screens/health/hrv_screen.dart` | `811` | Gate |
| `lib/screens/health/temperature_screen.dart` | `28,763` | Add import + gate (`List<double>`) |
| `lib/screens/health/blood_pressure_screen.dart` | `25,838` | Add import + pair gate |

## Design Compliance

* `DESIGN.md:149-183` Card system: `rgba(255,255,255,0.06)` + `border 0.5px rgba(255,255,255,0.09)` + `blur 28` + `radius 20` + `padding 16` — reused via `GlassCard`/`NotEnoughDataCard`, no new tokens.
* Spacing `20` already canonical between daily and trend (`Detail Pages: Structure 1-8`).
* No new colors, shadows, or patterns.

## Verification

* `flutter analyze` — 17 warnings (all pre-existing `unused_import`/`unused_local_variable` in HR/SpO2/HRV + `health_connect_service.dart`), zero errors in changed files.
* `flutter test` — 113 passed (`engines_utils_test.dart:22` TrendMath, `health_engine_test.dart`, etc.).
* Manual: 0 days → `NotEnoughTrendDataCard`, 1 day → still empty, 2 days → `ScrubbableChart` with 5 `AppTheme.div` stubs; BP 1 pair → empty, 2 pairs → chart; sleep empty → two glass cards with 20 px gap (no blur overlap).

## Decisions Log

* **Threshold = 2** per user (was 4 in card copy). Chosen over 3/4 to show trends earlier while avoiding 1-day sparse chart.
* **BP pair = `sbp>0 && dbp>0`** per user (vs `||`). Prevents trend from a day with only one arm present.
* **Temperature `List<double>`** uses same `hasEnoughTrendData(List<num>)`.

## Rollback

* Revert `kMinTrendDays` to `4` and copy to `4+` if user wants later.
* Sleep spacing is single-line `SizedBox`: removing it restores old 0-gap bug.

---
See `01-sleep-spacing.md` and `02-trend-threshold.md` for deep dives.
