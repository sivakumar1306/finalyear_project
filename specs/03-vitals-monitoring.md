# 03 — Vitals Monitoring

| Field | Value |
|-------|-------|
| **Status** | Shipped (temperature partial; continuous-sugar BLE stub) |
| **Key code** | `MeasurementLoopManager.kt`, `lib/screens/health/*`, `BleProvider`, Room entities, Supabase tables |

---

## 1. Purpose

Continuously collect ring vitals in the background, allow on-demand measurement, and present day + multi-day history with status classification.

---

## 2. Supported metrics

| Metric | Continuous loop | Manual measure | Detail route | Status |
|--------|-----------------|----------------|--------------|--------|
| Heart rate (BPM) | Yes | Yes | `/heart-rate` | Shipped |
| SpO₂ (%) | Yes | Yes | `/blood-oxygen` | Shipped |
| Blood pressure (SBP/DBP) | Yes | Yes | `/blood-pressure` | Shipped |
| Stress | Yes | No (loop only) | `/pressure` | Shipped |
| HRV (ms) | Yes | Yes (long ~50–60s) | `/hrv` | Shipped |
| Steps / cal / distance | Yes (snapshots) | Via activity | `/steps` | Shipped |
| Sleep stages + score | On demand from ring | N/A | `/sleep` | Shipped |
| Temperature | Optional / limited | Partial | `/temperature` | Partial |
| Sugar / lipids monitor state | Ring channel state (not glucose values) | Via `get/setHealthSettings` toggles | `/sugar-lipids` | Shipped (real reads; honest empty states) |
| Continuous sugar BLE | No | No (native returns `"[]"` stub) | — | Stub |
| Sport log (ring history) | Ring log 0..6 auto-merge | No | `/workouts` (+ `/sport-detail` stub) | Shipped (merge + RING badge) |

---

## 3. Background measurement loop

| ID | Requirement |
|----|-------------|
| VIT-01 | Native `MeasurementLoopManager` round-robins enabled vitals while connected and loop enabled. |
| VIT-02 | Each sample is written to local Room with `source` (e.g. `auto_cycle`) and timestamp. |
| VIT-03 | New readings notify fall analysis and Flutter (`NewReadingEvent` / EventChannel). |
| VIT-04 | Manual UI measurement and workout measurement coordinate so SDK is not double-driven (`MeasurementCoordinator`). |
| VIT-05 | Per-vital enable + interval configurable from Health Settings and mirrored on detail screens where applicable. |
| VIT-06 | Production target cycle cooldown is ~60s; **current code may still use a shorter test cooldown** — must be verified before release. |

---

## 4. Data tiers (detail screens)

Standard pattern for HR, SpO2, BP, HRV, stress, steps, temperature:

| Tier | Source | Use |
|------|--------|-----|
| Today | Room via `BleService.getTodaySummary` / `getReadings` | Offline-capable charts |
| Selected past day | Supabase | History day picker |
| Multi-day trend | Supabase (e.g. 7-day) | Trend charts |

Manual “Measure Now”:

1. Blocking native measurement with timeout (8s–90s by vital; HRV longer).  
2. Update `BleProvider` latest value.  
3. Upsert cloud history via **incremental** avg/min/max/count merge (not blind overwrite).

---

## 5. Classification thresholds (product)

### Blood pressure (`_bpStatus`)

| Label | Approx rule |
|-------|-------------|
| Normal | Below elevated cutoffs |
| Elevated | ≥ 120 systolic or related elevated band |
| Stage 1 | ≥ 130/80 band |
| Stage 2 | ≥ 140/90 band |

### Stress

Bands around 40 / 60 / 80 → Relaxed / Normal / Elevated / High.

### HRV

Labels from Very Low → Excellent (screen-defined buckets).

### Sleep score

```
score = efficiency * 0.4 + deepPct * 1.0 + remPct * 0.5
```

Stages: deep, light, REM, awake (+ timeline UI).

### Activity score (Home + Steps)

Same formula must stay consistent across `home_screen.dart` and `steps_screen.dart` (currently duplicated — treat as single product formula).

---

## 6. Charting requirements

| ID | Requirement |
|----|-------------|
| VIT-10 | HR: 24 hourly buckets for today. |
| VIT-11 | HRV: finer (e.g. 48 half-hour) buckets. |
| VIT-12 | Steps: 15-minute interval bars (e.g. 96/day). |
| VIT-13 | BP: dual series (systolic + diastolic). |
| VIT-14 | Offline network failures show `OfflineNotice`, not empty “no data” when connectivity is the cause. |
| VIT-15 | No third-party chart package required; custom painters are acceptable. |

---

## 7. Functional requirements (summary)

| ID | Requirement |
|----|-------------|
| VIT-20 | User can open each vital screen from Home cards and named routes. |
| VIT-21 | Pull-to-refresh / re-query updates latest values when connected. |
| VIT-22 | Steps aggregate is **day max** (ring cumulative counter), not sum of snapshots. |
| VIT-23 | Sleep is pulled from ring (not necessarily every loop cycle). |
| VIT-24 | Health settings toggles persist to ring/native and affect the loop. |

---

## 8. Acceptance criteria

- [ ] With ring connected, automatic HR/SpO2/etc. appear on Home within a few loop cycles.
- [ ] Manual measure updates UI and survives app restart via Room and/or cloud.
- [ ] Past-day history loads when online; offline today still works from Room.
- [ ] BP status labels match threshold table.
- [ ] Sleep screen shows stages + score when ring has sleep data.
- [ ] Stress screen has no broken “manual measure” path.

---

## 9. Related

- [04-home-dashboard.md](./04-home-dashboard.md)  
- [11-data-sync-storage.md](./11-data-sync-storage.md)  
- `architecture/Data_Layer.md`  
