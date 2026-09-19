# 00 — Product Overview

| Field | Value |
|-------|-------|
| **Product name** | SUNDR (package: `sundr`) |
| **Category** | Smart-ring companion / luxury health monitoring |
| **Primary platform** | Android (BLE + foreground services) |
| **Backend** | Supabase (Auth + Postgres); separate REST chat API |
| **Hardware** | QRing-class BLE smart ring via vendor AAR (`android/app/libs/qring_sdk_1.0.0.55.aar`) |
| **Status** | Pre-release / active development |
| **Codebase scale (verified 2026-09-19)** | `lib/` 204 dart · `BlePlugin.kt` ~3925 lines · `MeasurementLoopManager` ~752 lines · `qring_unpack` 3386 entries · source APK `com.app.cq.ring v1.0.1.131` |
| **Status legend** | See `specs/README.md`: Shipped / Partial / Stub / Planned |

---

## 1. Vision

SUNDR is a premium companion app for a smart ring. It continuously monitors vitals, surfaces calm scientific insights, and differentiates on **safety**: cardiovascular / syncope-oriented fall *risk* prediction plus phone-motion *active* fall detection with local alerts.

Visual and product positioning (from `DESIGN.md`): closer to **Whoop / Oura / Apple Health** than a flashy fitness tracker — premium, minimal, dark, trustworthy.

| ID | Vision requirement (integrated) |
|----|-------------------------------|
| OV-01 | Bring Sundr to **QRing functional parity where it matters for health accuracy**, then extend with premium safety (fall risk, Health Connect) and luxury UX (`DESIGN.md` `#C9A86E` glassmorphism). Do NOT replicate QRing packer obfuscation or light theme. Source: `docs/qring/README.md`. |
| OV-02 | Adopt the Adaptive Women's Health Engine (AWHE) vision (`docs/archive/scratch_docx.txt`): physiology-based cycle prediction (temp + HRV + RHR + sleep + stress + activity) instead of calendar-only (`last period + average length` assumes regular; irregularity from hormones/stress/illness/sleep is common). Pipeline: Sensors → Collection → Preprocessing (clean/normalize/artifact-removal) → Rule-based Phase Estimation → Prediction (calendar+phase if history, else phase+expected-remaining e.g. Late Luteal + 3 days → 3 September) → Confidence & Explainability (availability/consistency/stability/history, e.g. 92% + reasons) → Mobile. Rule-based now (explainable, immediately functional); ML (Random Forest/XGBoost/LSTM) only when sufficient anonymized data exists. |
| OV-03 | Emergency alerting vision (`docs/sms/emergency-alerting-system.md`, product-level): a possible fall (phone accelerometer + vitals corroboration — ring SDK exposes no continuous motion, so phone-side not ring-side) must alert every saved emergency contact instantly. Three-part target: (1) phone SMS best-effort free, (2) cloud SMS backup guaranteed (Twilio), (3) in-app instant alert to linked SUNDR contacts (FCM). No health data in messages — name + reason + live map link only; two-sided link consent; every alert logged. |

---

## 2. Goals

### Primary

1. Pair and keep a reliable BLE connection to the ring in the background.
2. Collect and display core vitals (HR, SpO2, BP, stress, HRV, steps, sleep, temperature) with offline-first “today” data.
3. Persist durable history in Supabase for trends and cross-session continuity.
4. Provide fall risk scoring and corroborated fall detection with local user alerts.
5. Support workouts, women’s health (when applicable), phone Focus/Prayer modes, and an AI health assistant.

