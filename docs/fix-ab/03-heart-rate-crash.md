# 03 — Heart Rate Always Crashes

## Ranked Causes

* **H1 BUSY→TIMEOUT:** `MeasurementLoopManager:52 OWNER="loop"` + `POST_STOP_SETTLE 2s:51` + `PREEMPT 200ms:57` vs `BlePlugin:828 MANUAL_ACQUIRE_TIMEOUT 4000`. Loop holds lock for median agreement `measureHeartRate:229` (2 consecutive `abs≤12`, lower-median). Manual tap sets `manualRequestPending`, `watchForPreempt:217` yields but release delayed 2s → deadline expires → `BUSY:837` → retry → 8 fails → `SdkGuard.open 45s`.
* **H2 Double-reply:** `BlePlugin:994 postDelayed 60s TIMEOUT` not cancelled on `onDeviceDisconnected:673` → `result.success(null):980` then `result.error(TIMEOUT)` → `IllegalStateException: Reply already submitted` → process death, `CrashStore:77`.
* **H3 type==12 gate:** `BlePlugin:966-969` + `VitalRanges 30..220:971`. Firmware emitting only `type 13` with 0 → ignored → 60s TIMEOUT. HR only vital with 2-sample gate vs SpO2 instant `>0`.

## Fix (`BlePlugin.kt` + `MeasurementLoopManager.kt:229`)

* Top of `readHeartRate:951`: `if (SdkGuard.isOpen()) return error SDK_GUARD_OPEN; if(!isConnected) return error NOT_CONNECTED` (mirror loop `109`).
* Extend `MANUAL_ACQUIRE_TIMEOUT 4000→8000`.
* Store `timeoutRunnable`, `removeCallbacks` on success (`961`) and disconnect (`673`); `watchForPreempt` removes timeout before release.
* Log rejected `255/95` via `measurement_attempt rejected` + `valueJson`.

## Verification

* `logcat -s MeasurementLoop:D BlePlugin:D | grep -E "BUSY|TIMEOUT|Reply already|candidate="`, `sqlite3 ... "select vital,status from measurement_attempt ..."`, `app_incidents source='heart_rate_screen'`.
