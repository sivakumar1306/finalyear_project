# 04 — Home Dashboard & Main Shell

| Field | Value |
|-------|-------|
| **Status** | Shipped |
| **Key code** | `lib/screens/main_shell.dart`, `lib/screens/home/*`, `lib/providers/main_tab_provider.dart`, `home_card_provider.dart` |
| **Status legend** | See `specs/README.md`: Shipped / Partial / Stub / Planned |

---

## 1. Purpose

Provide the primary daily health overview after login: connection status, key vitals at a glance, modes, and navigation into detail features. Home foregrounds `latest` values; averages are secondary; trends require `2+ days`; no bucket is ever faked.

---

## 2. Main shell

| ID | Requirement (integrated) |
|----|--------------------------|
| HOME-01 | Post-login shell has **three tabs**: Home, Assist, Settings (`IndexedStack` + custom bottom nav). |
| HOME-02 | Bottom nav follows design system: blur 28 / radius 20 / padding 16 (`AppTheme.kPad`/`kRadiusCard`), dark `#050505`, gold `#C9A86E` active state; SafeArea respected (`main_shell.dart:344` pattern; health details via Scaffold+AppBar own insets). |
| HOME-03 | **Workout lock:** if a workout is active, switching tabs is blocked; user is guided back to `ActiveWorkoutScreen`. |
| HOME-04 | On restart with in-progress workout (SharedPreferences), shell restores into active workout after provider init. |
| HOME-05 | Shell never computes thresholds: it resolves `latestHr/todayAvgHr` from `BleProvider`/Room then calls `HealthEngine.instance.assess*(v).label` (`docs/engining/architecture.md`: UI never computes thresholds/scores/date-keys/buckets). Deleted wrappers (`_spo2Status/_hrStatus/_hrvStatus/_sleepStatus`, `stressStatus`) must not return. |

---

## 3. Home screen content

### 3.1 Header / device

| ID | Requirement (integrated) |
|----|--------------------------|
| HOME-10 | Show user greeting / name from profile when available (fallback when `full_name` empty post-onboarding). |
| HOME-11 | Device pill shows connection state; tap opens ring scan sheet. |
| HOME-12 | Battery level when connected, if provided by SDK/events. |
| HOME-13 | Hero = latest: every card foregrounds the last-measured value with `avg` secondary and `avg · no fresh reading` stale pill after `30 min` (QRing parity `docs/qring/README.md`). Never freeze on AVG inertia (`87` anti-pattern); never inject `hourly[now.hour]=avg` — leave gap. Interval backfill comes from `LargeDataHandler` (HR/SpO₂/Temp/Sleep families via `BlePlugin.kt` + `BleOperateManager` + `CommandHandle`), not phone polling (`MeasurementLoopManager` 3-min round-robin is sparse). |

### 3.2 Metric cards

