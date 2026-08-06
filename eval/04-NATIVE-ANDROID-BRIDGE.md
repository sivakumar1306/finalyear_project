# 04 — Native Android / Flutter Bridge & Build Audit

> Verified by direct read of `android/app/build.gradle.kts`, `AndroidManifest.xml`, `MainActivity.kt`, `BlePlugin.kt`, `proguard-rules.pro`, and `lib/config.dart`.

## 4.1 Package consistency — OK (correction)

- Gradle: `namespace = applicationId = com.medxai.sundr` (`build.gradle.kts:11,21,32`).
- Manifest: `package="com.medxai.sundr"`; application `android:name=".QRingApplication"`; activity `android:name=".MainActivity"`.
- Kotlin sources: all under `com/medxai/sundr/` — **no leftover `com.example` files** (earlier concern invalid).

## 4.2 Channel wiring — MATCHES (correction)

| Channel | Dart (`lib/config.dart:20-23`) | Kotlin (`MainActivity.kt`) |
|---|---|---|
| BLE method | `com.medxai.sundr/ble` | `BLE_METHOD_CHANNEL` = `$PACKAGE_NAME/ble` ✓ |
| BLE events | `com.medxai.sundr/ble_events` | `BLE_EVENT_CHANNEL` ✓ |
| Phone mode | `com.medxai.sundr/phone_mode` | `PHONE_MODE_METHOD_CHANNEL` ✓ |

`MainActivity` wires them with proper `MethodChannel`/`EventChannel` registration. No case/format drift.

## 4.3 SDK version mismatch — CRIT (confirmed)

`android/app/build.gradle.kts`:
- Line 22: `compileSdk = 36`
- Line 33: `targetSdk = 37`

**AGP requirement: `compileSdk >= targetSdk`.** As-is, a clean build fails with "The targetSdk (37) is higher than compileSdk (36)". Fix: set `compileSdk = 37` (SDK 37 is stable as of 2026) or `targetSdk = 36`. Also bump `versionCode = 1` discipline (line 34).

## 4.4 Release signing falls back to DEBUG keystore — HIGH

`build.gradle.kts:53-60`: when `key.properties` is absent, `release` uses `signingConfigs.getByName("debug")`.

**Impact:** A release APK/AAB shipped without the key file is signed with the well-known debug key:
- cannot be updated in place later without key rollover (Play store rejects),
- defeats tamper evidence; anyone with the debug keystore can resign it.

**Fix:** fail the build when `key.properties` missing for release builds (CI should inject it as a secret).

## 4.5 NDK pinning — MED

`ndkVersion = "28.2.13676358"` (line 23) — if not installed on CI/dev machines, builds fail. `ndkVersion` is only needed if native code compiles; harmless otherwise, but pin to a version available in the build image.

## 4.6 R8/ProGuard — OK (confirmed)

`proguard-rules.pro` keeps `com.medxai.sundr.data.**` (Room/Gson reflection), Gson TypeToken, and `*Annotation*`/`Signature`. This is exactly what's needed for the `data/` entities serialized via Gson in `getReadings`/`getLatestReading`. Good.

## 4.7 Native stubs — HIGH (see 02.1)

`BlePlugin.kt:318-334`: `getDisplaySettings`, `setDisplaySetting`, `getTargetAndProfile`, `setTargetAndProfile`, `getAdvancedSettings`, `setAdvancedSetting`, `sendNotification` return canned values. Everything else is real SDK plumbing.

## 4.8 No `strings.xml` — MED

`android/app/src/main/res/values/` contains only `styles.xml` (values + values-night). App label `android:label="SUNDR"` is a hardcoded literal in the manifest. Consequences:
- untranslatable app label,
- AGP/lint warnings for the hardcoded string,
- any future `@string/app_name` reference breaks.

**Fix:** add `res/values/strings.xml` with `<string name="app_name">Sundr</string>` and reference `@string/app_name`.

## 4.9 Permission declarations — VERIFIED, over-broad (see 08)

Manifest declares (main): BLUETOOTH + CONNECT + SCAN (neverForLocation) + ADVERTISE + ADMIN; FINE/COARSE/BACKGROUND location; READ/WRITE external storage (write capped ≤28); INTERNET/network/wifi; **READ_CONTACTS, READ_PHONE_STATE, READ_CALL_LOG, RECEIVE_SMS, READ_SMS, SEND_SMS, RECORD_AUDIO, CALL_PHONE**; VIBRATE/WAKE_LOCK/RECEIVE_USER_PRESENT; FGS + CONNECTED_DEVICE + HEALTH; POST_NOTIFICATIONS + POST_PROMOTED_NOTIFICATIONS; BOOT_COMPLETED; battery-optimization ignore; notification-policy access; full Health Connect READ/WRITE set; ACTIVITY_RECOGNITION; `uses-feature bluetooth_le required=true`.

`lib/main.dart:22-32` requests: bluetooth, bluetoothScan, bluetoothConnect, bluetoothAdvertise, locationWhenInUse, notification, **sms, phone**.

**Impact:** High-risk permission surface for Play review (SMS/CALL_LOG/RECORD_AUDIO/background location need strong justifications). `RECORD_AUDIO` has no consumer in the codebase found. Trim to the minimal set or document each.

## 4.10 Application/entry classes — OK

- `QRingApplication` (SundrApplication.kt) is the Application class; `MainActivity.kt` registers channels and hosts `pendingFallPrediction` state.
- Boot receivers: `BootReceiver`, `SundrBluetoothReceiver`, `SundrSystemBluetoothReceiver` registered — Bluetooth/BOOT_COMPLETED wiring present.

## 4.11 Emergency call/sms native — real, permission-guarded

`EmergencyAutoCaller.kt`/`EmergencySmsSender.kt` are real implementations (countdown, cancel receiver, permission checks, call placement). Concerns are about product policy + fake contacts (01.2/01.3), not implementation quality.

---

## Checklist summary

| Item | Status |
|---|---|
| `compileSdk >= targetSdk` | ❌ 36 < 37 |
| Release signing = real key | ❌ falls back to debug |
| `strings.xml` | ❌ missing (label hardcoded) |
| Channel parity Dart↔Kotlin | ✅ exact match |
| `com.example` remnants | ✅ none |
| R8 keep rules | ✅ good |
| Permissions minimal & justified | ❌ over-broad (SMS/CALL_LOG/RECORD_AUDIO/bg-location) |
| NDK pinned to available version | ⚠️ verify |
| Boot/foreground services registered | ✅ |