| ID | Goal / non-goal (integrated) |
|----|------------------------------|
| OV-10 | Offline-first `today`: Room `qring_local.db` is source of truth; Supabase is history. `ReadingRepository.daySummaryFromRaw` + `DailyVitalSummaryEntity` rollup. |
| OV-11 | Ring-blob fidelity: ring logs autonomous interval blobs even when phone off (`heart_rate_detail` 1/day `interval/index_str/value TEXT`). Phone polling alone (`MeasurementLoopManager` 3 min round-robin) is sparse — MUST backfill via `LargeDataHandler` (4 interval families HR/SpO₂/Temp/Sleep). |
| OV-12 | Hero = latest, stats = avg/min/max: show last-measured badge + discrete dots; AVG inertia (`87` freeze) is anti-pattern. Every vital detail + home card foregrounds `latest` with `avg` secondary and `avg · no fresh reading` stale pill after `30 min`. Never inject `hourly[now.hour]=avg` when no slot — leave gap (QRing leaves slot empty). |
| OV-13 | UI never computes thresholds/scores/date-keys/bucket-math. Pure engines (`lib/utils/`, `lib/services/health_engine/*_engine.dart`: Inputs → Outputs, no BuildContext/SharedPreferences/Supabase) + service-engines (wrap `HealthConfig`/`GoalPrefs`/`SupabaseService`/`LocalVitalsService` for one-liner UI calls). `HealthEngine` is single source of truth for every band/color/score/range/tip/comment; fall prediction stays separate (`lib/services/fall_prediction/`) but will consume `HealthEngine` thresholds. |

### Non-goals (current release)

- Medical device certification or clinical diagnosis claims.
- Mechanical trip-and-fall prediction from ring IMU (SDK does not expose continuous accel/gyro).
- Caregiver cloud push and auto-dial emergency (deferred; see fall spec).
- Full iOS parity for BLE background measurement and DND automation.
- Light mode UI.

---

## 3. Personas

| Persona | Needs | Integrated detail |
|---------|-------|-------------------|
| **Everyday wearer** | Pair ring once, see today’s vitals and sleep, set goals, work out. | Hero-latest + 30-min stale pill (OV-12); activity score goal-aware (OV-40). |
| **At-risk adult / caregiver-aware user** | Fall risk awareness, emergency contacts, “I’m okay” dismiss path. | Phone SMS SENT/DELIVERED/unknown receipts (~90 s settle); cloud backup + FCM pending client Twilio/Firebase (OV-50). |
| **Wellness-focused user** | Cycle tracking, stress/HRV trends, AI assist Q&A. | AWHE: Follicular = HRV↑ RHR↓ temp-stable; Ovulation = temp-rise + RHR-rise; Late Luteal = temp↑ HRV↓ RHR↑; Luteal = higher temp, lower HRV, higher RHR, stress-sensitive. Phase names via `CycleEngine.phaseName` (≤pLen menstruation, ≤13 follicular, ≤16 ovulating, else luteal; flex `13-pLen/3/len-16`). |
| **Power user** | Health intervals, display/touch settings, OTA firmware, Health Connect. | `qc_setting_*` 42 ids 60% parity; OTA `DfuHandle` real; `firmware_updates` catalog live. |
| **Client / product owner** (SMS doc audience) | Plain-English safety story, cost control. | Needs to supply Twilio trial + number (~$1/mo + ~$0.0075/text) and free Firebase project + config file; phone SMS stays free, cloud backup billed only when used. |

---

## 4. Platforms & stack (summary)

