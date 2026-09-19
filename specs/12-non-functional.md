# 12 — Non-Functional Requirements

| Field | Value |
|-------|-------|
| **Status** | Mixed — requirements for release readiness |
| **Build baseline** | `com.medxai.sundr`, Flutter 3.47.2 / Dart 3.13.2, AGP 9.3.1, Kotlin `2.4.10`, KSP `2.3.11` line, `android.builtInKotlin=false` (pinned until KGP tracker green) |

---

## 1. Platforms

| ID | Requirement |
|----|-------------|
| NFR-01 | **Primary:** Android phone, `minSdk 26`, target/compile per project Gradle (`targetSdk` 37 / `compileSdk` 36 as configured — CRIT: must become `compileSdk >= targetSdk`, i.e. `compileSdk = 37` since SDK 37 is stable as of 2026, or `targetSdk = 36`; clean builds otherwise fail). |
| NFR-02 | Real BLE features require physical device with Bluetooth. |
| NFR-03 | iOS/desktop folders may exist for Flutter tooling; **not** release targets for ring features unless explicitly staffed. |
| NFR-04 | Kotlin/Java 17 toolchain for Android module (`kotlin { compilerOptions { jvmTarget = JVM_17 } }`). |
| NFR-05 | `ndkVersion = "28.2.13676358"` pinned — must be installed on CI/dev images; harmless if no native compilation, but missing NDK fails builds. |
| NFR-06 | Package consistency: `namespace = applicationId = com.medxai.sundr` (`build.gradle.kts:11,21,32`), manifest `package="com.medxai.sundr"`, `.QRingApplication` / `.MainActivity`, all Kotlin under `com/medxai/sundr/` — no `com.example` remnants. |
| NFR-07 | Channel parity Dart↔Kotlin exact: `com.medxai.sundr/ble`, `com.medxai.sundr/ble_events`, `com.medxai.sundr/phone_mode` (`lib/config.dart:20-23` ↔ `MainActivity.kt`); no case/format drift. |
| NFR-08 | Add `android/app/src/main/res/values/strings.xml` with `<string name="app_name">Sundr</string>` and reference `@string/app_name` (today only `styles.xml` exists and the manifest hardcodes `android:label="SUNDR"` — untranslatable, lint warnings, future `@string/app_name` refs break). |

---

## 2. Performance & battery

| ID | Requirement |
|----|-------------|
| NFR-10 | Foreground services must show ongoing notifications meeting Android policy. |
| NFR-11 | Measurement loop interval must balance data density vs ring battery; production default should not remain at aggressive test cooldown without sign-off. |
| NFR-12 | Continuous phone accel for fall detection: measure multi-hour battery delta vs baseline before marketing “always on safety”. |
| NFR-13 | UI should remain responsive during manual measurements (loading states; timeouts 8–90s by vital). |
| NFR-14 | Home and detail screens should render last-known data instantly from memory/Room without waiting for network. |
| NFR-15 | Adaptive measurement timeouts: per-vital rolling average (last 5) → `max(avg × 1.5, 15 s)` (`MIN_TIMEOUT_MS = 15_000`, `TIMEOUT_HEADROOM_FACTOR = 1.5`, `ROLLING_WINDOW = 5`), ceilings 60 s (HR/SpO2/Stress/BP) / 90 s (HRV/Temp); BLE-active ~7 min → ~2 min per cycle (60–80% cut). |
| NFR-16 | Adaptive cooldown: FAST 3 min (`FAST_COOLDOWN_MS = 180_000`) on anomaly → SLOW 15 min (`SLOW_COOLDOWN_MS = 900_000`) after `NORMALCY_CONFIRM_CYCLES = 2` consecutive normal `FallRiskAnalyzer.currentTier()` cycles; any anomaly resets to 3 min. BLE duty ~70% → ~15–30%. |
| NFR-17 | `BleConnectionService` poll: stable-connected (`connected && wasConnected`) 30 s (was 8 s); fresh-connect 8 s; `SdkGuard.isOpen()` 30 s; disconnected backoff `BACKOFF_STEPS_MS` 8 s → 15 s → 30 s → 60 s → 120 s. CPU wake-ups ~10,800/day → ~2,700/day (−75%). |
| NFR-18 | Provider leak fixes are permanent: `WorkoutProvider.dispose()` sets `_isWorkoutActive = false` (kills 4 s `hrLoop` / 2 s `stepsLoop` fire-and-forget loops); `PrayerSessionProvider.dispose()` cancels the 1 s timer + `stopWorkout()` + restores `setCycleCooldownMs(180000)`. |
| NFR-19 | FGS target: `app_incidents` `process_relaunch_scheduled` (`ForegroundServiceDidNotStartInTimeException`, 34 rows/week) drops to <2/week; `isIgnoringBatteryOptimizations` channel + battery GlassCard landed; `ShortSyncService`/`WorkScheduler` 15-min fallback proposed (see BLE-32). |

