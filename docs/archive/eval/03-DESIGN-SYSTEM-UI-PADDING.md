# 03 — Design-System & UI Audit (DESIGN.md compliance, spacing, padding, hardcoded values)

> Audit basis: `DESIGN.md` — soft glassmorphism (blur 28px, radius **20px**, padding **16px**), "#C9A86E as the only primary accent color" (DESIGN.md:603), "Every card must use glass styling" (DESIGN.md:601), "Maintain consistent spacing and radius" (DESIGN.md:604). Plus `lib/theme/app_theme.dart`.

## 3.1 Health screens re-define design tokens — [MED] (confirmed)

`_kCard`/`_kBorder`/`_kGrid`/`_kSec`/`_kSec2`/`_kGold`-style constants are redefined at the top of **8 files** instead of using `AppTheme`/widget tokens:

- `lib/screens/health/blood_pressure_screen.dart`
- `lib/screens/health/blood_oxygen_screen.dart`
- `lib/screens/health/heart_rate_screen.dart`
- `lib/screens/health/hrv_screen.dart`
- `lib/screens/health/pressure_screen.dart`
- `lib/screens/health/sleep_screen.dart`
- `lib/screens/health/temperature_screen.dart`
- `lib/screens/home/home_screen.dart`

**Impact:** theme changes in `app_theme.dart` don't propagate to these screens; colors/radius/padding drift (see 3.5). Direct violation of "reuse existing cards" (CLAUDE.md) and DESIGN.md's consistency rule.

## 3.2 Duplicate gold tokens — [MED] (confirmed)

`lib/theme/app_theme.dart`:
- `gold = Color(0xFFC9A86E)`
- `goldLight = Color(0xFFC9A86E)`
- `base = Color(0xFFC9A86E)`
- `goldAccent = Color(0xFFC9A86E)`