| Layer | Tech (integrated) |
|-------|-------------------|
| UI | Flutter, Provider, permanent dark theme (`#050505`, gold `#C9A86E`) |
| Native critical path | Kotlin foreground service, Room DB (`QRingDatabase.kt`, `ReadingEntities.kt` 216 lines 14 entities: `reading_heart_rate/spo2/hrv/temperature/blood_pressure/stress/steps` + `daily_vital_summary` `(vital,dayEpochMs)` PK + `fall_risk_log`/`fall_event`/`emergency_contact`/`phone_mode_session`/`measurement_*`), vendor BLE SDK via `BlePlugin.kt` `LargeDataHandler` + `BleOperateManager` + `CommandHandle` (`IntervalHeartRateEntity{dayIndex,interval,array:List<Int>}`, `IntervalBloodOxygenEntity`, `IntervalTemperatureEntity{array:List<Float>,values:List<IntervalTemperature>}`, `IIntervalHeartRateCallback`) |
| BLE channel | Dart `lib/config.dart:20-23` exactly matches Kotlin `com.medxai.sundr/ble`, `/ble_events`, `/phone_mode` (eval-confirmed good) |
| Cloud | Supabase Auth + Postgres (RLS) — single squashed `supabase/migrations/00000000000000_init.sql` (34 tables incl. `falls`, `user_quran_bookmarks`, `friends`, `nutrition`, `watchface`, `health_engine_config`); anon key publishable by design (RLS gate), never service-role; package `com.medxai.sundr` consistent Gradle/manifest/Kotlin |
| Chat | External REST API (`CHAT_API_BASE_URL`) |
| Design | `DESIGN.md` glassmorphism + gold accent `#C9A86E`; `AppTheme.card 0xFF111111` / `card2 0xFF1A1A1A` / `div 0xFF242424` / `gold 0xFFC9A86E`; `GlassCard` blur 28 radius 20 padding 16; `AppTheme.kPad` 16 + `kRadiusCard` 20 |
| Engines | `lib/utils/date_keys.dart`, `formatters.dart`, `hourly_aggregator.dart` (24/48/96), `trend_math.dart` (`kMinTrendDays=2`, `hasEnoughTrendData`, `hasEnoughBpTrendData`), `scrub_helper.dart`, `bp_staging.dart` (alias → `HealthEngine`); `lib/services/health_engine/` (`health_engine.dart` facade, `health_config.dart` + `health_engine_config.config` JSONB `supabase/migrations/20260905000000_health_engine_config.sql`, `models.dart`, `sleep/activity/temperature/cycle_engine.dart`), `history_service.dart`, `measurement_flow.dart` |

See `architecture/Overview.md` for diagrams.

---

## 5. Feature map

| Domain | Spec | Status |
|--------|------|--------|
| Auth & onboarding | [01](./01-auth-onboarding.md) | Shipped |
| Device pairing & BLE | [02](./02-device-pairing-ble.md) | Shipped |
| Vitals monitoring | [03](./03-vitals-monitoring.md) | Shipped (temp partial) |
| Home & shell | [04](./04-home-dashboard.md) | Shipped |
| Fall detection & safety | [05](./05-fall-detection-safety.md) | Partial (live but unvalidated prediction; Layer-3 history/peaks wired, cloud backup planned) |
| Workouts | [06](./06-workouts.md) | Shipped (ring sport auto-merge + phone GPS trace live) |
| Women’s health | [07](./07-womens-health.md) | Shipped |
| AI Assist | [08](./08-assist-chat.md) | Partial (backend dependency) |
| Phone modes & reminders | [09](./09-phone-modes-reminders.md) | Shipped (Android) |
| Settings & device | [10](./10-settings-device.md) | Partial (some stubs) |
| Data & sync | [11](./11-data-sync-storage.md) | Shipped |
| Non-functional | [12](./12-non-functional.md) | Mixed |

### 5.1 QRing parity phase map (snapshot 2026-08-27, counts re-verified 2026-09-19)

| Phase | Scope | Status | Completion | Doc |
|-------|-------|--------|------------|-----|
| **1** | Core vitals unified flow (HR/SpO₂/HRV/Temp) — latest hero, interval backfill, median de-bias, cloud polish, home/cards | Completed 2026-08-26 | 100% — all `latest` heroes, interval HR/SpO₂/Temp, `MeasurementLoopManager` lower-median, 123 tests pass (was 80 at completion) | `phase-1-core-vitals-flow.md` |
| **2** | Detailed health: ECG, Breath, Blood Sugar continuous/Lipids, Pressure interval, One-Key | In Progress 2026-08-27 13:00 — models + migration + 3 screens + routes `/ecg /breath /blood-sugar` live, wrappers `getEcgHistory` | 45% — scaffolding done, native BLE `EcgReq` pending | `phase-2-detailed-health.md` |
| **3** | Religious & social: Quran/Qibla, Muslim Goal V2, Friends/Lover, Nutrition | In Progress 2026-08-27 14:00 — `QiblaService` bearing, stubs + routes `/quran /qibla /friends /nutrition` | 35% — 5 stubs `GlassCard` `DESIGN.md` | `phase-3-social-religious.md` |
| **4** | Multimedia & sport granularity: Watchface Store, Album/Ebook/Music, 20 sport types, GPS trace | In Progress 2026-08-27 14:00 — `watchface_store` stub + route `/watchface` | 20% — hub exists, per-type detail + GPS pending | `phase-4-multimedia-sport.md` |
| **5** | System polish: `qc_setting_*` parity (42 ids), OTA, `LargeDataHandler` families, Supabase 34 tables, release signing | In Progress — 4 interval families (HR/SpO₂/Temp/Sleep), 34 tables | 35% — settings 60% parity | `phase-5-system-polish.md` |

