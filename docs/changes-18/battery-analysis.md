# Battery Drain Analysis — Changes 18

## Executive Summary

The app exhibited significant battery drain due to three primary factors:

1. **MeasurementLoopManager** — BLE radio active for ~7 min out of every 10 min cycle
2. **BleConnectionService** — 8-second polling loop even when healthy and connected
3. **Ring HR interval** — Set to 10 min (vs 30-60 min in official app)

## Root Causes

### 🔴 Root Cause #1: MeasurementLoopManager (HIGH)

**File:** `android/app/src/main/kotlin/com/sundr/myapp/MeasurementLoopManager.kt`

The measurement loop runs 7 vitals per cycle in sequence:

| Vital | Timeout |
|-------|---------|
| Steps | instant (passive read) |
| HR | 60s |
| SpO2 | 60s |
| Stress | 60s |
| BP | 60s |
| HRV | 90s |
| Temp | 90s |

Each vital also has a 2s post-stop settle. In the **worst case** (all vitals timeout):

```
(60×4 + 90×2) + 7×2 = 414s (~7 min)
```

With a **3-minute cooldown**, the BLE radio is active for the **majority of the time** — there's near-zero idle time between cycles.

### 🔴 Root Cause #2: BleConnectionService Polling (MEDIUM-HIGH)

**File:** `android/app/src/main/kotlin/com/sundr/myapp/BleConnectionService.kt:81-117`

The `checkRunnable` fires **every 8 seconds** (even when healthy) on the main thread:

1. Calls `BleSdkLifecycle.isConnected()` — BLE stack query
2. Runs `maybeFireSleepReminder()` — SharedPreferences reads
3. Reschedules itself

At 8s interval, that's **~10,800 wake-ups per day**, preventing the CPU from entering deep sleep.

### 🟡 Root Cause #3: Ring HR Interval (MODERATE)

**File:** `lib/providers/ble_provider.dart:1599-1602`

```dart
await _ble.setHeartRateSetting(enable: true, interval: 10)
```

Configures ring firmware to log HR every 10 minutes. Official QRing app defaults to 30-60 min. This doubles or triples **ring-side** radio activity.

### 🟡 Root Cause #4: WorkoutProvider Fire-and-Forget Loops

**File:** `lib/providers/workout_provider.dart:308-344`

`hrLoop()` (4s interval) and `stepsLoop()` (2s interval) run as `while (_isWorkoutActive)` loops. `dispose()` cancels `_uiTimer` but **does not set `_isWorkoutActive = false`**, so these loops can continue running after disposal.

### 🟡 Root Cause #5: PrayerSessionProvider Missing dispose()

**File:** `lib/providers/prayer_session_provider.dart`

Has a 1-second `_timer` but no `dispose()` override. If disposed without calling `endSession()`, the timer leaks.

## Priority Fixes

| # | Fix | Expected Impact |
|---|-----|-----------------|
| 1 | Adaptive measurement timeouts (response time + headroom) | **High** — reduces BLE radio duty cycle 60-80% |
| 2 | BleConnectionService poll interval (8s → 30s when connected) | **Medium** — 75% fewer CPU wake-ups |
| 3 | Ring HR interval (skipped per user request) | — |
| 4 | WorkoutProvider `_isWorkoutActive = false` in dispose() | **Low** — prevents leaked loops |
| 5 | PrayerSessionProvider add dispose() | **Low** — prevents timer leak |

## Implementation Details

### Fix 1: Adaptive Measurement Timeouts

**Approach:**
- Track actual measurement duration per vital type using a rolling average (last 5 readings)
- Compute adaptive timeout: `max(avg × 1.5, 15s)`, clamped at fixed ceiling (60s/90s)
- When vitals are normal (no FallRiskAnalyzer anomalies for 2+ cycles), cooldown stretches from 3 min → 15 min
- Any anomaly immediately resets to fast mode (3 min cooldown)

**Key constants:**
```kotlin
MIN_TIMEOUT_MS = 15_000L          // Floor — never shorter than 15s
TIMEOUT_HEADROOM_FACTOR = 1.5     // 50% headroom over actual response time
ROLLING_WINDOW = 5                // Rolling average over 5 measurements
FAST_COOLDOWN_MS = 180_000L       // 3 min — anomaly mode
SLOW_COOLDOWN_MS = 900_000L       // 15 min — healthy mode
NORMALCY_CONFIRM_CYCLES = 2       // Consecutive normal cycles before slowing
```

**Files modified:**
- `android/app/src/main/kotlin/com/sundr/myapp/MeasurementLoopManager.kt`
- `android/app/src/main/kotlin/com/sundr/myapp/analysis/FallRiskAnalyzer.kt`

### Fix 2: BleConnectionService Poll Interval

**Approach:**
- When connected and stable (`connected && wasConnected`), poll interval increases from 8s → 30s
- Freshly connected: 8s; circuit breaker open (`SdkGuard.isOpen()`): 30s
- While disconnected: exponential backoff 8s → 15s → 30s → 60s → 120s
- Reduces CPU wake-ups by ~75% when idle

**Files modified:**
- `android/app/src/main/kotlin/com/sundr/myapp/BleConnectionService.kt`

### Fix 4: WorkoutProvider Leak Fix

**Approach:**
- Set `_isWorkoutActive = false` in `dispose()` before cancelling timer
- Prevents fire-and-forget `hrLoop()`/`stepsLoop()` from continuing after disposal

**Files modified:**
- `lib/providers/workout_provider.dart`

### Fix 5: PrayerSessionProvider Leak Fix

**Approach:**
- Added `dispose()` override that cancels the 1s timer
- Stops workout and restores cooldown if session was still active

**Files modified:**
- `lib/providers/prayer_session_provider.dart`

## Verification

- `flutter analyze` passes (later runs surfaced 17 pre-existing warnings in unrelated files — zero errors in changed files)
- All changes are backward-compatible
- No API changes or breaking changes

## Estimated Battery Impact

| Fix | Phone Battery | Ring Battery |
|-----|--------------|--------------|
| Adaptive timeouts | **High** — BLE radio active time reduced 60-80% | Moderate — less frequent manual-mode commands |
| 30s poll interval | **Medium** — 75% fewer CPU wake-ups | — |
| WorkoutProvider fix | Low — prevents rare loop leak | Low |
| PrayerSessionProvider fix | Low — prevents timer leak | Low |