---

## 3. Reliability

| ID | Requirement |
|----|-------------|
| NFR-20 | BLE reconnect after transient disconnect without user re-pairing when bonded. |
| NFR-21 | BootReceiver restores monitoring path after reboot when user still logged in. |
| NFR-22 | Native SDK calls always race a timeout so Flutter Futures cannot hang forever. |
| NFR-23 | Workout and measurement coordinator prevent concurrent SDK ownership bugs. |
| NFR-24 | Incident reporting (`app_incidents` / `IncidentService`) captures uncaught Flutter/native errors when possible. |
| NFR-25 | Global error handlers → `ErrorWidget.builder` (`lib/main.dart:143`) + `app_incidents` with PII scrubbing (phone/e-mail/JWT/`Bearer` stripped), `app_env` marker (`production`/`development`, `APP_ENV` override), per-source rate-limit 10/min, identical-report dedupe 60 s, payload caps. `app_incidents` permits anon INSERT by design (pre-login crashes; no read policy so rows unreadable by others); server-side insert rate-limit (security-definer RPC / trigger) is future hardening. |
| NFR-26 | No empty-`catch` silence on load-bearing paths (`ble_provider.dart` and services): at minimum log + expose a "last error" state instead of `catch (_) {}` zeros (ring-history hooks are the sanctioned silent exception — expected-offline stays silent, no incidents). |
| NFR-27 | Dual local-DB authority is explicit: native Room (`qring_local.db`) is the vitals authority; Dart `local_vitals_service.dart` (sqflite) round-trip is tested (`local_vitals_service_test.dart`) — confirm per-metric authority to avoid divergence. |

---

## 4. Security & privacy

| ID | Requirement |
|----|-------------|
| NFR-30 | Health data treated as sensitive; RLS on all user tables. |
| NFR-31 | No service-role keys in the mobile binary. |
| NFR-32 | Transport HTTPS for Supabase and chat API. |
| NFR-33 | Account deletion and logout paths implemented before public store release. |
| NFR-34 | Privacy Policy and Terms screens accessible from settings. |
| NFR-35 | Fall prediction/alert copy must not present the app as a certified medical device unless certified. |
| NFR-36 | Supabase URL + anon key committed is a documented decision (`lib/config.dart:4-13`, `String.fromEnvironment` fallback): publishable only because RLS gates every table (versioned in `20260806000000_missing_tables.sql`: owner policies `auth.uid() = user_id` / `= id` on all 14 formerly-unversioned tables incl. `user_profiles`, `user_bp`, `user_emergency_contacts`, idempotent). One-time live-dashboard verification still required: `select relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and relname like 'user_%' and not relrowsecurity;`. |
| NFR-37 | Fake emergency contacts removed (both screens; contacts start empty with warning). Native guards: `EmergencySmsSender.schedule()` refuses countdown until ≥1 contact with a digit (`EmergencySmsSender.kt:88-105`); `EmergencyAutoCaller` no-ops on empty list. Auto-SMS body is static `DEFAULT_MESSAGE` (`:49-50`, no vitals/URLs), `SEND_COOLDOWN_MS = 15 min` (`:47,74-79`), 30 s cancellable countdown (`EmergencySmsCancelReceiver`, restored across process death `restoreIfNeeded :179-201`), `SEND_SMS` checked (`:234-245`). |
| NFR-38 | `SharedPreferences` plaintext is acceptable: keys are plain, no vitals stored in prefs (vitals live in native Room). No `usesCleartextTraffic` in any manifest. |

