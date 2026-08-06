# 07 — Testing, CI & Release Readiness

## 7.1 Test coverage — essentially zero — [HIGH]

- Only test file: `test/widget_test.dart` (7 lines) — "Placeholder — full app requires BLE hardware". It does nothing.
- `flutter test --no-pub` passes instantly (verified).
- `flutter analyze --no-pub` → "No issues found (5.2s)" (verified) — static analysis is clean but catches only compile-level issues; none of the logic bugs in 01.

**Priority test list (all pure-Dart, testable without hardware):**
1. BP staging classifier (01.1) — currently wrong; extract to a pure function and test boundaries (139/89 vs 140/90 vs 139/95 vs 180/120).
2. Fall-prediction reasoning chain (weights/classification).
3. Womens-health prediction thresholds.
4. `SupabaseService` map→row mapping (mock client).
5. Dart `LocalVitalsService` round-trip.
6. `BleProvider` state transitions (channel events → provider state).

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