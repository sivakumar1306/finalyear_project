# 07 — Women’s Health / Cycle Tracking

| Field | Value |
|-------|-------|
| **Status** | Shipped (calendar model + AWHE rule-based layer disclosed informational-only; ML RF/XGBoost/LSTM future) |
| **Key code** | `womens_health_screen.dart`, `womens_health_models.dart`, `womens_health_prediction_service.dart`, `CycleEngine` (`cycle_engine.dart`), Supabase `user_cycles` / `user_symptoms` |

---

## 1. Purpose

Provide menstrual cycle calendar, phase awareness, symptom logging, and predictions for eligible users. Combines calendar history with ring physiology (Adaptive Women's Health Engine, AWHE) — rule-based, explainable, immediately functional; ML personalization later.

---

## 2. Access control

| ID | Requirement |
|----|-------------|
| WH-01 | Women’s Health entry points (Home card, route `/womens-health`) are **gender-gated** from profile. |
| WH-02 | Users outside the eligible gender configuration must not see the card (or see a clear non-applicable state if navigated deeply). Profile gender changes update visibility. |

---

## 3. Core concepts

| Concept | Definition (product) |
|---------|----------------------|
| Period start | User-logged start date of menses (`user_cycles`, persisted via `getCycles` / `saveCycle`) |
| Cycle length | Days between period starts (user-set or default) |
| Period length | Days of bleeding (user-set or default) |
| Day of cycle | `cycleDay = now.diff(periodStart).inDays + 1` clamped (`CycleEngine`) |
| Phases | Menstrual, Follicular, Ovulation, Luteal |
| Fertile window / ovulation | Derived from cycle length (calendar model) |
| Next period | Predicted from period start + cycle length, optionally fused with AWHE phase estimate |
| Symptoms | Per-date log (`user_symptoms`, `getSymptomsForDate` / `upsertSymptoms` **with `user_id`** — RLS fix, eval 1.6/1.8) |

**CycleEngine** (`cycle_engine.dart`, pure — removes duplication `CompactWomensHealthCardState._loadCycle` ↔ `WomensHealthMiniCard`):

```
phaseName(day, cycleLen, periodLen):
  day <= periodLen → menstruation
  day <= 13        → follicular
  day <= 16        → ovulating
  else             → luteal
```

Refs `home_compact_cards:180`, `home_vitals_cards:94`, `WomensHealthMiniCard:180`. Flex ratios `13 - periodLen / 3 / len-16` (`CyclePhaseBar 344-387`). `cycleDay` clamped.

**Note:** Product math is primarily **calendar-based** today. Wearable-derived signals (temp/HRV trends) feed the AWHE phase-estimation layer below but are not the sole source of phase equations.

---

## 4. AWHE — Adaptive Women's Health Engine (rule-based v1)

Source: `docs/archive/scratch_docx.txt` (full proposal). Decision-support, not diagnosis — AWHE card carries footnote: *"Estimates from ring vitals plus cycle rules — informational only, not a medical diagnosis."* (eval 2.7 disclosed).

### 4.1 Table 1 — Physiological basis

Hormonal variation impacts wearables-tracked indicators (wearables track, not cause):

| Menstrual Phase | Typical Physiological Indicators |
|---|---|
| Menstrual | Lower activity, recovery begins |
| Follicular | Higher HRV, lower resting heart rate, stable temperature |
| Ovulation | Slight rise in skin temperature; resting heart rate begins increasing |
| Luteal | Higher skin temperature, lower HRV, higher resting heart rate, increased stress sensitivity |

Basis for estimating phase from wearable data alone.

### 4.2 Fig 1 — Pipeline (raw → app)

```
Smart Ring Sensors (continuous: skin temp, HRV, resting HR, sleep, stress, activity)
  ↓ Physiological Data Collection
  ↓ Data Preprocessing Layer (cleaning, normalization, artifact removal)
  ↓ Physiological Phase Estimation Engine (rule-based inference → phase probability distribution)
  ↓ Current Menstrual Phase Estimation
  ↓ Menstrual Prediction Engine (fuse with cycle history when available)
  ↓ Confidence & Explainability Module (score + supporting reasons)
  ↓ Mobile Application (SUNDR user)
```

Components: Sensors → Preprocessing → Phase Estimation → Prediction → Confidence/Explainability → Mobile.

### 4.3 Table 2 — Sensor inputs

| Sensor Data | Purpose |
|---|---|
| Skin Temperature | Reflects hormonal temperature changes |
| HRV | Reflects autonomic nervous system activity |
| Resting Heart Rate | Indicates cardiovascular adaptation |
| Sleep Quality | Indicates physiological recovery |
| Stress Score | Indicates autonomic balance |
| Activity Level | Indicates physical workload |

Thresholds operate on the **normalized 0–100 scale**, not raw °C/bpm (e.g. `temperature > 55.0` in `womens_health_prediction_service.dart` — documented per eval 1.11/02.7; same disclosure as fall-prediction `reasoning_engine.dart` normalized-scale heuristic, eval 1.10). Confirm against clinical baselines or keep marked simulation.

### 4.4 Rules 1–3 — Phase estimation

First estimate current phase, then predict. Each rule contributes evidence:

```
Rule 1: Skin Temp ↑ + HRV ↓ + Resting HR ↑ → Late Luteal
Rule 2: HRV ↑ + Resting HR ↓ + Temp Stable                → Follicular
Rule 3: Temp begins rising + Resting HR begins increasing → Ovulation
```

### 4.5 Two-path prediction

```
If cycle history exists:    Calendar Prediction + Estimated Phase → Final Prediction
If no history:              Estimated Phase + Expected Remaining Days → Predicted Period
```

### 4.6 Table 3 — Worked example

| Input | Value |
|---|---|
| Estimated Phase | Late Luteal |
| Remaining Duration | 3 days |
| Predicted Period | 3 September |

### 4.7 Table 4 — Confidence output

| Field | Value |
|---|---|
| Estimated Phase | Late Luteal |
| Prediction | 3 September |
| Confidence | 92% |
| Reason | Elevated skin temperature · Lower HRV · Higher resting heart rate |

Confidence inputs: sensor availability, data consistency, trend stability, historical availability.

### 4.8 Future ML

Transparent rules now (explainable, shippable). With sufficient anonymized ring data → supervised personalization (`Random Forest`, `XGBoost`, `LSTM`) in same framework.

---

## 5. Functional requirements

| ID | Requirement |
|----|-------------|
| WH-10 | User can view a calendar shaded by phase and logged/predicted periods (`CycleEngine.phaseName` + flex ratios drive shading). |
| WH-11 | Calendar may append a **synthetic predicted next cycle** for forward shading (`periodStart + cycleLen`). |
| WH-12 | User can log/edit cycle parameters (start, lengths) persisted via Supabase (`getCycles` / `saveCycle` → `user_cycles` with RLS owner policies, `20260806000000_missing_tables.sql`; `delete_user_account()` wipes). |
| WH-13 | User can log symptoms per date (`getSymptomsForDate` / `upsertSymptoms` **including `user_id`** → `user_symptoms`, RLS owner). |
| WH-14 | Current phase label is visible on screen and Home summary card when applicable (`_WomensHealthCard` / `WomensHealthMiniCard` / `CompactWomensHealthCard` all via `CycleEngine.phaseName` — keep aligned). |
| WH-15 | Prediction helpers (`womens_health_prediction_service`, normalized 0–100 thresholds documented) stay consistent with displayed dates; AWHE footnote informational-only always shown. |
| WH-16 | Offline: graceful degradation; network errors use OfflineNotice pattern. |
| WH-17 | Health Connect `Menstruation` type covered in permission set (8 types) where supported; no separate ring menstruation channel. |
| WH-18 | Two-path AWHE fusion: when history exists show calendar+phase final prediction with 92%-style confidence + reason string; when no history show phase+remaining-days prediction; confidence factors (availability/consistency/stability/history) documented in code. |

---

## 6. Integration points

- **Home:** `_WomensHealthCard` summary (keep formulas aligned with full screen via `CycleEngine`).  
- **Fall prediction (Flutter):** optional women’s-health layer weight when `isApplicable` / PMS flags — must not break scoring when WH off (redistribute weights).  
- **Profile:** gender changes should update visibility (WH-01/02).
- **HealthEngine:** WH does not own vitals thresholds; it *reads* `assessTemperature`/`assessHrv`/sleep/stress/activity assessments as AWHE sensor inputs.

---

## 7. Acceptance criteria

- [ ] Eligible user opens Women’s Health and sees calendar + current phase (`phaseName` edges: `day<=periodLen` menstrual, `<=13` follicular, `<=16` ovulating, else luteal; `cycleDay` clamped).
- [ ] Saving cycle data survives relaunch (online; `user_cycles` RLS).
- [ ] Symptom log for a day reloads after relaunch (`user_symptoms` with `user_id`).
- [ ] Ineligible gender does not show Home WH card.
- [ ] Predicted next period dates are consistent with entered cycle length (+ AWHE example path Late Luteal → 3 Sept 92% with reason string when physiology available).
- [ ] AWHE footnote informational-only visible; normalized-scale thresholds documented in service.
- [ ] `flutter test` includes `womens_health_prediction_test.dart` (eval 07).

---

## 8. Related

- [01-auth-onboarding.md](./01-auth-onboarding.md)  
- [05-fall-detection-safety.md](./05-fall-detection-safety.md) (optional W layer)
- `docs/archive/scratch_docx.txt`, `docs/archive/eval/01-CONFIRMED-BUGS-LOGIC.md` (§1.6/1.8/1.11), `docs/archive/eval/02-STUBS-PLACEHOLDERS-DEMO-DATA.md` (§2.7), `docs/engining/activity_engine.md` (CycleEngine), `docs/health-eng/*`
