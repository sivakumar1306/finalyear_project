# Executive Summary — Vital Monitoring (QRing / SUNDR) Full-Codebase Evaluation

> Evaluated: 2026-08-06 · Repository: `Vital_Monitoring` · Stack: Flutter (Dart) + Kotlin (Android) + Supabase
> Method: manual review of `lib/` (all providers/services/screens/models/widgets), `android/` (Kotlin + Gradle + manifest), `supabase/` (migrations), `specs/`, `test/`; plus `flutter analyze --no-pub` and `flutter test --no-pub`.
> Refs like `lib/…:N` / `android/…:N` point at file:line.

## Verdict

A large, feature-rich health-monitoring app whose **Dart and Kotlin layers are both substantial and real** — this is not a UI shell. The BLE stack talks to an actual ring SDK (Oudmon `com.oudmon.ble.base`), Room stores readings locally, and Supabase sync + fall detection + emergency SMS/call are implemented. Compilation is clean (`flutter analyze` → "No issues found").

However, the app is **not release-ready**:

- **7 native methods are hardcoded stubs** that return success without doing anything (`BlePlugin.kt:318-334`).
- **Two screens auto-seed FAKE emergency contacts** (9999999999 / +91 000 000 0000) that the emergency SMS/call path can actually dial.
- **A confirmed medical-classification bug**: BP staging uses `||` instead of `&&` — Stage-1/2 labels are wrong for many readings.
- **The Supabase migration set does not match the code**: ~14 tables the app reads/writes are never created by migrations; only 6 are. Fresh environments 404 on every sync.
- **`compileSdk 36 < targetSdk 37`** — release build failure/warning; also `ErrorWidget.builder` swallows all UI errors.
- **The only test is a placeholder.** *(Snapshot 2026-08-06 — stale: suite is 123 tests across 15 files as of 2026-09-19; see 07.1.)*

---

## Severity Legend
- **[CRIT]** — silent wrong health data / real phone calls to fake numbers / reproducible build failure.
- **[HIGH]** — feature silently does nothing, or whole workflow blocked.
- **[MED]** — inconsistency, dead UX, duplicated code, operational risk.
- **[LOW]** — cosmetic, maintainability.

---

## Top findings (quick scan)

