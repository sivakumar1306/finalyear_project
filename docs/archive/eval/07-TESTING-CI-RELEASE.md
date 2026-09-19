# 07 — Testing, CI & Release Readiness

## 7.1 Test coverage — was essentially zero at eval time (2026-08-06); 123 tests as of 2026-09-19 — [MED]

- ~~Only test file: `test/widget_test.dart` (7 lines)~~ — stale: `test/` now holds 15 files / 123 tests, including `fall_prediction_test.dart` (engine V2 healthy-metrics), `adaptive_weight_engine_test.dart` (weight renormalization), `layer3_motion_sources_test.dart` (native fall-event parsing, 24h peak freshness, gait-proxy bounds), `bp_staging_test.dart`, and widget tests (`widget_test.dart` now asserts real cards, incl. the removed StatCard affordance).
- `flutter test` passes (verified 2026-09-19: all 123).
- `flutter analyze` → "No issues found" (verified) — static analysis is clean but catches only compile-level issues; none of the logic bugs in 01.

**Priority test list (all pure-Dart, testable without hardware)** — status 2026-09-19:
1. BP staging classifier (01.1) — ✅ done (`bp_staging_test.dart`; classifier now delegates to `HealthEngine`).
2. Fall-prediction reasoning chain (weights/classification) — ✅ done (`fall_prediction_test.dart`, `adaptive_weight_engine_test.dart`, `layer3_motion_sources_test.dart`).
3. Womens-health prediction thresholds — ✅ done (`womens_health_prediction_test.dart`).
4. `SupabaseService` map→row mapping (mock client) — open.
5. Dart `LocalVitalsService` round-trip — ✅ done (`local_vitals_service_test.dart`).
6. `BleProvider` state transitions (channel events → provider state) — open.

## 7.2 No golden/visual tests — [MED]

Design tokens drift uncaught (03) — golden tests would catch per-screen token redefinition.

## 7.3 CI — none found

No `.github/workflows`, `gitlab-ci.yml`, or `azure-pipelines.yml` in the repo. Nothing runs `flutter analyze`/`flutter test` on PR, and nothing builds/signs artifacts. Combined with 4.4 (debug-signing fallback), a release could ship uncaught.

## 7.4 Release signing fallback — [CRIT] (see 04.4)

Release builds degrade to the debug keystore when `key.properties` is absent (`build.gradle.kts:53-60`). CI must fail loudly instead.

## 7.5 `compileSdk 36` vs `targetSdk 37` — [CRIT] (see 04.3)

Must fix before any stable build.

## 7.6 On-device smoke matrix (Android 13/14/15)

- BLE scan/connect with a real ring (all vitals paths).
- OTA with a real firmware file (02.4 — Dart→file→DfuHandle link is untested).
- Emergency SMS/call with REAL contacts and auto-call ON — verify countdown/cancel UX (and confirm product approval, 01.2).
- Permissions: request flow, denial handling, background running (FGS), Health Connect on Android 14+.
- Account deletion end-to-end (05.10 — currently broken on migration-only DB).

## 7.7 Release checklist

- [ ] `compileSdk = 37` (or `targetSdk = 36`)
- [ ] CI with analyze + unit tests + build, key injected as secret
- [ ] Remove debug-signing fallback
- [ ] `strings.xml` + `@string/app_name`
- [ ] Migrations for all tables; `delete_user_account` fixed
- [ ] Unit tests for BP/fall/womens logic
- [ ] Emergency auto-call behind a feature flag, default OFF (spec FD-33)
- [ ] No fake contact seeding (01.3)
- [ ] Trim over-broad permissions (08.5)