### 5.2 Progress overview (2026-08-27 14:00)

| Metric | QRing | Sundr Before | Sundr Now |
|--------|-------|--------------|-----------|
| `LargeDataHandler` families | 9 | 4/9 (44%) | 4 interval families HR/SpO₂/Temp/Sleep wired (was 7/9 in earlier draft — recounted 2026-09-19: 4) |
| Supabase tables | 40+ | 26 | 34 (single squashed `00000000000000_init.sql`, incl. `falls`, `user_quran_bookmarks`, `friends`, `nutrition`, `watchface`, `health_engine_config`) |
| Named routes `lib/app.dart` | ~240 Act. | 21 | 47 |
| Health screens hero `latest` | 100% | 25% (only Temp/BP/Stress) | 71% (HR/SpO₂/HRV added) +46% |
| `qc_setting_*` parity | 42 ids | 60% | 60% (no regression) |
| Glass screens new | — | — | 8 new `breath/ecg/blood-sugar/quran/qibla/friends/nutrition/watchface` all `AppTheme.bg` `GlassCard` `MetricChartCard` (+8) |

### Known stub / incomplete surfaces (verified 2026-09-19)

- Sugar & lipids detail — **implemented**: real ring monitor-state reads + channel toggles via `get/setHealthSettings` (continuous-glucose BLE itself remains a stub returning `"[]"`).
- Ring sport history — **implemented**: `getSports` 0..6 auto-merge into `user_workouts` with RING badge; per-type detail screen + GPS trace screen exist (depth pending).
- Select notifications — **partial**: choices persist (`NotificationPrefs`) and gate live phone alerts (`BleProvider`); ring-side persistence still open.
- Measurement log — **implemented**: per-vital History entry + flag-gated settings entry (`AppConfig.includeMeasurementLog`).
- OTA cloud catalog — **implemented**: `firmware_updates` releases list in-app; auto-update prompts still future.
- Caregiver push, cloud SMS backup, full-screen fall overlay (planned — receiving half of push exists: FCM token registration + `/companion-alert` display, dormant without Firebase config).
- Emergency auto-call — implemented behind an explicit opt-in settings toggle; phone SMS countdown (30s) + cancel + per-contact SENT/DELIVERED receipts live.
- Release signing keystore (debug signing used for release builds today).

---

## 6. Information architecture

```
Splash
 ├─ Auth (login / sign-up / recovery)
 ├─ Onboarding (name → age → gender → height → weight → [emergency] → pair ring optional)
 └─ MainShell (3 tabs)
      ├─ Home (dashboard, scan sheet, mode selector, fall banner)
      ├─ Assist (chat + history)
      └─ Settings (device, health, account, fall detection, …)
```

Named routes are defined in `lib/app.dart` (47 routes, incl. `/home /ecg /breath /blood-sugar /quran /qibla /friends /nutrition /watchface /companion-alert`). Deep feature screens use routes; flow screens (auth steps, chat, active workout) often use `Navigator.push`.

---

## 7. Core design principles (product)

