# 01 — Sleep Dual Empty-State Overlap

> File: `lib/screens/health/sleep_screen.dart:620-887` | Widget: `lib/widgets/not_enough_data_card.dart:9,71` | Card: `lib/widgets/glass_card.dart`

## Problem

When **no sleep data** exists (new user / ring not worn), two empty cards rendered with **no separation**:

* Daily `NotEnoughDataCard(metric:'sleep')` at `lib/screens/health/sleep_screen.dart:700-705` — `if (!hasData && !_loading && !_dbOffline)`
* Trend `NotEnoughTrendDataCard(metric:'sleep')` at `869-871` — `if (trendVals.every((v)=>v==0) && !_dbOffline)`

Both are `GlassCard` (`DESIGN.md:153-183`: `bg rgba(255,255,255,0.06)`, `border 0.5px rgba(255,255,255,0.09)`, `backdrop-filter blur 28px`, `radius 20px`, `padding 16px`) with ambient orb blur. With 0 gap the blurs visually **overlap/merge**, appearing as one card sitting atop another.

## Root Cause Analysis

Detail pages share structure `DESIGN.md:536-558`:
`Navigation Header → DateSelector → Current Reading → Primary Chart → Statistics Cards → Measurement CTA → Trend Section → Historical Insights`

* **Other screens** (reference: correct):  
  `lib/screens/health/heart_rate_screen.dart:688-762` → daily `if/else` (`NotEnoughDataCard` vs `ScrubbableChart + MetricStatCard×3 + RealTimeCard`) **then** unconditional `const SizedBox(height:20)` at `757` **before** `// 7. trend` at `760`.
  Same in `stress_screen.dart:623-703` (`SizedBox` at `699`), `blood_oxygen_screen.dart:708-783` (`778`), `hrv_screen.dart:735-812` (`808`), `blood_pressure_screen.dart:760-840` (`835`), `temperature_screen.dart:682-765` (`759`).

* **Sleep (bug)**:  
  `sleep_screen.dart:825` had `const SizedBox(height:20)` **inside** the `else` block (before `// 7. Vitals during sleep` at `827`), and `864` `Row(vitals)` was the last child before `],` at `865`. The `SizedBox` at `825` is *not* the inter-section gap — the gap at `865` was `SizedBox(height:20)` **inside** the `else` as the final element. So:
  * `hasData==true` → inside `SizedBox(20)` at `864→865` provided 20 px before trend — correct.
  * `hasData==false` → `else` not taken, **no** `SizedBox` rendered, column went `NotEnoughDataCard → NotEnoughTrendDataCard` with 0 px.

Visually: glass cards touch, shadows/blur stack.

## Fix

**Single unconditional spacer** — move gap outside the `if/else`:

```dart
// lib/screens/health/sleep_screen.dart:864-871
                ),
              ],   // ← end else

              const SizedBox(height: 20),   // ← NEW: always 20 px, matches other screens

              // ── 8. 7-day trend — collapse when empty (2+ days required)
              if (!TrendMath.hasEnoughTrendData(trendVals) && !_dbOffline)
                const NotEnoughTrendDataCard(metric: 'sleep')
```

* Removed the trailing `const SizedBox(height:20)` that was at `864` inside `else` (now at `867` outside). Net diff: **one moved line** (`git diff` shows `- SizedBox inside` + `+ SizedBox outside`).
* Reuses `SizedBox(height:20)` token already used everywhere — **no new design pattern** per `CLAUDE.md:3-4`.
* `TrendMath` gate change at `870` is covered in `02-trend-threshold.md`; this file focuses on spacing.

## Alternatives Considered

* Add conditional `if (!hasData) SizedBox` — rejected, duplicates logic.
* Keep both inner + outer `SizedBox(20)` → 40 px when `hasData==true` (double gap, not matching other pages).
* Wrap both cards in `Column(spacing:20)` — rejected, introduces new layout pattern not in `DESIGN.md`.

## Verification

* `flutter analyze lib/screens/health/sleep_screen.dart` — no errors (same 17 pre-existing warnings elsewhere).
* Manual: set `SupabaseService.getSleepForDate → null` + `getSleepHistory → []` → both cards visible, measure gap via Widget Inspector `getRect` → `trendCard.y - (dailyCard.y+ dailyCard.height) == 20.0`.
* With `hasData==true` (mock `totalDuration=28800`) → `SLEEP STAGES` chart + `VITALS DURING SLEEP` row + 20 px + `LAST 7 DAYS TREND` chart — same as HR/SpO2.

## Rollback

Remove line `867` `const SizedBox(height:20)` → restores 0-gap bug.

## References

* `DESIGN.md:149-183` Card system, `DESIGN.md:536-558` Detail Pages structure
* `lib/widgets/not_enough_data_card.dart:9` (`NotEnoughDataCard`), `:71` (`NotEnoughTrendDataCard`)
* `lib/theme/app_theme.dart` `glassCard`/`glassBorder`
