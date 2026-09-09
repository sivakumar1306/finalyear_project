# 03 — Auto-cycle 3-minute spacing (race prevention)

## Why

The auto loop round-robins Steps → HR → SpO2 → Stress → BP → HRV → Temperature
through one BLE manual-mode slot. With a 60s cooldown the loop re-armed quickly,
so a manual "Measure Now" tap often landed mid-vital: 8s acquire poll →
`BUSY`, or `watchForPreempt` + 2s `POST_STOP_SETTLE` yield delay, or a 90s
HRV/temperature window blocking the sensor. 3 minutes keeps the slot idle far
more often when the user taps.

## Change (`MeasurementConfig.kt`)

* `DEFAULT_CYCLE_COOLDOWN_MS`: `60_000L` → `180_000L` (3 min).
* One-time migration in `getCycleCooldownMs()`: stored `60_000` (old default)
  maps to `180_000` and is persisted, because prefs-cached devices would
  otherwise keep the old value forever. Explicit user/dev overrides (health
  settings screen, prayer session 0/180000) are untouched — only the exact old
  default migrates.
* `finishCycle()` already reads the cooldown fresh each cycle, so the new value
  takes effect on the very next cycle without a restart. `YIELDED_TO_MANUAL`
  still resumes after 15s (`WORKOUT_RECHECK_MS`) instead of the full cooldown.

## Dart already aligned

`ble_service.getCycleCooldownMs` fallback `180000`, `health_settings_screen`
default `180000` — no Dart change needed.

## Verify on device

* `adb logcat -s MeasurementLoop:D | grep -E "runCycle|YIELDED|COMPLETED"`: gap
  between `COMPLETED` and next cycle start ≈ 180s.
* Manual tap mid-cooldown acquires immediately (no `BUSY`); tap mid-vital still
  yields within ~2.2s worst case (200ms poll + 2s settle).
