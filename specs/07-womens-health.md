# 07 — Women’s Health / Cycle Tracking

| Field | Value |
|-------|-------|
| **Status** | Shipped |
| **Key code** | `womens_health_screen.dart`, `womens_health_models.dart`, `womens_health_prediction_service.dart`, Supabase cycles/symptoms |

---

## 1. Purpose

Provide menstrual cycle calendar, phase awareness, symptom logging, and simple predictions for eligible users.

---

## 2. Access control

| ID | Requirement |
|----|-------------|
| WH-01 | Women’s Health entry points (Home card, route `/womens-health`) are **gender-gated** from profile. |
| WH-02 | Users outside the eligible gender configuration must not see the card (or see a clear non-applicable state if navigated deeply). |

---

## 3. Core concepts

| Concept | Definition (product) |
|---------|----------------------|
| Period start | User-logged start date of menses |
| Cycle length | Days between period starts (user-set or default) |
| Period length | Days of bleeding (user-set or default) |
| Day of cycle | Derived from period start |
| Phases | Menstrual, Follicular, Ovulation, Luteal |
| Fertile window / ovulation | Derived from cycle length (calendar model) |
| Next period | Predicted from period start + cycle length |

**Note:** Current product math is primarily **calendar-based**. Wearable-derived cycle signals (temp/HRV trends) may appear in fall-prediction layer docs but are not the sole source of WH phase equations unless implemented end-to-end.

---

## 4. Functional requirements

| ID | Requirement |
|----|-------------|
| WH-10 | User can view a calendar shaded by phase and logged/predicted periods. |
| WH-11 | Calendar may append a **synthetic predicted next cycle** for forward shading. |
| WH-12 | User can log/edit cycle parameters (start, lengths) persisted via Supabase (`getCycles` / `saveCycle`). |
| WH-13 | User can log symptoms per date (`getSymptomsForDate` / upsert). |
| WH-14 | Current phase label is visible on screen and Home summary card when applicable. |
| WH-15 | Prediction helpers (`womens_health_prediction_service`) stay consistent with displayed dates. |
| WH-16 | Offline: graceful degradation; network errors use OfflineNotice pattern. |

---

## 5. Integration points

- **Home:** `_WomensHealthCard` summary (keep formulas aligned with full screen).  
- **Fall prediction (Flutter):** optional women’s-health layer weight when `isApplicable` / PMS flags — must not break scoring when WH off (redistribute weights).  
- **Profile:** gender changes should update visibility.

---

## 6. Acceptance criteria

- [ ] Eligible user opens Women’s Health and sees calendar + current phase.  
- [ ] Saving cycle data survives relaunch (online).  
- [ ] Symptom log for a day reloads after relaunch.  
- [ ] Ineligible gender does not show Home WH card.  
- [ ] Predicted next period dates are consistent with entered cycle length.

---

## 7. Related

- [01-auth-onboarding.md](./01-auth-onboarding.md)  
- [05-fall-detection-safety.md](./05-fall-detection-safety.md) (optional W layer)  