---

## 5. Permissions (Android)

Removed 2026-08-07 (no consumer anywhere in Dart or Kotlin) — must stay removed:

`READ_CALL_LOG`, `READ_SMS`, `RECEIVE_SMS`, `READ_CONTACTS` (contacts manually entered → Room; nothing reads the address book), `ACCESS_BACKGROUND_LOCATION` (no background-location code), `POST_PROMOTED_NOTIFICATIONS`, `READ/WRITE_EXTERNAL_STORAGE` + `requestLegacyExternalStorage` (OTA via Storage Access Framework; downloads to app-private storage).

Remaining declared set — every entry justified by a consumer:

| Permission | Consumer | Notes |
|---|---|---|
| `BLUETOOTH`, `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN` (neverForLocation), `BLUETOOTH_ADVERTISE`, `BLUETOOTH_ADMIN` | BLE scan/connect | `uses-feature bluetooth_le required=true` |
| `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` | BLE scanning on Android < 12 (`permission_handler` request `main.dart:43-52`); phone GPS traces | Foreground only |
| `POST_NOTIFICATIONS` | FGS + alerts | Split-request flow (`main.dart:45-61`) |
| `ACTIVITY_RECOGNITION` | Step sync (`health_connect_service.dart:198-203`) | — |
| `SEND_SMS` | `EmergencySmsSender.kt` (fall alert SMS) | Cooldown + cancel + guards (NFR-37) |
| `CALL_PHONE`, `READ_PHONE_STATE` | `EmergencyAutoCaller.kt` (+ `BlePlugin.kt:2989`) | Behind feature flag, default OFF (FD-33) |
| `RECORD_AUDIO` | `speech_to_text` AI-assist voice sheet (`lib/screens/assist/voice_listening_sheet.dart`) | Has consumer — keep, justify in Play review |
| `CAMERA` | Ring camera feature | — |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_CONNECTED_DEVICE`/`DATA_SYNC`/`HEALTH` (+ proposed `SHORT_SERVICE`) | `BleConnectionService` / `ShortSyncService` | — |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Battery GlassCard flow (`:41`, `PowerManager` channels) | Declared; now actually checked |
| `ACCESS_NOTIFICATION_POLICY` | DND / phone-mode control (native) | — |
| `RECEIVE_BOOT_COMPLETED` | `BootReceiver` | — |
| Health Connect full READ/WRITE set | `lib/services/health_connect_service.dart` (per-metric READ/WRITE) | QRing ref declares `WRITE_STEPS`, `WRITE_HEART_RATE`, `WRITE_SLEEP`, `WRITE_TOTAL_CALORIES_BURNED`; app adds SpO₂/HRV/BP/temperature |
| `VIBRATE`, `WAKE_LOCK`, `RECEIVE_USER_PRESENT`, `INTERNET`/`ACCESS_NETWORK_STATE`/`ACCESS_WIFI_STATE` | System / network | Standard |

| ID | Requirement |
|----|-------------|
| NFR-40 | Deny paths must degrade gracefully (feature off, not crash). |
| NFR-41 | Background protection guidance for OEMs that kill services. |
| NFR-42 | High-risk surface (`SEND_SMS`/`CALL_PHONE`/`RECORD_AUDIO`/location) carries per-permission Play-review justification; `RECORD_AUDIO` keeps its voice-sheet consumer or is removed. Emergency auto-call stays behind a feature flag, default OFF, verified with REAL contacts only. |

---

## 6. Accessibility & UX quality

| ID | Requirement |
|----|-------------|
| NFR-50 | Permanent dark theme only; contrast sufficient for primary metrics (white ~0.95 on `#050505`). |
| NFR-51 | Follow `DESIGN.md` for any UI change. |
| NFR-52 | Critical actions (delete account, OTA, end workout) use confirmation dialogs. |
| NFR-53 | No dead affordances: every tappable affordance has a handler (e.g. `StatCard` "know more >" `stat_card.dart:37` fixed/removed); every `Navigator.pushNamed` target exists. "AI" labels describe deterministic engines honestly (rename or disclose, e.g. `explainable_ai_dashboard.dart`). |
| NFR-54 | Home composition reuses `lib/widgets/*` card components and `AppTheme` tokens (no 3,692-line `home_screen.dart` monolith growth; no per-screen `_kCard`/`_kBorder`/`_kGrid` token copies); golden/visual tests guard token drift. |

