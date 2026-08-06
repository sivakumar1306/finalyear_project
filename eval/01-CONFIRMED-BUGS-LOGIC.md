# 01 — Confirmed Bugs & Logic Errors

> Refs are `file:line`. All confirmed by direct read.

## 1.1 Blood-Pressure staging uses `||` instead of `&&` — [CRIT]

```dart
String _bpStatus(int sbp, int dbp) {
  if (sbp <= 0 || dbp <= 0) return '';
  if (sbp < 120 && dbp < 80) return 'Normal';
  if (sbp < 130 && dbp < 80) return 'Elevated';
  if (sbp < 140 || dbp < 90) return 'Stage 1';   // BUG: should be &&
  return 'Stage 2';
}
```

- `lib/screens/health/blood_pressure_screen.dart:40-46` (classification) and `:48-54` (color helper, same bug at line 52)
- `lib/screens/home/home_screen.dart:3044-3045,3052` (duplicate)

**Impact of the `||` bug:** a reading qualifies for Stage 1 if EITHER value is below the threshold. E.g.:
- **139/95** → `sbp<140` true → labeled **Stage 1** (correct answer: Stage 2, since dbp ≥ 90).
- **179/70** → `dbp<90` true → labeled **Stage 1** (correct: isolated systolic ≥ Stage 2 range).

**Second bug — "Elevated" requires `dbp < 80`:** 125/85 (elevated systolic, borderline dbp) fails both `Normal` and `Elevated` gates and falls into **Stage 1** — wrong per the UI's own reference table (`blood_pressure_screen.dart:487-507`: Elevated = 120–129/&lt;80, Stage 1 = 130–139/80–89).

Stage-1/Stage-2 classification and the displayed color are wrong for any reading where one value is high and the other low. **Medical misclassification.**

**Fix:** use `sbp < 140 && dbp < 90` for the Stage-1 boundary, and correct the Elevated gate to `sbp < 130 && dbp < 90`. Extract to one pure function shared by both files.

---

## 1.2 Emergency Auto-Call / Auto-SMS shipped despite spec FD-33 — [CRIT]

- Spec `specs/05-fall-detection-safety.md:108` — "FD-33 | No auto SMS/call in current release unless explicitly product-approved later."
- Spec `specs/00-product-overview.md:117` — "auto-call is not current scope."
- Code: `android/app/src/main/kotlin/com/medxai/sundr/analysis/EmergencyAutoCaller.kt` + `EmergencySmsSender.kt` — fully implemented, wired to settings toggle (`setAutoCallOnFallEnabled`), and `CALL_PHONE`/`SEND_SMS` declared in the manifest.

**Impact:** The release ships a capability the safety spec explicitly deferred, with no approval trail, plus `READ_SMS`/`READ_CALL_LOG`/`RECORD_AUDIO` in the manifest to go with it.

---

## 1.3 Fake emergency contacts auto-seeded — [CRIT]

Two independent screens insert placeholder contacts when the contact list is empty:

- `lib/screens/settings/fall_detection_screen.dart:107-114` — seeds `'Mom' → '+91 000 000 0000'` and `'9999999999'`.
- `lib/screens/settings/profile_edit_screen.dart:89-93` — seeds `'Default Emergency (Default)' → '9999999999'`.

**Impact:**
- Users believe a real doctor/relative is on the emergency list; the app will **dial a non-existent number** and **send the fall SMS to it** on the real emergency pipeline.
- `9999999999` is one digit away from India's emergency line (112/100) — a user glancing at the list may think it's a real service number.
- The feature works "end-to-end" (settings → SMS → call) against **fabricated data**, which is worse than a disabled feature.

**Fix:** Start with an empty list. Show a warning + block auto-call/auto-SMS until ≥1 real contact exists. Never insert demo numbers in release code paths.

---

## 1.4 "Demo" buttons trigger the REAL emergency pipeline — [HIGH]

`android/app/src/main/kotlin/com/medxai/sundr/BlePlugin.kt:2481-2566`:
- `simulateFallEvent` → inserts a real fall event, fires `FallAlertNotifier.notifyFall`, shows the safety live-update, **schedules EmergencySmsSender** and **calls EmergencyAutoCaller.placeIfEnabled**.
- `simulateFallPrediction` → inserts HR spike, notifies, **schedules SMS**.