1. **Offline-first for “today”** — Local Room is source of truth for continuous readings; cloud is history and multi-day trends.
2. **Hardware-native for reliability** — BLE loop, fall analysis, and background sync run in Kotlin, not only Dart.
3. **Safety over hype** — Fall *prediction* is scoped to syncope/cardiovascular signals, not general mechanical falls.
4. **Information first** — Metrics readable within ~1 second; UI effects support data (`DESIGN.md`).
5. **User control on emergencies** — Local alert with dismiss; auto-call is not current scope.
6. **Engine-owned truth** — `HealthEngine` + `HealthConfig` own every threshold/score/label; `AppTheme` owns every color/spacing token; `GlassCard` (blur 28 / radius 20 / padding 16) is the only card container; trend gating is `TrendMath.kMinTrendDays=2` with `2+ days` copy.

| ID | Product requirement (integrated) |
|----|---------------------------------|
| OV-20 | Card system MUST be `rgba(255,255,255,0.06)` + `0.5px rgba(255,255,255,0.09)` + blur 28 + radius 20 + padding 16 via `GlassCard`/`AppTheme.kPad`/`kRadiusCard`; orb `70px 40–60%` never obstructs; gold `#C9A86E` is the only primary accent; no pure-white bg, no new colors without approval. Token drift fixed: `_kCard/_kBorder/_kSec2` derive from `AppTheme.card/div/textSec`, single `gold` + `goldBorder` (removed `goldLight/base/goldAccent`), `explainable_ai_dashboard` text → `AppTheme.textPrimary`, `StatCard` dead `know more >` removed, SafeArea verified on all top-level screens (home:819, main_shell:344, settings:101/225; health via Scaffold+AppBar). Deferred debt: `home_screen.dart` 3692-line monolith extraction; empty-state `no ring data` vs `integration failure` copy decision; residual 12/14 px paddings + 14/16 px radii in list rows (not DESIGN cards). |
| OV-21 | Health bands (single source `HealthConfig`, overridable via `health_engine_config.config` JSONB, deep-merge fallback, `HealthConfig.refresh()` on Home pull): sleep score `(efficiency*0.4+deepPct*1.0+remPct*0.5)` bands 80/60/40 → Excellent/Good/Fair/Poor; HR <60 Below / <100 Normal / else Above; SpO₂ ≥95 Normal / ≥90 Borderline / else Low; HRV <20 Very Low / <40 Low / <60 Moderate / <80 Good / else Excellent; stress <40 Relaxed / <60 Normal / <80 Elevated / else High; BP `<120/80` Normal, `<130/80` Elevated, `<140/90` Stage-1 (`&&` not `\|\|`), else Stage-2; temp <36.0 Low / ≤37.2 Normal / ≤38.0 Elevated / else Fever (°C, `UnitPrefs` converts display). |
| OV-22 | Activity score (Home badge + Steps, identical): `stepsW=60, calW=25, distW=15` (sum 100); denoms from `GoalPrefs` (defaults 10000 / 1000 / 5.0 km → 5000 m; config `thresholds.activity.*Denom` fallback); `s=(steps/goalSteps*60).clamp(0,60)`, `c=(cals/goalCals*25).clamp(0,25)`, `d=(distM/goalDistM*15).clamp(0,15)`; `score=(s+c+d).round().clamp(0,100)`. Labels: 0 Lack / <25 Sedentary / <50 Lightly / <75 Moderately / else Highly. Goal change → `HealthConfig.notifyGoalChanged()` + `invalidateActivityCache()`; description interpolates actual denoms/weights. |
| OV-23 | Trend/empty rules: `TrendMath.kMinTrendDays=2`; `hasEnoughTrendData(List<num>)` = non-zero ≥2; `hasEnoughBpTrendData(sbp,dbp)` = paired `sbp>0 && dbp>0` ≥2 days (not `\|\|`). Copy `NotEnoughTrendDataCard`: `2+ days of data are needed. Keep wearing your ring.` (was `4+`). Sleep dual-empty gap is unconditional `SizedBox(height:20)` at `sleep_screen.dart:867` (matches HR:757, stress:699, SpO₂:778). Buckets: `HourlyAggregator` 24-slot (HR/SpO₂/stress/temp), 48-slot HRV `(h*60+m)~/30`, dual SBP/DBP, steps 96→24 `sublist(h*4).fold`; `TrendMath.avg/avgDouble/min/max/minMax/last7Bars`; `ScrubHelper.initialIndex/indexFromDx`. |
| OV-24 | Evaluation posture (2026-08-06 eval, code deltas to 2026-09-19): app is real (BLE+Room+sync+fall+SMS, `flutter analyze` clean) but not release-ready at snapshot. Severity: **[CRIT]** silent wrong health data / real calls to fake numbers / build failure; **[HIGH]** silently no-op or blocked workflow; **[MED]** inconsistency/dead UX/dup/ops risk; **[LOW]** cosmetic. In good shape: MethodChannel match, real native HR/BP/SpO₂/steps/sleep/HRV/stress/temp/camera/DND/reminders/OTA-`DfuHandle`, RLS, Room, `proguard-rules.pro` Room/Gson keeps, thorough `clearPersonalData` (stops loops, drops DB, clears prefs, cancels notifications). Not-a-bug: Supabase URL+anon key publishable (RLS gate); `com.medxai.sundr` consistent. Snapshot gaps closed since: migrations → 34-table squash, tests → 123/15 files. Remaining release gates live in specs 02/05/10/11/12. |

