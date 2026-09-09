# 01 — Can the current HR implementation cancel an ongoing request?

Date: 2026-09-09 · Branch state: `main@c31b954` + tiered strict/legacy fallback

## Verdict: yes, substantially true — no cancel path existed

## Evidence

* Dart `lib/screens/health/heart_rate_screen.dart:_startMeasurement` guarded
  `if (_measuring) return`; `RealTimeCard` set `onTap: measuring ? null : onTap`.
  Second tap ignored, `await _ble.readHeartRate()` blocked up to 60s, no
  `cancelHeartRate` channel, no `dispose` cleanup.
* Native `BlePlugin.readHeartRate` (then `BlePlugin.kt:981`) only exited via
  strict success / legacy-at-timeout / `HR_ERR_*` / 60s `TIMEOUT`. The stop entry
  `manualModeHeart(start=false)` existed but the HR screen never called it.
* Single-slot `MeasurementCoordinator.busyOwner` shared by `"manual"` / `"loop"` /
  `"workout"`. A held slot meant the next tap polled 300ms until the 8s
  `MANUAL_ACQUIRE_TIMEOUT_MS`, then `BUSY`.
* No stop-before-start: lock acquired, then `manualModeHeart(cb,false)` issued
  directly. A firmware-stuck sensor (LED on from a leaked session) fought the new
  start on the vendor SDK's single shared manual-mode response slot.
* Disconnect leak: `onDeviceDisconnected` cleared connect state but never removed
  the HR `timeoutRunnable`, released `"manual"`, or sent stop — slot held until
  the 60s timeout fired.
* Storm breaker: 8 failures/60s opens `SdkGuard` for 45s; every invoke then
  returns `SDK_GUARD_OPEN` without touching the sensor.

## What already worked (partial mitigations)

8s acquire poll + `BUSY`, `NOT_CONNECTED` / `SDK_GUARD` guards, `errCode`
fail-fast + stop, 60s timeout + stop + release, loop `watchForPreempt` yield to
manual, `POST_STOP_SETTLE_MS` 2s before lock release.