Dart UI exposes these behind "Simulated fall" / "Simulated prediction" buttons (`lib/screens/settings/fall_detection_screen.dart:399-413`) — labeled as simulations but producing real SMS countdowns and, if the auto-call toggle is on, a real phone call.

**Impact:** A user tapping "demo" in the settings gets a real SMS/call. Not just a data concern — an operational one.

---

## 1.5 `ErrorWidget.builder` swallows all UI errors — [HIGH]

`lib/main.dart:104-107` — every widget build/layout error renders as `SizedBox.shrink()` (blank screen), while `FlutterError.onError` (line 80) and `PlatformDispatcher.onError` (line 93) report to Supabase `app_incidents` (via `IncidentService`).

**Impact:**
- Users see a blank section with no error UI; no way to know a widget crashed.
- Every error from dev/test/QA devices lands in the **production incidents table** with no environment filter, rate limit, or dedupe → table spam (see 05.4/08.4).

---

## 1.6 Prayer summary/history write to `workouts` table — no migration — [HIGH]

- `lib/screens/prayer/prayer_summary_screen.dart:40` — `.from('workouts').insert(...)`
- `lib/screens/prayer/prayer_history_screen.dart:29` — `.from('workouts').select(...)`

`workouts` is **not** created by any migration (05.1). If absent in the deployed DB, saving a prayer session 404s and history is always empty. (Verify whether the table exists in the live dashboard.)

---

## 1.7 `compileSdk` (36) < `targetSdk` (37) — [CRIT] (see 04)

AGP requires `compileSdk >= targetSdk`. `android/app/build.gradle.kts:22,33` as written produces a hard build failure on a clean machine ("The targetSdk is higher than compileSdk"). Release builds are blocked or produce a broken artifact depending on toolchain.

---

## 1.8 Supabase: app writes tables migrations never create — [CRIT] (see 05)

`user_profiles`, `user_steps`, `user_hr`, `user_spo2`, `user_bp`, `user_stress`, `user_hrv`, `user_temp`, `user_workouts`, `user_sleep`, `user_cycles`, `user_symptoms`, `user_emergency_contacts` (all `supabase_service.dart:110-734`) and `workouts` (prayer) are **absent from migrations**. RLS policies exist only for the 6 migrated tables. Fresh environments silently lose all vitals.

---

## 1.9 Steps→calories `~/ 1000` — OK (documented, not a bug)

`lib/providers/workout_provider.dart:345-361` — `e = calories (小卡, divide by 1000 for kcal)`; the `~/ 1000` conversion is documented and intentional. Same convention in `steps_screen.dart:254`. Retracted from earlier draft.

---

## 1.10 Fall-prediction "AI" reasoning assumes 100 = optimal baseline — [MED]

`lib/providers/fall_prediction/*` reasoning engine computes deviations against a normalized 0–100 scale as if 100 were the physiological optimum (heart rate "100" is not optimal; HR data is normalized for display). The reasoning chain (`explainable_ai_dashboard.dart`) can therefore explain nonsense. Acceptable only if documented as a demo heuristic.

---

## 1.11 Womens-health prediction uses threshold values on a 0–100 scale — [MED]

`lib/services/womens_health_prediction_service.dart` — rules like `temperature > 55.0` operate on the normalized scale, not °C. Look like placeholder thresholds; document or correct against clinical baselines.

---

## 1.12 Health Connect writes unverified on Android 14+ — [MED]

`lib/services/health_connect_service.dart` — permission flow changed for Android 14+ (`HealthConnectClient`). Verify the package version + permission request UX; the most likely "silently does nothing" spot.

---

## 1.13 `syncAutoTemperature` complexity vs failure modes — [LOW]

`BlePlugin.kt:1762-1852` — 4-attempt retry with FileHandle callback juggling is brittle (callback registrations racing with `initRegister()`); consider a simpler documented path. Not a confirmed bug.

---

## 1.14 Prayer schedule prefs stored as strings for a native consumer that doesn't exist — [LOW]

`lib/services/prayer_schedule_prefs.dart:4-7` — comment says ints-as-strings prevents a native `getInt` crash, but no native code reads these keys today. Harmless workaround; confirm the comment's premise when native reads are added.