Four names, one value. DESIGN.md mandates a single primary accent (#C9A86E). The tokens themselves match DESIGN.md — the problem is API clutter that invites "change one, not all" bugs. Collapse to `gold` + `goldBorder`.

## 3.3 Hardcoded whites / saturated colors in widgets — [MED] (confirmed)

`lib/widgets/fall_prediction/explainable_ai_dashboard.dart:38,75` — `Colors.white` text; `:67,69` `Colors.white.withAlpha(...)`.
Per-screen re-spelled card colors (e.g. `0xFF141414`-style literals in home_screen) diverge from `AppTheme.card = 0xFF111111` (confirmed in app_theme.dart).

## 3.4 Spacing/padding/radius drift vs DESIGN.md — [MED] (confirmed)

DESIGN.md: padding **16px**, radius **20px**. Measured in `blood_pressure_screen.dart`:
- Padding: `16` ✓ (`:616`), but also `14` (`:838`), `12` (`:1085`), `14` (`:1193`).
- Radius: `20` ✓ (`:681,:841`), but also `16` (`:896,:1156`), `14` (`:1088`).

No shared spacing constants exist (no `AppTheme.gap`/`kPad`); `EdgeInsets.all(12/14/16)` scattered across widgets and screens. Users see uneven alignment between screens.

## 3.5 System UI / safe-area handling — [MED] (verify per screen)

Screens use a mix of `SafeArea` vs manual `MediaQuery.paddingOf(context).top`; home_screen's edge-to-edge glass background must respect status-bar insets. Verify each top-level screen (home, health, settings) handles insets identically.

## 3.6 StatCard "know more >" is a dead affordance — [LOW] (confirmed)

`lib/widgets/stat_card.dart:37` renders `'know more >'` as plain text — **no `onTap`/`Navigator` anywhere** in the file. Implies navigation that doesn't exist. Either wire it or remove it.

## 3.7 "AI Reasoning" label overstates a rules engine — [MED] (see 02.6)

`explainable_ai_dashboard.dart` presents a deterministic weight-based rules engine as "AI Reasoning" with a `psychology` icon. In a health app this overstates capability.

## 3.8 `home_screen.dart` is a 3,692-line monolith — [MED] (confirmed)

Metrics, charts, headers, and lists are inlined with local constants instead of `lib/widgets/*`. Consequences: duplicated BP staging logic (01.1), duplicated tokens (3.1), huge diffs, no reuse.

## 3.9 Empty-state differences — [MED]

Some screens show "0"/empty when the provider has no data, others render blank sections — inconsistent "no data yet" treatment (plus no distinction between "no ring data" vs "integration failure", see 01.5).

## 3.10 Consistent with DESIGN.md (confirmed good)

- Glassmorphism backdrop blur ~28px is used in `glass_card.dart`.
- Radius 20 used for main cards in several screens.
- Metric color palette in `app_theme.dart` matches DESIGN.md metric colors (hrColor/bpColor/spo2Color/stepsColor/etc.).

---

## Token drift summary

| Token | `app_theme.dart` | Screens re-define |
|---|---|---|
| card background | `0xFF111111` (card) / `0xFF1A1A1A` (card2) | home_screen + health screens literals (e.g. `0xFF141414`) |
| gold | `gold`/`goldLight`/`base`/`goldAccent` = `0xFFC9A86E` | `_kGold`-style copies |
| border | `div = 0xFF242424` | `_kBorder` |
| spacing | none centralized | `12/14/16/20` scattered |
| radius | none centralized | `14/16/20` mixed |

---

## Status (updated 2026-08-07)

| Item | Status | Notes |
|---|---|---|
| 3.1 Health screens re-define tokens | FIXED | `_kCard`/`_kBorder`/`_kSec2` now derive from `AppTheme.card`/`AppTheme.div`/`AppTheme.textSec` in all 8 screens AND in shared `glass_card.dart` (`kCard`/`kBorder`/`kSec2`); theme changes now propagate. `_kSec`/`_kGrid` kept as local literals (no AppTheme counterpart). |
| 3.2 Duplicate gold tokens | FIXED | `goldLight`, `base`, `goldAccent` removed; single `gold` + `goldBorder` remain. Usages re-pointed in chat_screen (10), insights_header (2), ota_screen (1), home_screen (2). |
| 3.3 Hardcoded whites | FIXED | `explainable_ai_dashboard.dart` text colors routed to `AppTheme.textPrimary` (identical value). White-alpha glass overlays (_kCardBg etc.) kept — they are the DESIGN.md glass style layer. |
| 3.4 Spacing/radius drift | PARTIAL | Added shared tokens `AppTheme.kPad` (16) + `AppTheme.kRadiusCard` (20) and wired the shared `GlassCard` to them (padding/radius now token-driven; GlassCard radius 16 -> 20, matching DESIGN.md "every card" radius). Residual 12/14px paddings and 14/16px radii in per-screen list rows/tiles remain as documented debt (not DESIGN "cards"). |
| 3.5 Safe-area handling | VERIFIED | All top-level screens wrap bodies in SafeArea (home:819, main_shell:344, settings:101/225, records, sheets, workouts, auth); health detail screens use Scaffold+AppBar which owns the insets. Consistent — no change needed. |
| 3.6 StatCard dead affordance | FIXED | Removed `onKnowMore` field and the `'know more >'` render block (no production caller ever supplied the callback). Widget test updated to assert the affordance is gone. |
| 3.7 "AI Reasoning" label | ALREADY HONEST | Dashboard already renders "Risk Reasoning" (02.6); text now token-coloured via 3.3. |
| 3.8 home_screen monolith | DEFERRED | 3,700-line extraction into lib/widgets is a structural refactor with visual-QA risk; tracked separately, not done in this pass. |
| 3.9 Empty-state differences | DEFERRED | Needs a product decision on "no ring data" vs "integration failure" copy per screen; not a mechanical fix. |
| 3.10 Consistent with DESIGN.md | CONFIRMED GOOD | Metric palette + card radius align with DESIGN.md; no action. |

Verification: `dart analyze lib test` -> "No issues found!" | `flutter test` -> 123 pass (was 88/88 on 2026-08-07).