| # | Sev | Finding | Where |
|---|-----|---------|-------|
| 1 | CRIT | **BP staging misclassifies** — `if (sbp < 140 \|\| dbp < 90) return 'Stage 1'` (should be `&&`); e.g. 139/95 → "Stage 1" instead of "Stage 2". Duplicated in 2 files. | `lib/screens/health/blood_pressure_screen.dart:44,52` · `lib/screens/home/home_screen.dart:3044,3052` |
| 2 | CRIT | **Fake emergency contacts auto-seeded** when contact list is empty — `9999999999` and `+91 000 000 0000`. Emergency SMS/call path is real and would dial them. | `lib/screens/settings/fall_detection_screen.dart:107-114` · `lib/screens/settings/profile_edit_screen.dart:89-93` |
| 3 | CRIT | **Supabase migrations incomplete**: only `user_hr_readings`, `user_spo2_readings`, `user_hrv_readings`, `user_steps_snapshots`, `firmware_updates`, `app_incidents` are created. The app also uses `user_profiles`, `user_steps`, `user_hr`, `user_spo2`, `user_bp`, `user_stress`, `user_hrv`, `user_temp`, `user_workouts`, `user_sleep`, `user_cycles`, `user_symptoms`, `user_emergency_contacts`, `workouts`. | `supabase/migrations/*` vs `lib/services/supabase_service.dart:110-865` |
| 4 | CRIT | **`compileSdk 36` < `targetSdk 37`** — illegal AGP config; stable release build fails. Also release signing falls back to **debug keystore** when `key.properties` absent. | `android/app/build.gradle.kts:22,33,53-60` |
| 5 | HIGH | **7 native stubs**: `getDisplaySettings`/`setDisplaySetting`/`getTargetAndProfile`/`setTargetAndProfile`/`getAdvancedSettings`/`setAdvancedSetting`/`sendNotification` return canned `"{}"`/`true`; ring settings UI claims "saved" with no effect. | `android/app/src/main/kotlin/com/medxai/sundr/BlePlugin.kt:318-334` |
| 6 | HIGH | **Demo/simulation methods schedule REAL SMS and can place REAL calls** (`simulateFallEvent`, `simulateFallPrediction`) — a "demo" button triggers the actual emergency pipeline including `EmergencySmsSender.schedule` and `EmergencyAutoCaller.placeIfEnabled`. | `BlePlugin.kt:2481-2566` · `lib/screens/settings/fall_detection_screen.dart:399-413` |
| 7 | HIGH | **Emergency auto-call shipped despite spec FD-33** ("No auto SMS/call in current release") — code exists and is enabled via settings; manifest declares `SEND_SMS`/`CALL_PHONE`. | `specs/05-fall-detection-safety.md:108` · `EmergencyAutoCaller.kt` |
| 8 | MED | **All UI errors silently swallowed** (`ErrorWidget.builder → SizedBox.shrink`), reported to `app_incidents` table — users see a blank screen; incidents spam production DB from dev/test. | `lib/main.dart:80-107,141-150` |
| 9 | MED | **No `strings.xml`** — app label `"SUNDR"` hardcoded in manifest; also a hardcoded `READ_CALL_LOG`/`RECORD_AUDIO`-style broad permission list (see 08). | `android/app/src/main/AndroidManifest.xml` |
| 10 | MED | **Design tokens duplicated per screen** (7 health screens + home each redefine `_kCard`/`_kBorder`/`_kGrid`/gold colors instead of `AppTheme`) — drift risk; `AppTheme` gold/goldLight/base/goldAccent are the same color. | `lib/screens/health/*` · `lib/screens/home/home_screen.dart` · `lib/theme/app_theme.dart` |
| 11 | MED | **Only test is a placeholder** (7-line smoke test); `flutter test` passes but verifies nothing. *(Snapshot 2026-08-06 — stale: 123 tests as of 2026-09-19.)* | `test/widget_test.dart` |

---

## Section index (this folder)

| File | Contents |
|------|----------|
| `00-EXECUTIVE-SUMMARY.md` | This overview + severity matrix. |
| `01-CONFIRMED-BUGS-LOGIC.md` | Logic/medical-classification bugs, crash paths. |
| `02-STUBS-PLACEHOLDERS-DEMO-DATA.md` | Native stubs, placeholder screens, demo-data paths. |
| `03-DESIGN-SYSTEM-UI-PADDING.md` | DESIGN.md compliance, token duplication, spacing/padding. |
| `04-NATIVE-ANDROID-BRIDGE.md` | Kotlin↔Flutter channels, build config, permissions. |
| `05-BACKEND-DATA-PERSISTENCE.md` | Supabase migration gaps, Room, sync, RLS. |
| `06-CODE-QUALITY-MAINTENANCE.md` | Monolith screens, duplication, error swallowing. |
| `07-TESTING-CI-RELEASE.md` | Test coverage, signing, SDK versions, checklist. |
| `08-SECURITY-PRIVACY-PERMISSIONS.md` | Permissions, fake contacts, incidents table, privacy. |

---

## What is in good shape (confirmed)
- BLE MethodChannel wiring: Dart names in `lib/config.dart:20-23` exactly match Kotlin (`com.medxai.sundr/ble`, `/ble_events`, `/phone_mode`).
- Native side implements real SDK calls for HR / BP / SpO2 / steps / sleep / HRV / stress / temperature / camera / phone control / DND / reminders / **OTA (DfuHandle)** — far from a shell.
- RLS exists for the 6 migrated tables; Room keeps readings locally; `proguard-rules.pro` has correct Room/Gson keep rules.
- `clearPersonalData` (logout wipe) is thorough: stops loops, drops DB, clears native prefs, cancels notifications.

## What is not an actual bug
- Hardcoded Supabase URL + anon key in `lib/config.dart` — publishable by design (RLS is the gate).
- `package`/`applicationId` = `com.medxai.sundr` consistent across Gradle, manifest, and Kotlin package (no leftover `com.example` files).