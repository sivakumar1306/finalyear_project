# 06 — Code Quality & Maintainability

## 6.1 `home_screen.dart` is a 3,692-line monolith — [MED] (confirmed)

`lib/screens/home/home_screen.dart` — every metric card, chart, header, and list is inlined with local constants instead of `lib/widgets/*`. Consequences:
- duplicated BP staging logic (01.1),
- duplicated design tokens (03.1),
- huge diffs, impractical review,
- no reuse of existing card widgets (violates CLAUDE.md).

**Recommendation:** split into `home/widgets/*` (MetricCard, ChartCard, etc.) reusing `AppTheme` + existing chart card widgets.

## 6.2 Per-screen helper duplication — [MED] (confirmed)

8 screens (7 health + home) each define their own `_kCard`/`_kBorder`/`_kGrid`/`_kSec`/gold constants and their own formatting helpers. Single source of truth would eliminate ~8 copies.

## 6.3 Empty `catch (_) {}` blocks hide failures — [HIGH]

`lib/providers/ble_provider.dart` (and several services) swallow platform exceptions. This is the mechanism that turns real failures into silent zeros (see 01.5). At minimum: log + expose a "last error" state for the UI.

## 6.4 Dead affordances — [LOW] (confirmed)

- `StatCard` "know more >" — no tap handler (`stat_card.dart:37`).
- Route references without targets — verify with grep on each `Navigator.pushNamed`.

## 6.5 "AI" claims vs rules engine — [MED]

`explainable_ai_dashboard.dart` labels a deterministic weight-based engine "AI Reasoning". Rename or disclose.

## 6.6 Service vs provider responsibilities — [LOW]

`lib/services/supabase_service.dart` (~900 lines) mixes persistence + policy. Split into per-domain repositories (`vitals_repository`, `profile_repository`, …) to mirror the models split.

## 6.7 Hard-coded heuristics — [MED]

- `lib/services/womens_health_prediction_service.dart` — thresholds like `temp > 55.0` on the normalized 0–100 scale (02.7). Document the scale or use real formulas.
- `lib/providers/fall_prediction/*` — reasoning assumes 100 = optimal baseline (01.10). Document.

## 6.8 Versioning — [LOW]

`versionCode = 1`, `versionName = "1.0.0"` (`build.gradle.kts:34-35`). Bump discipline needed, especially with OTA in the app.

## 6.9 Incident reporting coupling — [MED]

Global error handlers → `app_incidents` with no dev/prod filter, rate limit, or dedupe (05.4/08.4).

## 6.10 No golden/visual tests — [MED]

Design tokens drift uncaught (03.1) — golden tests would catch per-screen token redefinition.

## 6.11 Prayer schedule prefs "string" workaround — [LOW]

`lib/services/prayer_schedule_prefs.dart:4-7` documents a native `getInt` crash concern with no native consumer today. Keep the comment; confirm premise when native reads arrive (01.14).

## 6.12 Native Kotlin quality — [OK overall]

`BlePlugin.kt` (2,913 lines) is well-structured: explicit timeout runnables, `AtomicBoolean` guards against double-resolve, coordinator acquire/release for manual measurements, retry logic for bind/temperature sync. This is mature native code, not scaffolding.

## 6.13 Dual local-DB question — [HIGH] (see 05.5)

Dart `local_vitals_service.dart` (sqflite) vs native Room (`qring_local.db`). Two local stores for the same vitals — must confirm authority per metric to avoid divergence.

## 6.14 Test file was a placeholder at eval time (see 07.1) — ✅ superseded

~~`test/widget_test.dart` — "Placeholder — full app requires BLE hardware". The only test in the repo.~~ Stale (2026-08-06): suite is 123 tests / 15 files as of 2026-09-19.