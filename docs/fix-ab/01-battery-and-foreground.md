# 01 — Battery Prompt + Foreground Service + Non-Foreground Fallback

## Problem

`app_incidents_rows.csv` shows ~34 rows `android_native:process_relaunch_scheduled` with `message=main:ForegroundServiceDidNotStartInTimeException` (e.g. 2026-08-07 18:54:17Z, 19:05:12Z burst). Foreground service dies, auto cycle stops.

## Current State

* `android/app/src/main/AndroidManifest.xml:29-37` declares `FOREGROUND_SERVICE`, `CONNECTED_DEVICE`, `DATA_SYNC`, `HEALTH`, `POST_NOTIFICATIONS`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS:41` (declared, never checked via `isIgnoringBatteryOptimizations`).
* `android/app/src/main/kotlin/com/sundr/myapp/BleConnectionService.kt:149-170` `onCreate` calls `startForeground(NOTIF_ID, notif)` in try/catch, then `MeasurementLoopManager.start:177`. Catches generic `Exception` but not `ForegroundServiceStartNotAllowedException` (API 31 background-start restriction). `onStartCommand:187` returns `START_STICKY`.
* `lib/main.dart:45-61` bulk `.request()` includes `Permission.notification:52` but ignores result; `await _bleChannel.invokeMethod('startForegroundService'):57` swallows `FGS_DENIED`.
* No `WorkManager`/`JobScheduler` (`grep WorkManager → 0`). No `FOREGROUND_SERVICE_SHORT_SERVICE`.

## Implementation (partially landed — status 2026-09-19)

> Landed: `isIgnoringBatteryOptimizations` / `requestIgnoreBatteryOptimizations` channels + Home battery `GlassCard` (see `BlePlugin.kt`, `home_screen.dart`). **Proposed, not landed:** `ShortSyncService`, `WorkScheduler`/`MeasurementWorker.kt`, `enqueueWorkManagerFallback` — zero hits in `android/` and no `SHORT_SERVICE` in the manifest. The doc below is the proposal.

### Manifest
* Add `<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SHORT_SERVICE"/>`.
* Add `<service android:name=".ShortSyncService" android:foregroundServiceType="shortService" android:exported="false"/>`.

### Native `BleConnectionService`
* Keep `connectedDevice|dataSync` primary. In `onCreate`, keep 5s `startForeground` contract (`154-157` comment). On `ForegroundServiceStartNotAllowedException`, call `WorkScheduler.enqueuePeriodic(context)` and return (do not crash).
* Add `WorkScheduler` object + `MeasurementWorker.kt` (`androidx.work:work-runtime-ktx:2.9` to `build.gradle.kts:92`): `CoroutineWorker` checking `MeasurementConfig.isMasterEnabled() && prefs flutter.user_logged_in && BleSdkLifecycle.isConnected()`, then single `walkSequence` subset (STEPS→HR→SpO2) + `SupabaseSyncManager.maybePush()`. Periodic 15m + expedited 1-shot.

### Dart `main.dart:45`
* Split `Permission.notification` out: `if denied → request → if permanentlyDenied → openAppSettings()`.
* After bulk request, query `isIgnoringBatteryOptimizations` channel; if false && loggedIn, set flag for `HomeScreen` battery `GlassCard`.
* Wrap `startForegroundService` in `try on PlatformException (FGS_START_NOT_ALLOWED) → enqueueWorkManagerFallback` + show `GlassCard`: "Background tracking running in battery-saving mode (15min). Tap to enable full real-time sync."

### Battery GlassCard (`DESIGN.md:153-183`, `glass_card.dart:13`)
* `GlassCard(margin horizontal 16, padding 16)`, orb amber `#FBBF24` (`app_theme.dart:30`), icon `battery_alert_rounded 36px` in `glassButton 0x08FFFFFF`, title 14px w500 white 0.95 "Background tracking may be restricted", body 12px textSec, CTAs `Allow` (gold `#C9A86E`) → `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` + `Not now` snooze 7d (`battery_prompt_dismissed_until`).
* Show above `ALL METRICS` sliver (`HomeScreen:694`), once per 7d, only if `loggedIn && isMasterEnabled`.

### Battery channel (`BlePlugin.kt:375`)
* Add `isIgnoringBatteryOptimizations` / `requestIgnoreBatteryOptimizations` via `PowerManager`, plus `enqueueWorkManagerFallback`.

## Verification
* `adb shell dumpsys activity services | grep BleConnectionService`, `logcat -s BleConnectionService:D MeasurementLoop:D SdkGuard:D`.
* `app_incidents` `process_relaunch_scheduled` drops 34/week → <2.
