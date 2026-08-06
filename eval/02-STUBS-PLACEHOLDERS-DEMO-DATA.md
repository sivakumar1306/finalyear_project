# 02 — Stubs, Placeholders, and Fake/Demo Data

> Every item below was confirmed by direct read. Important correction vs. earlier notes: **the native layer is mostly real** — only the 7 methods in 2.1 are stubs. BLE scan/connect, HR/BP/SpO2/steps/sleep/HRV/stress/temperature, camera, phone control, DND, reminders, OTA (DfuHandle), Room persistence, emergency SMS/call, and sync are genuinely implemented against the Oudmon SDK (`com.oudmon.ble.base`).

## 2.1 Native method-channel stubs (Android) — [HIGH]

File: `android/app/src/main/kotlin/com/medxai/sundr/BlePlugin.kt:318-334`

| Method | Line | Actual behavior | Correct behavior |
|---|---|---|---|
| `getDisplaySettings` | 318 | `result.success("{}")` | read ring display settings from hardware |
| `setDisplaySetting` | 319 | `result.success(true)` | write setting to ring |
| `getTargetAndProfile` | 320 | `result.success("{}")` | fetch targets/profile from ring |
| `setTargetAndProfile` | 321 | `result.success(true)` | persist on ring |
| `getAdvancedSettings` | 322 | `result.success("{}")` | read advanced settings |
| `setAdvancedSetting` | 323 | `result.success(true)` | write to ring |
| `sendNotification` | 334 | `result.success(true)` | send notification to ring |

**Impact:** Ring settings screens show "saved"/"configured" while the ring is untouched. A user setting 12h-clock, temperature unit, or activity targets believes they took effect on-device. Silent lie in the settings domain — worse than a disabled button.

## 2.2 Demo/simulation paths that trigger REAL side effects — [HIGH]

`BlePlugin.kt:2481-2566`:
- `simulateFallEvent` → real `FallEventEntity` insert + real `FallAlertNotifier.notifyFall` + real `EmergencySmsSender.schedule` + real `EmergencyAutoCaller.placeIfEnabled`.
- `simulateFallPrediction` → real HR insert + real SMS scheduling + real `FallPredictionNotifier.notifyPrediction`.

UI entry points: `lib/screens/settings/fall_detection_screen.dart:399-413` ("Simulated fall — SMS countdown started", "Simulated prediction — SMS countdown started").

Also:
- `seedDemoData(hoursBack)` (BlePlugin.kt:2412) seeds Room with fabricated readings, exposed via `BleProvider.seedDemoData` (`lib/providers/ble_provider.dart:584`) — used by "test without ring" flows. Readings land in the same tables as real data with no `is_demo` flag, then sync to Supabase (`saveStepsSnapshot` → `SupabaseSyncManager.forceSyncNow()`).

**Impact:** Demo data pollutes real vitals, and "demo" fall buttons place real SMS/calls. Any demo mode must be (a) isolated from sync and (b) clearly labeled in UI.

## 2.3 Sugar/Lipid screen — placeholder + native stub behind it — [HIGH]

`lib/screens/sugar_lipids/sugar_lipids_screen.dart` (77 lines, confirmed):
- Two `DataCard`s showing hardcoded `'--'` values (lines 43-45).
- "Fetch Data" button calls `_ble.getHealthSettings()` → native `getAdvancedSettings` stub → returns `"{}"` (`BlePlugin.kt:322`).
- Result rendered as raw indented JSON in monospace (`:23-25,71`) — `sugarLipids` key won't exist in `{}`, so the user sees `{}`.

Reachable from the UI; users see an empty placeholder screen plus a JSON dump instead of a designed panel.

## 2.4 OTA screen — actually implemented (correction) — [OK]

`BlePlugin.kt:2191-2222` uses `DfuHandle` with file check, init/send/check/end state machine and `otaProgress` events. The native half is real. Verify only the Dart screen actually downloads the firmware file from `firmware_updates` and passes a valid path — that link needs a smoke test on device.

## 2.5 Prayer mode — writes to unmigrated `workouts` table — [HIGH]

`lib/screens/prayer/prayer_summary_screen.dart:40`, `prayer_history_screen.dart:29`. If the table doesn't exist in the deployed DB, all prayer sessions fail silently (404). `prayer_session_screen.dart:537` also has a 'Simulated Data' label path (correctly labeled, good).

## 2.6 Fall prediction "AI" — deterministic rules engine labeled as AI — [MED]

`lib/providers/fall_prediction/*` — `baseAlpha/baseBeta/baseGamma/baseDelta` weights + adaptive normalization. UI label "AI Reasoning" (`lib/widgets/fall_prediction/explainable_ai_dashboard.dart`). In a medical app, rename to "rule-based estimation" or disclose.

## 2.7 Womens-health prediction — threshold pseudo-rules — [MED]

`lib/services/womens_health_prediction_service.dart` — cycle/temperature thresholds on the 0–100 normalized scale (e.g., `temp > 55.0`). Confirm against clinical baselines or mark as simulation.

## 2.8 Test suite — single placeholder — [HIGH]

`test/widget_test.dart` — 7 lines: "Placeholder — full app requires BLE hardware". Only test in the repo. `flutter test` passes but verifies nothing. (See 07.)

## 2.9 `user_emergency_contacts` has no migration — [HIGH]

`lib/services/supabase_service.dart:711-734` upserts/reads it; no migration creates it (05.1). If absent, contact sync fails — combined with 1.3 (fake seeded contacts) this makes the contacts feature look functional while being broken.

## 2.10 Health-connect (Android Health) — verify on device — [MED]

`lib/services/health_connect_service.dart` wraps the official package; confirm Android 14+ permission UX and that `AGGREGATE_*` ids are current. Most likely silent no-op (see 01.12).

---

## Summary table

| Surface | Native | Status |
|---|---|---|
| BLE scan/connect/HR/BP/SpO2/steps/sleep/HRV/stress/temp/camera/phone/DND/reminders/OTA | real SDK calls | OK |
| Display settings, targets/profile, advanced settings, sendNotification | canned `{}`/`true` | **STUB** |
| Emergency SMS + auto-call | real | **WORKS — but spec says out-of-scope, and dials fake seeded contacts** |
| Fall "simulation" buttons | real side effects | **DANGEROUS DEMO** |
| Seed demo data | Room + sync | pollutes real data |
| Sugar/lipids | Dart placeholder | **PLACEHOLDER** |
| Prayer summaries | writes to unmigrated table | **BROKEN at DB layer** |
| Tests | — | **ABSENT** |