---

## 8. Success metrics (product-level)

| Metric | Intent |
|--------|--------|
| Pair success rate | Users complete first ring bind without support |
| Background uptime | Foreground service reconnects after kill/reboot |
| Sync lag | Background readings appear in cloud within one sync cycle |
| Fall motion FP rate | Low false positives after g-unit threshold fix (measure on-device) |
| Fall prediction validity | Correlate logged scores vs real near-falls (open research task) |
| Crash / incident volume | `app_incidents` table + client reporting |

| ID | Success / client requirement (SMS + eval, product-level only) |
|----|---------------------------------------------------------------|
| OV-50 | After alerting work: (1) possible fall auto-alerts every saved contact via phone SMS (cloud backup pending wiring); (2) SUNDR contacts get instant in-app alert if Firebase configured + link accepted (link UI pending); (3) every phone text carries SENT/DELIVERED/unknown receipt in `getEmergencySmsStatus` snapshot (unknown after ~90 s; no phone-vs-backup split yet); (4) offline backup covers once phone regains internet (requires wiring — not yet true); (5) no silent failures — permission/signal errors surface in snapshot. Client supplies Twilio trial + number and Firebase project + config; work plan order: cloud tables → backup SMS → in-app → linking → phone improvements → screens → E2E test. |
| OV-51 | Release readiness is measured by closing eval CRIT/HIGH (fake-contact seeding `9999999999`/`+91 000 000 0000`, BP `\|\|` staging, 7 native stubs `BlePlugin.kt:318-334`, `compileSdk 36 < targetSdk 37` + debug-keystore fallback `build.gradle.kts:22,33,53-60`, migration/code parity) plus NFR suite (123 tests/15 files + `SupabaseService` mapping + `BleProvider` transitions + WH baseline review). |

---

## 9. Related docs

- `architecture/Overview.md` — system diagram
- `DESIGN.md` — visual system
- `FALL_DETECTION_STATUS.md` — fall shipping status
- `KNOWLEDGE_TRANSFER.md` — engineer onboarding
- `docs/qring/README.md` + `phase-*.md` — parity roadmap
- `docs/archive/eval/00-EXECUTIVE-SUMMARY.md` + `03-DESIGN-SYSTEM-UI-PADDING.md` — eval baseline
- `docs/engining/overview.md` + `architecture.md` + `hourly_aggregator.md` + `activity_engine.md` — engine extraction
- `docs/health-eng/overview.md` + `thresholds.md` + `activity.md` — HealthEngine truth
- `docs/fix-aa/00-overview.md` + `01-sleep-spacing.md` + `02-trend-threshold.md` — spacing + trend gating
- `docs/sms/emergency-alerting-system.md` — client-facing alerting (product-level)
- `docs/archive/scratch_docx.txt` (AWHE) — women's-health vision