---

## 7. Internationalization

| ID | Requirement |
|----|-------------|
| NFR-60 | Initial release may be single-language (English) unless product expands. |
| NFR-61 | Units: support metric profile data (cm/kg); unit prefs service exists for future expansion. |
| NFR-62 | `strings.xml` (`@string/app_name`) unblocks future localization of the app label (see NFR-08). |

---

## 8. Testing & release

| ID | Requirement |
|----|-------------|
| NFR-70 | Automated suite is 123 tests / 15 files (fall engine V2, adaptive-weight Σ=1, BP staging, Layer-3 motion sources, womens-health, widget cards). Before release, still add: `SupabaseService` map→row mapping, `BleProvider` state transitions, WH clinical-baseline review. |
| NFR-71 | Manual test matrix: pair, loop vitals, manual measure, workout, fall simulate, offline today, sync after reconnect. |
| NFR-72 | Release builds must use a production signing keystore (not debug). |
| NFR-73 | R8/Proguard keep rules for Room/Gson models remain valid. |
| NFR-74 | Vendor AAR present in `android/app/libs/` for all CI builds. |
| NFR-75 | CI/release workflow under `.github/workflows/` if used must build signed artifact. |
| NFR-76 | Latest-by-design dependency pins (2026-09-02, `flutter pub outdated` direct = all up-to-date; transitive only `material_color_utilities 0.13.0→0.13.1`, `cli_util 0.4.2→0.6.0`, `test_api 0.7.12→0.7.13` constrained by Flutter SDK): `firebase_core ^4.14.0` (was `^3.0.0`), `firebase_messaging ^16.6.0` (was `^15.0.0`), `geolocator ^14.0.3` (was `^13.0.1`), `health ^13.3.2` (was `^13.3.1`), `package_info_plus ^10.2.1` (was `^9.0.1`), `permission_handler ^13.0.1` (was `11.4.0` exact), `share_plus ^13.3.0` (was `10.1.4` exact), `device_info_plus 13.2.0` (was 12.4.0), `speech_to_text ^7.1.0 → 7.4.0` resolved, `permission_handler_android 12.1.0→14.0.0`, `_flutterfire_internals 1.3.59→1.3.77`, `win32 5.15→6.4` (32 deps changed, `pubspec.lock` committed). Breaking APIs fixed: `Share.share` → `SharePlus.instance.share(ShareParams(...))` (`home_screen.dart:932`, `friends_screen.dart:58`, `workout_detail_screen.dart:156`, `screenshot_share.dart:24`). `flutter analyze` → 2 info only (`sleep_screen:605,649 curly_braces` pre-existing); `flutter build appbundle --release` → √ Built 66.8 MB in 327.3 s. Direct deps auto-float weekly (`flutter pub outdated`). |
| NFR-77 | Built-in Kotlin: `android.builtInKotlin=false` stays until the KGP tracker is all-green; `android/app/build.gradle.kts` keeps `id("org.jetbrains.kotlin.android")` + `id("com.google.devtools.ksp")` (KSP stays for Room) until then. Tracker (2026-09-02): clean — `device_info_plus 13.2.0`, `package_info_plus 10.2.1`, `share_plus 13.3.0`, `geolocator 14.0.3`, `permission_handler 13.0.1`; still warning — `firebase_core 4.14.0` (likely transitive `_flutterfire_internals`), `health 13.3.2` (`android/build.gradle:25 kotlin-android`, blocks `builtInKotlin=true`), `speech_to_text 7.4.0` (`android/build.gradle:12 kotlin-android`, `compileSdk` missing for AGP 9). File upstream issues per the Flutter built-in-Kotlin template when ready; setting `builtInKotlin=true` early fails the build on `health-13.3.2`. `health_connector 3.10.0` (built-in-Kotlin clean) is the evaluated escape hatch — reverted spike, needs full `health_connect_service_v2.dart` port (see SET-20). |
| NFR-78 | CI: none exists (no `.github/workflows` / `gitlab-ci.yml` / `azure-pipelines.yml`; nothing runs `flutter analyze`/`flutter test` on PR, nothing builds/signs artifacts). Required before release: analyze + unit tests + signed build with `key.properties` injected as secret; release build FAILS LOUDLY when `key.properties` is absent instead of falling back to debug (`build.gradle.kts:53-60` fallback removed). |
| NFR-79 | On-device smoke matrix (Android 13/14/15): BLE scan/connect with a real ring (all vitals paths); OTA with a real firmware file (Dart→file→`DfuHandle` link untested); emergency SMS/call with REAL contacts and auto-call ON (countdown/cancel UX + product approval); permissions request/denial/background (FGS) flows; Health Connect on Android 14+; account deletion end-to-end. |
| NFR-80 | Release checklist (all must be checked): `compileSdk = 37` (or `targetSdk = 36`) · CI green · debug-signing fallback removed · `strings.xml` + `@string/app_name` · migrations for all tables + `delete_user_account` fixed · BP/fall/womens unit tests (+ `SupabaseService` mapping, `BleProvider` transitions, WH clinical review) · emergency auto-call flagged OFF · no fake-contact seeding · permissions trimmed (NFR-42) · KSP `2.3.x`↔Kotlin `2.4.10` pairing verified (if `KSP version … does not match Kotlin` → align per ksp docs). |

