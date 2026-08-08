# 05 — Fall Detection & Safety

| Field | Value |
|-------|-------|
| **Status** | Partial — Phases 1–3 built; prediction live but **not validated** against real falls |
| **Key docs** | `FALL_DETECTION_STATUS.md`, `architecture/Health_Analysis.md` |
| **Key code** | `FallRiskAnalyzer.kt`, `FallMotionDetector.kt`, `FallAlertNotifier.kt`, `FallPredictionNotifier.kt`, `fall_detection_screen.dart`, Flutter `fall_prediction/*` |

---

## 1. Purpose

1. **Predict** elevated near-term fall *risk* from cardiovascular / syncope-oriented vitals patterns.  
2. **Detect** likely falls using phone motion + vitals corroboration.  
3. **Alert** the user locally and store contacts for future emergency expansion.

---

## 2. Product scope & explicit non-scope

### In scope

- Vitals-based risk score (0–100) logged on every analysis.
- Live predictive alerts for high tiers (with cooldown).
- Phone accelerometer/gyro three-phase detector (free-fall → impact → stillness).
- Corroboration window (~±30s) against vitals spikes before local fall alert.
- Local notification with “I’m okay” dismiss.
- Emergency contact list persisted natively (Room).
- UI: score, history, contacts, debug simulation tools.

### Out of scope (current)

- Continuous ring IMU fall detection (SDK does not stream accel/gyro for this).
- Claiming general mechanical trip-and-fall prediction from vitals alone.
- Caregiver push (FCM / Supabase realtime) — **planned**.
- Auto-dial emergency contacts or 112 — **planned / deferred**.
- Full-screen lockscreen overlay — **planned**.

**Clinical honesty:** Mechanical falls often have no physiological prodrome. Prediction is marketed/scoped as **syncope/cardiovascular pre-fall signal**, not a universal fall predictor.

---

## 3. Architecture (three phases)

```
Phase 1 — Predictive (vitals)
  NewReadingEvent → FallRiskAnalyzer → fall_risk_log
                 → (HIGH/CRITICAL/OVERRIDE + cooldown) → FallPredictionNotifier

Phase 2 — Active detection (phone motion)
  Accel/Gyro 50Hz → FallMotionDetector → fall_event (always)
                 → vitals corroboration? → Phase 3

Phase 3 — Local alert
  FallAlertNotifier → notification + "I'm okay"
```

Both detectors run inside the existing BLE **foreground service** (no second service for motion).

---

## 4. Phase 1 — Fall risk score (native)

| ID | Requirement |
|----|-------------|
| FD-01 | On each persisted vital reading, compute a score 0–100 and tier. |
| FD-02 | Inputs include sedentary HR anomalies, SpO₂, BP extremes / pulse pressure, stress vs short baseline, HRV drops vs baseline (when available). |
| FD-03 | **Hard override:** SpO₂ < 88 → critical / score 100 path. |
| FD-04 | Log every computation to `fall_risk_log` regardless of tier (silent measurement capability). |
| FD-05 | For HIGH / CRITICAL / OVERRIDE, fire predictive notification subject to **~15 min cooldown**. |
| FD-06 | Predictive copy must not overclaim (risk / “might fall”, not guaranteed fall). |

### Flutter multi-layer model (UI explainability)

A separate Dart engine (`FallPredictionEngine`) computes HSI / risk layers for the Fall Detection settings UI (physiological, recovery, motion, women’s health, adaptive weights).

| ID | Requirement |
|----|-------------|
| FD-10 | Document polarity: **HSI = stability (higher better)**; **risk score = higher worse**. |
| FD-11 | Product UI should prefer clear naming (**Fall Risk Score**), not ambiguous “Fall Confidence Score”. |
| FD-12 | Adaptive weights must renormalize so Σw = 1. |
| FD-13 | Known open issues (recovery term polarity, triple-counting history, missing personal baselines) tracked in `something.md` / `something-action-plan.md` — treat as P0/P1 backlog before research claims. |

---

## 5. Phase 2 — Active motion detection

| ID | Requirement |
|----|-------------|
| FD-20 | Sample phone accelerometer at ~50 Hz; gyroscope optional confidence boost. |
| FD-21 | Detect free-fall: magnitude < ~0.4g for minimum duration (~80ms). |
| FD-22 | Detect impact: peak &gt; ~3.0g within ~0.5s of free-fall. |
| FD-23 | Require post-impact stillness (≥~35% samples near 1g within stillness window) — primary FP filter vs running/jumping. |
| FD-24 | Minimum confidence ≥ ~0.55 to accept candidate. |
| FD-25 | Thresholds in **g-units**, never raw m/s² mistaken for g (regression test). |
| FD-26 | Log **all** candidates to `fall_event`, including non-corroborated. |
| FD-27 | Corroborate with vitals spike (HR / stress / SpO₂) in ±30s before escalating to Phase 3. |

---

## 6. Phase 3 — Local alerting

| ID | Requirement |
|----|-------------|
| FD-30 | High-priority local notification only on corroborated events. |
| FD-31 | “I’m okay” action dismisses alert without emergency side effects. |
| FD-32 | Tapping notification opens Fall Detection settings / relevant UI. |
| FD-33 | No auto SMS/call in current release unless explicitly product-approved later. |

Future (planned requirements):

| ID | Requirement |
|----|-------------|
| FD-40 | Optional countdown before SMS/call; user can cancel. |
| FD-41 | Caregiver push via chosen transport (FCM vs Supabase). |
| FD-42 | SMS/call uses onboarding/settings emergency contacts. |

---

## 7. Emergency contacts

| ID | Requirement |
|----|-------------|
| FD-50 | User can add/edit/remove emergency contacts. |
| FD-51 | Contacts stored in **native Room** (not Flutter-only memory) so background actions can read them later. |
| FD-52 | Optional cloud mirror table `user_emergency_contacts` for backup/sync if present. |

---

## 8. Fall Detection settings UI

Screen: `fall_detection_screen.dart` (`/fall-detection`).

Must show:

- Current risk score / tier (real engine output, not placeholder).  
- Explainable layers if Flutter engine is active.  
- Fall event history.  
- Emergency contacts management.  
- Debug menu (dev/test): simulate risk tiers, fall notification, synthetic vital through real pipeline.

---

## 9. Acceptance criteria

- [ ] Risk score updates after real ring readings and appears on Fall Detection screen.
- [ ] SpO₂ < 88 path produces critical tier / override behavior in analyzer logs.
- [ ] Drop test on real phone yields detection with confidence; walking/running FP rate acceptable after g-unit fix.
- [ ] Uncorroborated motion candidates log but do not notify.
- [ ] Corroborated path shows local notification dismissible with “I’m okay”.
- [ ] Emergency contacts survive app restart.
- [ ] Simulation tools exercise notification and score path without real fall.

---

## 10. Open validation work

1. Multi-hour battery impact of continuous sensors.  
2. Correlation of logged risk scores vs real/near falls.  
3. Align Flutter HSI/FRS math with native analyzer semantics and fix polarity bugs.  
4. Caregiver push product decision.

---

## 11. Related

- `FALL_DETECTION_STATUS.md`  
- `something.md`, `something-action-plan.md`  
- `architecture/Health_Analysis.md`  