Home surfaces summary cards in `DESIGN.md` order (Greeting → Ring Status → Alarm → Activity → Stress → Sleep → HRV → SpO₂ → Heart Rate → Sport → Women's Health → Temperature → Blood Pressure), configurable via card settings where implemented. Status badges/colors MUST equal detail-screen classifiers (single source `HealthEngine` + `HealthConfig`).

| Card | Engine source (integrated thresholds) |
|------|---------------------------------------|
| Steps / activity score | `HealthEngine.calcActivityScoreWithGoals`: `60/25/15` weights; denoms from `GoalPrefs` (defaults 10000 / 1000 / 5.0 km); `s=(steps/g*60).clamp(0,60)+…`, round 0–100. Labels 0 Lack / <25 Sedentary / <50 Lightly / <75 Moderately / else Highly. Detail copy interpolates actual goals (`activityDescription()`). |
| Heart rate | `<60` Below (`hrvColor`) / `60–99` Normal (`success`) / `100+` Above (`danger`) |
| SpO₂ | `≥95` Normal / `≥90` Borderline (`amber`) / else Low (`danger`) |
| Stress | `<40` Relaxed / `<60` Normal (`0xFFFBBF24`) / `<80` Elevated (`stressColor`) / else High (`danger`) |
| HRV | `<20` Very Low / `<40` Low / `<60` Moderate / `<80` Good / else Excellent |
| Blood pressure | AHA/ACC via `bp_staging.dart` → `HealthEngine.assessBloodPressure` (`&&` only): `<120/80` Normal / `<130/80` Elevated / `<140/90` Stage-1 / else Stage-2 |
| Sleep | Score `(efficiency*0.4+deepPct*1.0+remPct*0.5)`; `≥80` Excellent / `≥60` Good / `≥40` Fair / `>0` Poor (canonical `80/60/40`; detail `85/70/55` drift fixed) |
| Temperature | `<36.0` Low / `≤37.2` Normal / `≤38.0` Elevated / else Fever (°C; display via `UnitPrefs`) |
| Women’s health (gender-gated) | `CycleEngine.phaseName(day,cycleLen,periodLen)`: ≤pLen menstruation, ≤13 follicular, ≤16 ovulating, else luteal; flex `13-pLen/3/len-16`; `cycleDay=now.diff(periodStart).inDays+1`; AWHE rules (temp↑+HRV↓+RHR↑ → Late Luteal; HRV↑+RHR↓+stable → Follicular; rising temp+RHR → Ovulation) feed confidence, not calendar alone |
| Fall prediction banner | Vitals-based risk only (not mechanical); see §3.4 |

| ID | Requirement |
|----|-------------|
| HOME-20 | Tapping a metric card navigates to its detail route (47 routes in `lib/app.dart`). |
| HOME-21 | Status badges/colors align with detail-screen classifiers (all via `HealthEngine.assess*`; `InsightsService` delegates BP cut-offs; no screen-local `_xxxStatus`). |
| HOME-22 | Pull-to-refresh reloads provider/native summaries AND `HealthConfig.refresh()` (remote `health_engine_config.config` deep-merge; missing keys fall back, never crash offline). |
| HOME-23 | Card visibility/order can be customized (`HomeCardProvider` / card settings) where feature is enabled. |
| HOME-24 | Buckets/charts on Home reuse `HourlyAggregator` (24-slot HR/SpO₂/stress/temp; 48-slot HRV `(h*60+m)~/30`; dual SBP/DBP; steps 96→24 `sublist(h*4).fold`), `TrendMath.avg/min/max/minMax/last7Bars`, `ScrubHelper.initialIndex/indexFromDx`; painters' `maxY/baseline` (HR 120/[120,100,80,60], SpO₂ 100/85, temp 40/34) are domain thresholds owned by `HealthConfig`, widget keeps only `barColor` callback. |
| HOME-25 | Empty vs offline is explicit: `OfflineNotice` when connectivity is the cause; `NotEnoughDataCard` for no-ring-data; `NotEnoughTrendDataCard` (`2+ days of data are needed. Keep wearing your ring.`) only when `!TrendMath.hasEnoughTrendData` (or `!hasEnoughBpTrendData` paired `sbp>0 && dbp>0` for BP) — never `every==0` single-day sparse chart. Product decision on `no ring data` vs `integration failure` copy remains deferred per eval 3.9. |

### 3.3 Alarm / phone mode segment

| ID | Requirement |
|----|-------------|
| HOME-30 | Segmented control for **Focus / Base / Prayer** modes on Home. |
| HOME-31 | Mode changes drive DND automation on Android (see [09](./09-phone-modes-reminders.md)). |

### 3.4 Fall prediction banner

| ID | Requirement |
|----|-------------|
| HOME-40 | When a predictive fall notification was opened or flag is set, Home shows a banner with take-action / dismiss. Copy must not present app as certified medical device. |
| HOME-41 | Support both cold start (`consumeFallPredictionFlag`) and warm resume (lifecycle) deep-link paths. |
| HOME-42 | Prediction SMS template (product-level, `docs/sms/emergency-alerting-system.md`): *"You might fall soon... multiple signs you might fall in 2–3 minutes. Take a seat and contact caretaker. — Sent by SUNDR Fall Detection"*; fall SMS: *"We have detected a fall... you may have potentially fallen. — Sent by SUNDR Fall Detection"*. Proposed upgrade adds name + reason + live map link. Per-contact SENT/DELIVERED/unknown via `getEmergencySmsStatus` (unknown after ~90 s); cloud backup (`supabase/functions/send-emergency-alert`, Twilio) and FCM `/companion-alert` receiving half exist but need client Twilio/Firebase + wiring (see OV-50). |

---

## 4. Side panel & secondary home UI

- Side panel (if present) for quick navigation / shortcuts (`GlassIconButton`/`SidePanel` stay in UI layer; parsing/bucketing lives in `ActivityEngine.parseIntervalJson` — handles `d/f/e/g` vs `timeIndex/walkSteps/calorie/distance`, `totalCalRaw≥1000?~/1000:>0?1:0`, `normalizeCalories` `raw≥500&&steps<4000?~/1000`, `distributeSteps` `(nowSlot-28).clamp(1,96)` — + `HourlyAggregator`).
- Ring scan sheet: primary pair path (see [02](./02-device-pairing-ble.md)).
- Card settings screen for layout preferences.

---

## 5. Design requirements

| ID | Requirement (integrated) |
|----|--------------------------|
| HOME-50 | Permanent dark theme; background `#050505`; accent gold `#C9A86E`. Text `0.95/0.65/0.35` white. Metric orbs: HR `#FF4757`, Sleep `#8B5CF6`, Stress `#F97316`, HRV `#2DD4BF`, SpO₂ `#38BDF8`, BP `#818CF8`, Temp `#FBBF24`, Women `#EC4899`, Steps `#F59E0B` (active `AppTheme` tokens; soft palette `#C96B6B…` was Phase-3 mistake, do not reintroduce). |
| HOME-51 | Prefer existing glass cards / shared widgets (`GlassCard`, `DataCard`, `StatCard`, etc.). Card = `rgba(255,255,255,0.06)` + `0.5px rgba(255,255,255,0.09)` + blur 28 + radius 20 (`AppTheme.kRadiusCard`) + padding 16 (`AppTheme.kPad`); orb `70px 40–60%` never obstructs; buttons 44–52 h radius 999; icon buttons 36–40; motion 200–400 ms fade/blur/scale 0.98→1.0, no bounce/elastic. Single `gold` + `goldBorder` (`0xFFC9A86E`); `card 0xFF111111` / `card2 0xFF1A1A1A` / `div 0xFF242424`; no `_kCard/_kBorder/_kGold` copies. |
| HOME-52 | Metrics identifiable within ~1 second (information-first); typography Title 24/600, Value 36–48/300 (dominates card), Card title 14/500, Support 12/400; charts 1–2 px strokes, grid `rgba(255,255,255,0.05)`, stroke `rgba(255,255,255,0.7)` + metric accent. |
| HOME-53 | `home_screen.dart` 3692-line monolith is DEFERRED debt (extraction = visual-QA risk); new Home UI must still reuse `lib/widgets/*` and add no new card/spacing/color patterns (`CLAUDE.md`). Inter-card gap is `SizedBox(height:20)` (fix-aa canonical; sleep dual-empty `867` pattern applies to stacked Home empties). |

---

## 6. Acceptance criteria

- [ ] Logged-in user lands on shell with Home selected.
- [ ] Cards show live or last-known values from `BleProvider` with `latest` hero + `30-min` stale pill; no fake hourly fill.
- [ ] Tap HR card opens heart rate detail; badge colors match `HealthEngine` bands (incl. BP `&&` staging, sleep `80/60/40`, activity goal-aware score).
- [ ] Active workout blocks tab switch.
- [ ] Scan sheet opens from device pill and can connect a ring.
- [ ] Fall banner appears when prediction flag is consumed.
- [ ] 1-day trend shows `NotEnoughTrendDataCard (2+ days)`; 2+ days shows `ScrubbableChart`; BP needs 2+ paired days.
- [ ] `flutter analyze` clean on touched files; `flutter test` 123 pass (TrendMath + HealthEngine edges incl. 79→Good/80→Excellent).

---

## 7. Related

- [03-vitals-monitoring.md](./03-vitals-monitoring.md)
- [05-fall-detection-safety.md](./05-fall-detection-safety.md)
- `DESIGN.md`
- `docs/qring/README.md` (hero-latest, LargeData families, 47 routes)
- `docs/health-eng/overview.md` + `thresholds.md` + `activity.md` (bands + goal-aware score)
- `docs/engining/overview.md` + `architecture.md` + `hourly_aggregator.md` + `activity_engine.md` (UI-vs-engine, buckets, CycleEngine)
- `docs/fix-aa/00-overview.md` + `01-sleep-spacing.md` + `02-trend-threshold.md` (`SizedBox 20`, `kMinTrendDays=2`, paired BP, `2+ days` copy)
- `docs/archive/eval/03-DESIGN-SYSTEM-UI-PADDING.md` (tokens, monolith + empty-state debt)
- `docs/sms/emergency-alerting-system.md` §§5/7/10 (templates, UX, success — product-level)