---

## 9. Observability

| ID | Requirement |
|----|-------------|
| NFR-90 | Fall risk and fall events logged for offline analysis. (Was NFR-80.) |
| NFR-91 | App incidents table for crash triage. (Was NFR-81.) |
| NFR-92 | Avoid logging full PII (tokens, precise address books) to incidents. (Was NFR-82.) |
| NFR-93 | Log tags `MeasurementLoop` / `BleConnectionService` / `FallRiskAnalyzer` / `SdkGuard` carry timeout, cooldown (`FAST_COOLDOWN`/`SLOW_COOLDOWN`), response-time, tier-change, and poll-interval decisions for `adb logcat -s` triage (see changes-18 §5). |

---

## 10. Compliance posture (product statements)

Until regulatory clearance:

- Market as a **wellness / lifestyle** companion with safety *assistance*, not diagnostic equipment.  
- Fall features are **aids**, not substitutes for medical care or dedicated PERS devices.  

---

## 11. Related

- `DESIGN.md`  
- `FALL_DETECTION_STATUS.md`  
- [00-product-overview.md](./00-product-overview.md)
- `docs/archive/eval/04-NATIVE-ANDROID-BRIDGE.md`, `06-CODE-QUALITY-MAINTENANCE.md`, `07-TESTING-CI-RELEASE.md`, `08-SECURITY-PRIVACY-PERMISSIONS.md`
- `docs/bugs-fixes/01-dependency-upgrade-plan.md` … `07-health-connector-spike.md`
- `docs/changes-18/battery-analysis.md`, `implementation-details.md`, `summary.md`
