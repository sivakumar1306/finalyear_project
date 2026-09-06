# 02 — Mounted Guard Generalization

## Problem

`app_incidents_rows.csv` ~18 rows identical: `setState() called after dispose(): _SleepScreenState` stack `#2 _loadDayFromDb sleep_screen.dart:225 → #3 _parseSleepData:173 → #4 _fetchFromRing:156 → #5 _init:119`. Also `chat_screen.dart:239` `Null check operator` and `CameraException buildPreview disposed`.

## Root

`sleep_screen.dart:119` `_init() async { await _fetchFromRing() ... }` awaits 5s BLE, user pops, `setState` on defunct. Same pattern in `heart_rate_screen:152,272`, `blood_oxygen:155,249`, `hrv:168,456`, `stress:170,263`, `temperature:178,264`, `blood_pressure:199,296`.

## Fix

* Create `lib/utils/mounted_guard.dart` mixin or add `if(!mounted) return;` before every `setState` after `await` in 7 health screens + `chat_screen:239`.
* In `sleep_screen:155,216,439,540,757` capture `final date=_selectedDate` before await, guard all 8 `setState` sites.
* Keep `IncidentService` catch but guard first.

## Verification

* `app_incidents` `setState after dispose` 18 → 0. `flutter test` unchanged.
