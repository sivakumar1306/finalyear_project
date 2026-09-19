# 06 — Workouts

| Field | Value |
|-------|-------|
| **Status** | Shipped |
| **Key code** | `WorkoutProvider`, `WorkoutService.kt`, `lib/screens/workouts/*`, `lib/models/workout_model.dart` |

---

## 1. Purpose

Let users start guided sports sessions with live ring metrics, end sessions with a summary, and browse history stored in Supabase.

---

## 2. Categories & metrics

**12 categories** (150+ specific sports in pickers):

| Category | Typical live metrics |
|----------|----------------------|
| Running | HR, steps, distance, calories |
| Cycling | HR, distance, calories |
| Swimming | HR, calories |
| Outdoor Sports | HR, distance, calories |
| Gym & Fitness | HR, calories |
| Yoga | HR, calories |
| Dance | Category-defined |
| Combat Sports | Category-defined |
| Ball Sports | Category-defined |
| Water Sports | Category-defined |
| Winter Sports | Category-defined |
| Leisure & Recreation | Category-defined |

Metric set is driven by `WorkoutCategory.metrics` in `workout_model.dart`. UI must only show cards for metrics relevant to the active category.

---

## 3. User flow

1. Open Workouts hub (`/workouts` or nav).  
2. Pick category → sport sheet → pre-start info.  
3. `WorkoutProvider.startWorkout()`:
   - Persist resume state to SharedPreferences.
   - Start native `WorkoutService` foreground session.
   - Navigate to `ActiveWorkoutScreen`.  
4. Live polling of metrics (staggered HR/SpO2/BP/steps as implemented).  
5. Back press / end → confirm “End Workout?”.  
6. `stopWorkout()` computes deltas, shows summary, inserts Supabase `user_workouts` (or equivalent).

---

## 4. Functional requirements

| ID | Requirement |
|----|-------------|
| WO-01 | User can browse categories and sports and start a session only when ring connection policy is satisfied (document UX if disconnected). |
| WO-02 | Active workout uses a dedicated native foreground service distinct from the BLE monitor service. |
| WO-03 | Measurement loop and workout coordinate to avoid SDK command collisions. |
| WO-04 | App process death mid-workout: on relaunch, restore active workout UI from SharedPreferences. |
| WO-05 | Main shell tab bar cannot abandon an active workout (workout lock). |
| WO-06 | Completed sessions appear in history (e.g. 90-day window), grouped by date. |
| WO-07 | Spotlight cards for most recent sessions on hub. |
| WO-08 | History load handles offline via `OfflineNotice` pattern. |
| WO-09 | Ring sport buffer auto-merges on page open (`getSports` 0..6 → `SportPlusEntity` normalize → `insertWorkout` for unseen, RING badge, `TYPE_APP_*` start-second dedupe). |
| WO-10 | Manual outdoor workouts sample phone GPS (ring has no coordinates) → `user_workouts.locations` jsonb → polyline in `gps_trace_screen`. |

---

## 5. Data (completed session)

Persist at least:

- Sport / category identity  
- Start / end timestamps, duration  
- Aggregated metrics available for that sport (calories, steps, distance, HR stats as applicable)  
- `user_id` with RLS  

---

## 6. Acceptance criteria

- [ ] Start running workout shows HR (and other running metrics) while ring connected.  
- [ ] Ending workout saves row visible after relaunch (online).  
- [ ] Kill app mid-workout → reopen → resumes active workout screen.  
- [ ] Tab switch mid-workout is blocked.  
- [ ] History lists past sessions when Supabase reachable.
- [ ] Ring sport buffer merges without duplicates (reopen page twice → single rows).
- [ ] GPS trace renders a real polyline for an outdoor manual workout.

---

## 7. Related

- [02-device-pairing-ble.md](./02-device-pairing-ble.md)  
- [04-home-dashboard.md](./04-home-dashboard.md)  
