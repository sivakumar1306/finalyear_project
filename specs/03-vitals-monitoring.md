# 03 — Vitals Monitoring

| Field | Value |
|-------|-------|
| **Status** | Shipped (temperature history backfill blocked; continuous-sugar BLE stub `"[]"`; ECG native `EcgReq` pending) |
| **Key code** | `MeasurementLoopManager.kt`, `lib/screens/health/*`, `BleProvider`, `HealthEngine`, `SleepEngine`, `ActivityEngine`, `TemperatureEngine`, `HourlyAggregator`, `TrendMath`, `DateKeys`, Room entities, Supabase tables |

---

## 1. Purpose

Continuously collect ring vitals in the background, allow on-demand measurement, and present day + multi-day history with status classification. All scoring, bands, colors, copy, date math, bucketing, and parsing live in engines (`lib/services/health_engine/*`, `lib/utils/*`). UI only does layout/navigation/theming per `DESIGN.md` / `CLAUDE.md:4` (reuse `GlassCard`/`MetricStatCard`/`ScrubbableChart`, `rgba(255,255,255,0.06)` + `border 0.5px rgba(255,255,255,0.09)` + `blur 28` + `radius 20` + `padding 16`).

---

## 2. Supported metrics

| Metric | Continuous loop | Manual measure | Detail route | Ring history backfill | Status |
|--------|-----------------|----------------|--------------|----------------------|--------|
| Heart rate (BPM) | Yes | Yes (streaming + list fallback) | `/heart-rate` | ✅ `_pullRingHistory` → `array`/`mHeartRateArray` unsigned 30–220 → `upsertHr` | Shipped |
| SpO₂ (%) | Yes | Yes | `/blood-oxygen` | ✅ `_pullRingHistory` → `array`/`minArray`/`maxArray` 1–100 → `upsertSpo2` | Shipped |
| Blood pressure (SBP/DBP) | Yes (poll-only; SDK has no `IntervalPressureEntity`) | Yes | `/blood-pressure` | ✅ `_pullRingHistory` → `{time,sbp,dbp}` s/ms auto-normalize, keep 70–250/40–150 → `insertBp(source:ring_history)` | Shipped |
| Stress (pressure 0–100) | Yes | No (loop only) | `/pressure` | ✅ `_pullRingHistory` → `pressureArray` bytes unsigned drop `0xFF` clamp 0–100 → `insertStress` | Shipped |
| HRV (ms) | Yes | Yes (long ~50–60s) | `/hrv` | ✅ `_pullRingHistory` → `d` or `pressureArray` (unsigned drop `0xFF`) → `upsertHrv` | Shipped (today path `_parseAndSaveHrv` reads only `d`; history covers both keys) |
| Steps / cal / distance | Yes (snapshots) | Via activity | `/steps` | ✅ `_pullRingHistory` → `ActivityEngine.parseIntervalJson` (`d/f/e/g`) + `_saveToDb` per day | Shipped |
| Sleep stages + score | On demand from ring | N/A | `/sleep` | ✅ `_loadHistory` → `getSleepList(0,7)` (reference impl, pre-existing) | Shipped |
| Temperature | Optional / limited | Partial (`manualTemperature`, `manualTemperature_POC`) | `/temperature` | ❌ blocked: `IntervalTemperatureEntity{array,values[{value1..3}],interval}` semantics unverified; `TemperatureEngine` Map-case keys don't match — needs one live-ring `getTemperatureList` sample logged once | Partial |
| Sugar / lipids monitor state | Ring channel state (not glucose values) | Via `get/setHealthSettings` toggles (temperature/rri/emotion via `SugarLipidsSettingReq` + `BloodSugarLipidsSettingRsp`) | `/sugar-lipids` | n/a (app-side; continuous-sugar channel is `"[]"` stub) | Shipped (real reads; honest empty states; no hardcoded `'--'`, no raw-JSON dump) |
| Continuous sugar BLE | No | No (native returns `"[]"` stub) | — | n/a (`app_continuous_sugar(mac,date_str,timestamp,min_sugar,max_sugar,hour)` CGM 1/h only on premium ring, gate via `getDeviceSupport`) | Stub |
| ECG | No | 30s capture (mocked without ring) | `/ecg` | n/a | Scaffolding done; native `EcgReq` + `LargeDataHandler.syncBloodSugar` + `ReadingRepository.insertEcg` + `tryWriteEcg` pending |
| Breath | Phone-timer only (no ring BLE; live HR via `manualModeHeart`) | 2-min session | `/breath` | n/a | Scaffolding done (`breath_model`, `breath_screen`, `user_breath_sessions`) |
| Sport log (ring history) | Ring log 0..6 auto-merge | No | `/workouts` (+ `/sport-detail` stub) | ✅ `_pullRingSports` on page open → normalize `SportPlusEntity` → `insertWorkout` unseen, RING badge, `TYPE_APP_*` start-second dedupe; `mCalories` kcal-vs-小卡 auto (`≥10000 → ÷1000`, `~/1000` intentional per eval 1.9) | Shipped |

Range-payload contract (all range APIs): `[{"dayIndex": N, "data": {…same shape as single-day…}}]` (`day_index` snake variant accepted). Ring buffer 7 days (`dayIndex 0..6`, `kRingHistoryMaxDays = 7` in `ble_service.dart`). "View all history from the ring" = range fetch `startDay=0, count=7` via `BleService.fetchRingHistory(vital)` (Dart-side timeouts 10–15s per call).

---

## 3. Background measurement loop

| ID | Requirement |
|----|-------------|
| VIT-01 | Native `MeasurementLoopManager` round-robins enabled vitals (Steps → HR → SpO₂ → Stress → BP → HRV → Temperature) while connected and loop enabled, through one BLE manual-mode slot (`MeasurementCoordinator.busyOwner`: `"manual"`/`"loop"`/`"workout"`, single slot). |
| VIT-02 | Each sample is written to local Room with `source` (`auto_cycle` / `manual` / `interval_sync` / `auto_cycle_fallback`) and timestamp. `persist()` skips `NewReadingEvent` on rejected inserts (`id<=0`). |
| VIT-03 | New readings notify fall analysis and Flutter (`NewReadingEvent` / EventChannel). HRV also `unawaited(_pushToHealthConnect('hrv'))` via `tryWriteHrv` (`ble_provider.dart:545-573,579-605`). |
| VIT-04 | Manual UI measurement and workout measurement coordinate so SDK is not double-driven (`MeasurementCoordinator`). Loop `watchForPreempt:217` yields to manual (`PREEMPT 200ms`, `POST_STOP_SETTLE 2s` before lock release). `YIELDED_TO_MANUAL` resumes after 15s (`WORKOUT_RECHECK_MS`), not full cooldown. |
| VIT-05 | Per-vital enable + interval configurable from Health Settings (`get/setHeartRateSetting`, `get/setHrvSetting`, `get/setBloodOxygenSetting`, `get/setBloodPressureSetting`, `get/setPressureSetting`, `get/setTemperatureSetting`, `get/setTargetAndProfile`, `get/setHealthSettings`, `getDeviceSupport`, `getAdvancedSettings`, `read/setRriAutoMeasure`, `read/setEmotionAutoMeasure`) and mirrored on detail screens where applicable. |
| VIT-06 | Production cycle cooldown is `DEFAULT_CYCLE_COOLDOWN_MS = 180_000L` (3 min). One-time migration in `getCycleCooldownMs()`: stored `60_000` (old default) maps to `180_000` and is persisted; explicit user/dev overrides (health settings screen, prayer session `0`/`180000`) untouched. `finishCycle()` reads cooldown fresh each cycle (no restart needed). Dart already aligned: `ble_service.getCycleCooldownMs` fallback `180000`, `health_settings_screen` default `180000`. |
| VIT-07 | Per-vital ceilings: Steps instant (passive), HR 60s, SpO₂ 60s, Stress 60s, BP 60s, HRV 90s, Temp 90s (+2s post-stop settle each; worst-case `414s` ≈ 7 min). Adaptive timeout: `max(avg × 1.5, 15s)` clamped at ceiling (`MIN_TIMEOUT_MS=15_000L`, `TIMEOUT_HEADROOM_FACTOR=1.5`, `ROLLING_WINDOW=5`). Adaptive cooldown: after `NORMALCY_CONFIRM_CYCLES=2` consecutive normal cycles (via `FallRiskAnalyzer.currentTier()`, `@Volatile _lastTier="LOW"`, `RiskTierChangeEvent`) cooldown stretches 3 min (`FAST_COOLDOWN_MS=180_000L`) → 15 min (`SLOW_COOLDOWN_MS=900_000L`); any anomaly resets to fast. |
| VIT-08 | Manual HR acquire: `MANUAL_ACQUIRE_TIMEOUT_MS = 8000` (was 4000). Streaming `readHeartRate` early guards `SDK_GUARD_OPEN` / `NOT_CONNECTED`; `errCode` fail-fast `HR_ERR_<code>` ("keep ring snug"); stored `timeoutRunnable` + `removeCallbacks` on every success path (fixes double-reply `result.success(null)` then `result.error(TIMEOUT)` → `IllegalStateException: Reply already submitted`); `postDelayed(timeoutRunnable, 30_000L)` 30s TIMEOUT + stop + release. Auto path (`measureHeartRate:229`) requires 2 consecutive candidates `abs≤12` (was 8), lower-median `sorted[(size-1)/2]` (was `size/2` upper-median → `87` for `[65,87]`), skips `errCode!=0` frames. Neither strict path gates on `rsp.status` (intermediate calibration frames lack `RESULT_OK`). |
| VIT-09 | Tiered strict/legacy extraction (range-gated `VitalRanges.isValidBpm(30–220)` both tiers): strict accepts `getHeartRate()>0` (type 13) or `type==12 → value`, rejects type-14 SpO₂ / `0xFF` sentinels / cross-vital bytes; auto needs 2 consecutive within 12 (lower-median), manual returns first strict immediately. Legacy (pre-Aug24 first-nonzero `getHeartRate else getValue`, no checks) restored as second tier only — collected in parallel, median used solely when strict empty by timeout; tagged `source=auto_cycle_fallback`, `valueJson {"extractor":"legacy",…}` (`strict`/`strict_timeout` otherwise). Interval array casts fixed (`List<*> filterIsInstance<Number>` + `IntArray/FloatArray/DoubleArray`) so blobs inflate instead of empty. |
| VIT-10 | `syncManualHeartRateList` fallback (QRing parity): streaming miss → `_tryManualListFallback()` — `LargeDataHandler.syncManualHeartRateList` → `ILargeDataManualHeartRateResponse.manualHeart` → `[{index,data:[{m,v}]}]` JSON → latest valid 30–220. XAPK evidence: `syncManualHeartRateList` + `MyDeviceNotifyListener` (36 hits) + `ManualHeartRate`/`DetailBean(m,v)` + `queryManualHeart`/`saveManualHeartRate`; SDK `qring_sdk_1.0.0.55.aar` already contains it (`syncManualHeartRateList`, `getManualHeartRate(s)`, `getTodayManualHeartRate`, `ManualHeartRate{index,data[]}`, `ILargeDataManualHeartRateResponse`); `StartHeartRateRsp.getErrCode()` now checked. Frame gate retained: `manualModeHeart(cb,false)` start, `(null,true)` stop. |
| VIT-11 | Cancel path: `cancelHeartRate` channel (native session `manualHrResult`/`manualHrDone`/`manualHrTimeout` + `clearSession()`; late callbacks check `done` first). Second tap cancels (tap-toggle): `BleService.cancelHeartRate()` → `invokeMethod<bool>('cancelHeartRate')`; `_startMeasurement` tap while `_measuring` → cancel, `_measuring=false`, `Cancelled` snackbar. `abortActiveManualHr("DISCONNECTED",…)` from both `disconnect()` and `onDeviceDisconnected()` → original result `DISCONNECTED`. Stop-before-start: best-effort `manualModeHeart(null,true)` + 300ms settle before `manualModeHeart(cb,false)` (inside 8s budget; cancel during window honored, no double-reply). `CANCELLED`/`DISCONNECTED` added to `_measureErrorMessage` + `_isExpectedHrError` (local `debugPrint`, never `app_incidents`). `RealTimeCard` tap stays enabled while measuring (spinner + `Tap to cancel`, `enabled: connected`); `NotEnoughDataCard` reads `Cancel measurement`. Verify: LED off, no `BUSY`, `currentOwner()==null`, no false `success` in `measurement_attempt`. Navigating away keeps measuring (no dispose-cancel) by decision. |
| VIT-12 | Storm breaker: 8 failures/60s opens `SdkGuard` 45s; invokes return `SDK_GUARD_OPEN` without touching sensor. Expected Dart failures (`TIMEOUT`/`HR_ERR_*`/`BUSY`/`NOT_CONNECTED`/`SDK_GUARD_OPEN`/`CANCELLED`/`DISCONNECTED`) stay `debugPrint`-local; only unexpected reach `app_incidents`. `walkSequence` never marks still-`RUNNING` HR `success` — records `failed_no_data`. |
| VIT-13 | Measurement attempts log (Room 7→8, local-only, no `SupabaseSyncManager` push): `MeasurementAttemptEntity(id, vital HEART_RATE|…, source auto_cycle|manual|interval_sync, cycleId FK, startedAt, endedAt, status success|failed|timeout|yielded|rejected|aborted_disconnect|skipped_workout|sdk_guard_open|skipped_disabled, error, valueJson)` (`ReadingEntities.kt:197`); `MeasurementAttemptDao(attemptsBetween, failedBetween, attemptsForCycle, cyclesWithCountsBetween, purgeOlderThan)`; `QRingDatabase.kt:9,29` bump 7→8; `ReadingRepository.kt:35` `startAttempt/finishAttempt` + purge 30d. `walkSequence:59` instruments every exit (disabled/disconnect/workout/yielded/timeout/rejected/exception); `BlePlugin:2953` phantom cycles `id>0→success else rejected`. Bridges `getMeasurementAttempts` + `getFailedMeasurementAttempts` (no `getMeasurementLogGrouped`, no `measurement_log_service.dart` — parsing in screen). UI `health/measurement_log_screen.dart` (`GlassBackButton`, `AppTheme.bg`, `AppTypography`, `FooterSpacer`), opened per-vital via `_openMeasurementLog` (filter `All | Failed only`, last-3-days window), flag-gated settings entry (`settings_screen.dart:440`, `AppConfig.includeMeasurementLog`); no `/measurement-log` route, no History card in `health_settings_screen`. Burst >3/hr → `IncidentService.reportUnhandled(source:measurement_loop)`. |
| VIT-14 | `BleConnectionService` poll: `SdkGuard.isOpen()` → 30s; `connected && wasConnected` → 30s (was 8s); freshly connected → 8s; disconnected → exponential backoff `BACKOFF_STEPS_MS` 8s→15s→30s→60s→120s (≈10k GATT attempts/night avoided; wake-ups ~10,800→~2,700/day, −75%). Ring HR interval `setHeartRateSetting(true,10)` 10 min kept (official 30–60 min skipped per user request). |
| VIT-15 | Mounted guard: `if(!mounted) return` before every `setState` after `await` in 7 health screens + `chat_screen:239` (`lib/utils/mounted_guard.dart` mixin; sleep `155,216,439,540,757` captures `final date=_selectedDate` before await; guards all 8 `setState` sites; keeps `IncidentService` catch). Fixes `setState() called after dispose(): _SleepScreenState` (18 rows: `_loadDayFromDb:225 → _parseSleepData:173 → _fetchFromRing:156 → _init:119`) + `chat Null check` + `CameraException buildPreview disposed`. |

---

## 4. Data tiers (detail screens)

Standard pattern for HR, SpO2, BP, HRV, stress, steps, temperature:

| Tier | Source | Use |
|------|--------|-----|
| Today | Room via `BleService.getTodaySummary` / `getReadings` | Offline-capable charts |
| Selected past day | Supabase | History day picker |
| Multi-day trend | Supabase (7-day) + ring range backfill `_pullRingHistory` (6-step pattern §7) | Trend charts (gated 2+ days) |

Manual "Measure Now":

1. Blocking native measurement with timeout (HR 30s incl. 8s acquire; HRV ~50–60s; others 8s–90s by vital).  
2. Update `BleProvider` latest value (`updateHrLatest`/`updateSpo2Latest`/`updateHrvData`/`updateHrvLatestDetailed`, `ble_provider.dart:273-310`; `_refreshHrFromLocal:1081-1145` / `_refreshSpo2FromLocal:1147-1178` / `_refreshHrvFromLocal:1379-1391` capture `lastValue/lastMeasuredAt` + `getLatestReading` fallback when `count==0`; `_onNewReadingEvent:545-573`).  
3. Upsert cloud history via **incremental** avg/min/max/count merge (not blind overwrite); cloud only when `!hasData(local)`.

Hero rule (Phase 1): hero = `latest` (`latestHr`/`latestSpo2`/`latestHrv` + `latestHrMeasuredAt` etc., `ble_provider.dart:44-71,188-210`); avg is secondary; stale pill (`isLatestHrStale(30m)` / `isLatestSpo2Stale` / `isLatestHrvStale`, 30 min) shows `avg · no fresh reading` (white `0.6`); `latest==0` → stale pill. No fake buckets (removed `hourly[now.hour]=avg`, `heart_rate_screen:204`). Detail heroes (`heart_rate_screen:63-710`, `blood_oxygen:63-702`, `hrv:63-774` incl. 48 half-hour slots, `home_screen:334-553` `latestHrvHome`/`latestSpo2Home`, `FigmaExpandedCard` HR uses `latest`): `latest>avg` + stale pill + no fake bucket + cloud guard + `insertHeartRate`/`insertSpo2`/`insertHrv` → true `AVG/MIN/MAX/COUNT` from `getTodaySummary`.

6-step `syncAllFromRing` (`_initThenSync:1546-1656`, native `ReadingRepository.kt:67-151` `insertHeartRateAt/Spo2At/HrvAt/TemperatureAt` via `repo.startCycle → insert*At → completeCycle → EventBus NewReadingEvent`; `BlePlugin.kt:449,2819-2855,993-1151` dispatch `insert*` + `syncInterval*Detail` inflating `IntervalHeartRateEntity{dayIndex,interval,array}` / `bigData.IntervalBloodOxygenEntity` via `IIntervalHeartRateCallback`/`IIntervalBloodOxygenCallback` → `dayStart+idx*interval*60k+30k` `insert*At(source=interval_sync)` ±30s dedup; `syncIntervalTemperatureDetail` handles `array:List<Float>` + `values:List<IntervalTemperature>` (`value1`) → `valueC/10` normalized 30–45; Dart bridges `ble_service.dart:663-682` `insertHeartRate/insertSpo2/insertHrv/insertTemperature/syncIntervalHeartRateDetail/syncIntervalSpo2Detail/syncIntervalTemperatureDetail`):
`HRV → Sleep → TempAuto → HR interval → SpO₂ interval → Temp interval` (`0.33 → 0.66 → 0.90 → 0.92 → 0.96 → 1.0`) with `_refresh*`, plus `setHeartRateSetting(true,10)`. Pressure interval LargeData not needed (SDK has no `IntervalPressureEntity` — poll-only accepted). Temperature dual path (`array` vs nested `IntervalTemperature`) needs field test (`supportTemperatureBoth`).

`SupabaseSyncManager` 6h: `unsyncedBatch` → `user_*_readings` + recompute daily `user_hr/spo2/hrv` avg. `seedDemoData` rows carry `source='demo_seed'` and are excluded from every `unsyncedBatch` push query (all 7 tables, `ReadingDaos.kt`) — never reach Supabase.

Health Connect sleep fix (`health_connect_service.dart`, `health 13.3.2`): `tryWriteSleep` uses local date string `${y}-${mm}-${dd}` (not `millis ~/ 86400000` UTC) for deterministic `clientRecordId`; `end` fallback `DateTime(y,m,d+1,wakeHour,wakeMinute)` (+1 day fallback) handles overnight 23:00→07:00. `fetchToday` sums `p.dateTo.difference(p.dateFrom).inMinutes` for `SLEEP_*` (not `_numValue`); computes `asleepM, deepM, lightM, remM, awakeM, inBedM`; `totalSleep = asleep!=0 ? asleep : deep+light+rem ?: inBed`; `sleepMinutes = totalSleep!=0 ? totalSleep : null`. Permission: `_connect()` requests enabled subset (`requestAuthorization(_enabled)`), `_toggle()` saves set + `_refreshGrantedAndToday` (no single-type sheet); covers 8 types (Steps, Heart Rate, HRV, SpO2, Sleep, BP, Temperature, Menstruation). Verified: `isHealthConnectAvailable()` gating, per-type `hasPermissions`/`requestAuthorization` `READ_WRITE`, `requestHealthDataHistoryAuthorization()` 30-day unlock, deterministic `clientRecordId`.

---

## 5. Classification thresholds (HealthEngine single truth)

All numeric bands live in `HealthConfig` (`health_config.dart:kDefaultConfig`) overridable via Supabase singleton `health_engine_config` (`id=1`, `config JSONB`, `supabase/migrations/20260905000000_health_engine_config.sql`: RLS `select` for `anon`/`authenticated`, `all` for `service_role` only, `touch_health_engine_config()` trigger; fetch `eq('id',1).maybeSingle()`; cache `SharedPreferences health_engine_config_json` + `health_engine_config_updated_at`; `load()` in `main.dart` before `runApp`, `refresh()` on Home pull-to-refresh / resume if `updated_at` stale >5 min (`kCacheTtl`); deep-merge remote over default; partial `{"thresholds":{"sleep":{"excellent":85}}}` allowed; `version` bump forces refresh; nonsensical clamped + `IncidentService` log; offline falls back to cache then `kDefaultConfig`; airplane mode never shows `--` from config miss). `lib/utils/bp_staging.dart` is an alias: `classifyBp(sbp,dbp)` → `HealthEngine.instance.assessBloodPressure(sbp,dbp)` → `BpStage.normal/elevated/stage1/stage2/noData` (+ `label/compactLabel`); `bpStatusColor(…)` → `.color`. Delete wrappers after alias (`blood_pressure_screen:43 _bpStatus`, `home_compact_cards:254 _bpCompactStatus`, `hrv:122 _hrvLabel`, `stress:48 _stressLabel`, `temperature:123 _tempLabel`, `home_screen:174 _spo2Status/_hrStatus/_hrvStatus/_sleepStatus`, `home_card_shared:70 stressStatus/tempStatus/activityScoreLabel`).

### Sleep (score 0–100) — `thresholds.sleep.excellent/good/fair`

```
window    = (st>0 && et>0) ? (et - st) : total
efficiency= total/window*100            clamp 0..100
deepPct   = deep/total*100              clamp 0..40
remPct    = rem/total*100               clamp 0..30
score     = (efficiency*0.4 + deepPct*1.0 + remPct*0.5).round()  clamp 0..100
```

```
score >= excellent (80) → Excellent (AppTheme.success)
score >= good (60)      → Good      (AppTheme.sleepColor)
score >= fair (40)      → Fair      (AppTheme.amber)
score > 0               → Poor      (AppTheme.danger)
else                    → No data   (AppTheme.textSec)
```

Canonical `80/60/40` (detail's `85/70/55` was drift — fixed). `calcSleepScore(total:,deep:,rem:,st:,et:)`; `assessSleep(score)`; stage const `0=deep,1=light,2=awake,3=REM`.

### Heart rate (bpm) — `thresholds.hr.belowNormal/aboveNormal`

```
v <=0      → No data
v < 60     → Below normal (AppTheme.hrvColor)
v < 100    → Normal       (AppTheme.success)
else       → Above normal (AppTheme.danger)
```

Note ranges `<60` / `60–99` / `100+`. `assessHeartRate(v)`.

### SpO₂ (%) — `thresholds.spo2.normal/borderline`

```
v <=0          → No data
v >= 95        → Normal     (AppTheme.success)
v >= 90        → Borderline (AppTheme.amber)
else           → Low        (AppTheme.danger)
```

Note ranges `95–100` / `90–94` / `<90`. `assessSpo2(v)`.

### HRV (ms) — `thresholds.hrv.veryLow/low/moderate/good`

```
v <=0   → --        (AppTheme.textSec)
v < 20  → Very Low  (AppTheme.danger)
v < 40  → Low       (AppTheme.stressColor)
v < 60  → Moderate  (AppTheme.amber)
v < 80  → Good      (AppTheme.success)
else    → Excellent (AppTheme.hrvColor)
```

Matches `hrv_screen.dart:119`. `assessHrv(v)`.

### Stress (0–100) — `thresholds.stress.relaxed/normal/elevated`

```
v <=0        → --       (textSec)
v < 40       → Relaxed  (AppTheme.success)
v < 60       → Normal   (0xFFFBBF24)
v < 80       → Elevated (AppTheme.stressColor)
else         → High     (AppTheme.danger)
```

Replaces `supabase_service.dart:363 _stressLabel` (was diverging `40/60/80` copy). `assessStress(v)`.

### Blood pressure (mmHg) — `thresholds.bp.normalSbp/normalDbp/elevatedSbp/stage1Sbp/stage1Dbp`

AHA/ACC staged (fixed `||` bug — eval 1.1: `139/95` was Stage 1, correct Stage 2; `179/70` was Stage 1, correct ≥Stage 2; `125/85` fell to Stage 1, correct Elevated gate):

```
if sbp<=0||dbp<=0                                    → noData
if sbp<120 && dbp<80                                 → Normal   (success)
if sbp<130 && dbp<80                                 → Elevated (amber)
if sbp<140 && dbp<90                                 → Stage1   (stressColor)
else                                                 → Stage2   (danger)
```

Keys `normalSbp=120 / normalDbp=80 / elevatedSbp=130 / stage1Sbp=140 / stage1Dbp=90`. `InsightsService` delegates (no ad-hoc `>=130`). Note ranges `<120/80` / `120–129/<80` / `130–139/80–89` / `140+/90+`. Tests: `110/70 normal`, `125/75 elevated`, `135/85 stage1`, `145/95 stage2`, `120/80 stage1`, `140/89 stage2`.

### Temperature (°C native; display via `UnitPrefs`) — `thresholds.temp.low/normal/elevated`

```
v <=0              → --       (textSec)
v < 36.0           → Low      (AppTheme.spo2Color)
v <= 37.2          → Normal   (AppTheme.success)
v <= 38.0          → Elevated (AppTheme.tempColor)
else               → Fever    (AppTheme.danger)
```

Engine `barColor(double c)` re-used by charts (chart `maxY 40 baseline 34`, `temperature:788`). `assessTemperature(v)`.

### Activity (0–100) — `thresholds.activity.stepsWeight/caloriesWeight/distanceWeight` + `stepsDenom/caloriesDenom/distanceDenomM` fallbacks

Weights product-fixed (defaults stable, Studio-retunable):

```
stepsW = 60 (stepsWeight) | calW = 25 | distW = 15   // sum == 100
goalSteps = GoalPrefs.load().steps              // default 10000 (fallback stepsDenom=10000)
goalCals  = GoalPrefs.load().calories           // default 1000  (fallback caloriesDenom=1000)
goalDistM = GoalPrefs.load().distanceKm * 1000  // default 5.0*1000 (fallback distanceDenomM=5000)
s = (steps / goalSteps * stepsW).clamp(0, stepsW)
c = (cals  / goalCals  * calW  ).clamp(0, calW)
d = (distM / goalDistM * distW ).clamp(0, distW)
score = (s + c + d).round().clamp(0,100)
```

Example: goals `12000/600/8km` → `12000`=60 + `300/600*25`=12 + `6000/8000*15`=11 → `83`. Legacy `8000/250/5000` with default goals scores `48+6+15=69` (intentional goal-aware shift). API: `calcActivityScoreWithGoals(steps:,calories:,distanceM:,goals: GoalTargets(steps:10000,calories:1000,distanceKm:5.0))` sync (caller supplies goals, avoids async in `build`) + `calcActivityScore(steps:,calories:,distanceM:)` async (loads `GoalPrefs`+config). Home (`home_screen:176 _computeActivityScore`) + Steps (`steps_screen:554 _activityScore`) both call engine; `activityScoreLabel/scoreLabelColor` on engine; `ActivityDescriptionScreen` blurb via `activityDescription()` (interpolates goal denoms + weights, never lies after goal change); `goal_setting_screen:39` after `GoalPrefs.save` → `HealthConfig.notifyGoalChanged()` / `invalidateActivityCache()`.

```
score == 0 → Lack of exercise  (AppTheme.danger)
score < 25 → Sedentary
score < 50 → Lightly active    (AppTheme.tempColor)
score < 75 → Moderately active (AppTheme.spo2Color)
else       → Highly active     (AppTheme.success)
```

### Advice & VitalNote copy (all 8, engine-owned)

Bundled fallback `health_config.dart:kDefaultConfig['advice']+['ranges']` (moved verbatim, no visual change); remote override same row `config.advice/.ranges`. Accessor `noteFor(HealthMetric.*)` → `VitalNoteData{title,heading,intro,ranges,tips,didYouKnow}`; `VitalNoteScreen.fromData(note)` / `fromMetric(metric)` maps `colorKey → AppTheme`; `tipIcon(String)` maps `icon` string → `Icons.*_rounded`.

| Metric | Owner screen (was) | Engine accessor | Note fields |
|---|---|---|---|
| Sleep | `sleep_screen:842` | `noteFor(HealthMetric.sleep)` | `Sleep`/`About Sleep`, deep/REM intro, Poor 0–39 … Excellent 80–100, tips "Aim 7–9h"/"Consistency", didYouKnow deep vs REM |
| Heart Rate | `heart_rate:618` | `noteFor(HealthMetric.heartRate)` | Below/Normal/Above, tips Lower can be fine / Watch trend, didYouKnow caffeine |
| SpO₂ | `blood_oxygen:638` | `noteFor(HealthMetric.spo2)` | Normal/Borderline/Low, tips sleep dips / altitude, didYouKnow cold fingers |
| HRV | `hrv:662` | `noteFor(HealthMetric.hrv)` | Very Low … Excellent, tips personal / alcohol, didYouKnow rising trend |
| Stress | `stress:580` | `noteFor(HealthMetric.stress)` | Relaxed/Normal/Elevated/High, tips breathing / sleep debt, didYouKnow brief spike |
| Temperature | `temperature:658` | `noteFor(HealthMetric.temperature)` | Low/Normal/Elevated/Fever (Celsius), tips baseline / daily rhythm, didYouKnow skin vs core |
| Blood Pressure | `blood_pressure:655` | `noteFor(HealthMetric.bloodPressure)` | Normal/Elevated/Stage1/Stage2 `<120/80` etc, tips sodium / measure same way |
| Activity | `activity_description:51` | `noteFor(HealthMetric.activity)` | Weights 60/25/15, range bar & legend, tips per metric |

Inline badges also from engine (`assessHrv(v).label/color`); `InsightsService` headlines build from same `assessmentFor` helpers. Studio workflow: edit `health_engine_config.config.advice.sleep.tips[0].tip` → next `HealthConfig.refresh()` (pull-to-refresh/resume/`refreshConfig()`) pulls it; offline uses `health_engine_config_json` cache.

---

## 6. Charting + parsing requirements

| ID | Requirement |
|----|-------------|
| VIT-20 | HR: 24 hourly buckets for today (`HourlyAggregator.aggregateInt(readings, valueKey:, measuredAtKey:, slots:24)`; `sums[hour]+=v; counts[hour]++; hourly[h]=round(sums/counts)`). Chart painter `maxY 120 yLines [120,100,80,60]` (`heart_rate:752`). |
| VIT-21 | HRV: 48 half-hour buckets (`aggregateHrv(…)` → `aggregateInt(…, slots:48, slotFor:(h,m)=> (h*60+m)~/30)`). |
| VIT-22 | Steps: 96 fifteen-minute slots → 24 hourly (`ActivityEngine.parseIntervalJson` + `distributeSteps` + `toHourlyInt/Dbl(slots)` `sublist(h*4).fold`, `steps_screen:803-811`; `activeSlotsCount=(nowSlot-28).clamp(1,96)`, `stepsPerSlot=curSteps/activeSlotsCount`, `steps_screen:169`; `totalCalRaw>=1000?~/1000:>0?1:0`, `normalizeCalories(raw,steps)` `raw>=500&&steps<4000?~/1000`, `steps_screen:231-288`, `supabase 344`; obfuscated `d/f/e/g` vs `timeIndex/walkSteps/calorie/distance`; tests `2142 for 547 steps → 2 kcal`, `0 steps → 0 slots`). |
| VIT-23 | BP: dual series (`aggregateBp(readings)` → `({sbp, dbp})`, `blood_pressure:226-256` dual SBP/DBP; `ScrubbableBPChart:648`). SpO₂ double path `aggregateDouble(slots:24)` (painter `maxY 100 baseline 85`, `blood_oxygen:788`); Temperature double (painter `maxY 40 baseline 34`); Stress 24-slot; Sugar 24h `MetricBarPainter(maxY:300)` design / impl `maxY15`. `maxY/baseline/yLines` read `HealthConfig` via engine (widget keeps `barColor` callback). |
| VIT-24 | Offline failures show `OfflineNotice`, not empty "no data" when connectivity is cause. Trend loading/offline guards preserved (`!_loadingTrend && !_trendOffline`, `!_dbOffline`). |
| VIT-25 | No third-party chart package required; custom painters acceptable (`_HypnogramPainter`, `MetricBarPainter`, `ScrubbableChart`). |
| VIT-26 | Trend gate: `TrendMath.kMinTrendDays = 2`; `hasEnoughTrendData(List<num> values, {minDays=kMinTrendDays})` → `where((v)=>v>0).length >= minDays` (covers `List<int>` + `List<double>` temp `36.5`); `hasEnoughBpTrendData(List<int> sbp, List<int> dbp)` counts `sbp[i]>0 && dbp[i]>0` pairs. All 7 screens gated: `sleep:870`, `heart_rate:760`, `blood_oxygen:781`, `stress:702` (+import `26`), `hrv:811`, `temperature:763` (+import `28`), `blood_pressure:838` paired (+import `25`). Copy `not_enough_data_card.dart:86` `4+ → 2+ days`. Matrix: 0 days → card; 1 day `[…,65]` → card (was chart); 2 days → `ScrubbableChart` 2 bars; BP 1 pair → empty, 2 pairs → chart, mixed `[130,130]/[0,85]` → 1 pair → empty. Single source: `2→3/4` updates all. |
| VIT-27 | Sleep dual empty-state spacing: unconditional `const SizedBox(height:20)` at `sleep_screen:867` between daily and trend (moved from inside `else` at `825/864`); matches `heart_rate:757`, `stress:699`, `blood_oxygen:778`, `hrv:808`, `blood_pressure:835`, `temperature:759`. Reuses `DESIGN.md:149-183` tokens only. `ScrubbableChart` 7 slots `5.5px gap`/`barW max 4→9px`; zeros stay `AppTheme.div` stubs until threshold. |
| VIT-28 | `TrendMath` (`trend_math.dart`): `avg(List<int>)` `fold~/length`, `avgDouble`, `min`/`max` `reduce`, `minMax(rows,minKey,maxKey)`, `last7Bars(rows,dateKey,valueKey)` (`sleep:786-800`); replaces `heart_rate:376-383 reduce(min/max)`, `sleep:768-774 fold`. `ScrubHelper`: `initialIndex(values)` last `>0` else 0 (`chart_scrubber:243`); `indexFromDx(dx,width,count)` `(dx/width*count).floor().clamp(0,count-1)` (`:432`); duplicated at `ScrubbableChart` + `ScrubbableBPChart:648`. `DateKeys` (`date_keys.dart`): `fmt` `yyyy-MM-dd padLeft` (×16: `heart_rate:114`, `supabase:147`, `local_vitals:28`, `sleep:607`, `steps:135`), `isToday` (×7, `heart_rate:82`, `ble_provider:1254 isTodayTimestamp`), `sameDay`, `dateOnly`, `dateKey`, `dayIndexFor` (`today.difference(sel).inDays`, `steps:140`), `isFuture`, `trendXLabels()` 7 Mon–Sun (`heart_rate:630` ×7), `trendDayLabelsShort()` M/T/W (`sleep:804`), `dayStartMs`/`dayEndMs` (`LocalVitalsService 18-26`, `SupabaseService._dateStr 675` delegates). `Formatters` (`formatters.dart`): `sleepDuration(secs)` (`--` if ≤0; `h/m` via `~/3600`, `home:196`+`sleep:739`), `sleepTimeLabel(ts)` 12h `$m$am/pm` (`sleep:747`), `hourLabel(h)` `0→12am <12→am 12→12pm else -12pm` (`heart_rate:639` ×4), `halfHourLabel(slot)` (`hrv:669`), `fmtTime(dt)` (`hrv:125`). Pure, no `BuildContext`; widgets keep `AppTypography.inter`. |
| VIT-29 | `SleepEngine` (`sleep_engine.dart`, PRIORITY extraction of `sleep_screen:216-437` ~220 lines): `calcTotals(segs)`, `parseSegments(rawList,st,et)` (heuristic `firstD>1e9` → timestamp vs duration; `d<500 →*60`, `d<10000→seconds`, `cursor` reconstruction, `st==0` shift `et-last.end`, old-proto `sleepStart/sleepEnd/type`), `parseSleepData(jsonStr)` (new-proto `st/et/list{d,t}` + old `totalSleepDuration/deepDuration` + `IncidentService` fallback to caller; keeps `d>1e9`/`d<500` exactly), `efficiency(total,st,et)` (`total/(wake-sleep)*100`, `757-762`), `syntheticSegs(total:,deep:,light:,rem:,awake:,st:)` (`1267-1376`, `_yPos 0.05/0.35/0.62/0.88`), `calcScore(total,deep,rem,st,et)` → `HealthEngine.calcSleepScore` (widget `439-440` already delegates; `_quality 764-766` delegates; `_avgHistory*/_last7Bars/_trendDayLabels 768-811` → `TrendMath`). Widget after: `parsed=parseSleepData(jsonStr); setState(total/deep/…/score/segs); _saveToDb(…)`. Tests: timestamp `d=1_700_000_000` vs `d=30 (*60→1800s)` vs `d=5000` s; `st==0` shift; old `sleepStart`; `total<=0 → loadDayFromDb`. |
| VIT-30 | `TemperatureEngine.parseTempReadings(String json, DateTime base)` (`temperature:547-605`): list vs map `{mValues/d, mTimeSpan/b, a/b}`, `val>100/10` (`365→36.5`); `disp(double c, TempUnit)` wraps `UnitPrefs.celsiusToFahrenheit`. Tests `mTime/mValue` vs `a/b` vs `mValues/d`. |
| VIT-31 | Empty-state measuring: `NotEnoughDataCard(measuring:false, onPressed: isConnected?onMeasure:null, child: measuring?'Cancel measurement':Text(measureLabel))` (same spinner as `RealTimeCard`); pass `measuring:_measuring` in 6 screens (`heart_rate:692`, `blood_oxygen:712`, `hrv:739`, `stress:628`, `temperature:687`, `blood_pressure:765`); keep `sleep:701` + `steps:644` buttonless. Fixes exclusive `if(!hasData && !_loading && !_loadingDay && !_dayOffline)` hiding `RealTimeCard` (`heart_rate:688` etc.; hero only `···` while 5–90s BLE wait). |
| VIT-32 | ECG/Breath/Sugar/Pressure screens (Phase 2 scaffolding done, BLE pending): QRing refs `activity_ecg.xml/detail/guild/measure/list` 5 layouts + `EcgRepository qc_ecg_entity(device_address,date_str,type,data_list,avg_heart,unix_time)` + `CMD_ECG_MEASURE_TIME` + `ECGSurfaceView` + `EcgYAxisRange`; breath 8 layouts `activity_breath_home/category/training/finish/record/detail/audio/setting` + `BreathTrainingRepository breath_audio(asset_path,download_status,file_size)` 30+ methods (`balance_equal`,`bellows`,`taichi`) + `breath_training_record(id,method_id,average_heart_rate,inhale_seconds…)` (manual timer + ring HR, no `LargeDataHandler`); sugar `activity_blood_sugar.xml/data_detail/guide` + `BloodSugarRepository app_sugar(app_heart)` + `app_continuous_sugar(mac,date_str,timestamp,min_sugar,max_sugar,hour)` CGM 1/h via `BloodSugarSettingReq`; pressure `pressure_detail(device_address,date_str,interval,index_str,value,unix_time)` via `PressureReq/PressureSettingReq` + `LargeDataHandler` (Sundr `BlePlugin:1769` poll-only gap). Models `breath_model.dart` (`BreathMethod(Category,Method,audioId,inhale/hold/exhale)` + `BreathRecord` = QRing record), `ecg_model.dart` (`EcgSample(avgHeart,dataList<List<int>>,type,unixTime)`), `blood_sugar_model.dart` (`SugarReading(timestamp,minSugar,maxSugar,hour)`); migration squashed `user_ecg(user_id,date,avg_heart,data_list jsonb,unix_time PK user_id,date)` + `user_breath_sessions(user_id,started_at,method_id,average_hr,subjective_feeling PK user_id,started_at)` + `user_blood_sugar(user_id,measured_at,min_sugar,max_sugar,hour UQ user_id,measured_at)` + RLS owner + `delete_user_account` extension. Screens reuse card `rgba(255,255,255,0.06) blur 28 radius 20` + `MetricChartCard`: `breath_screen` method-picker + `BreathingTraining` countdown (`AnimatedCircularProgress`) + live `latestHr` + save `user_breath_sessions` (+`tryWriteHrv` bonus); `ecg_screen` 30s `ECGSurfaceView` placeholder (polyline) + `EcgHistory` from `user_ecg` (Mock 120 pts `Random`); `blood_sugar_screen` 24h bar `MetricBarPainter` + `DateScrollRow` min/max from `app_continuous_sugar` + manual spot; `pressure_screen:702` extended to `PressureInterval` backfill (`insertPressure`). Routes `/breath /ecg /blood-sugar` (`app.dart`, 47 routes); wrappers `getEcgHistory/getBreathHistory/getSugarHistory` (`supabase_service:905`); bridges `getContinuousSugar/startEcgMeasure` stubbed (channel exists, native canned `"[]"`/`"{}"`); `BlePlugin` dispatch same stub (no SDK call yet); ECG 500Hz decimated for charts (`insertEcg/ecgBetween`, `insertBreathRecord`, `insertSugar` + `readingsBetween` planned); `ReadingRepository`/`QRingDatabase` dao pending; pressure interval `insertPressure` pending; Home cards + `tryWriteEcg` (`ELECTROCARDIOGRAM`) pending. Risks: `supportEcg` subset flag via `getDeviceSupport`; CGM premium-only. Next: wire `EcgReq` + `getContinuousSugar` → `ReadingRepository` + `SupabaseSyncManager` 6h + `pressure_screen` inflate + Home card. |

---

## 7. Functional requirements (summary)

| ID | Requirement |
|----|-------------|
| VIT-40 | User can open each vital screen from Home cards and named routes (`/heart-rate`, `/blood-oxygen`, `/blood-pressure`, `/pressure`, `/hrv`, `/steps`, `/sleep`, `/temperature`, `/sugar-lipids`, `/breath`, `/ecg`, `/blood-sugar`). |
| VIT-41 | Pull-to-refresh / re-query updates latest values when connected (also `HealthConfig.refresh()`). |
| VIT-42 | Steps aggregate is **day max** (ring cumulative counter), not sum of snapshots. |
| VIT-43 | Sleep is pulled from ring (not necessarily every loop cycle); `total<=0 → loadDayFromDb` fallback. |
| VIT-44 | Health settings toggles persist to ring/native and affect the loop. |
| VIT-45 | Standard `_pullRingHistory` wiring (all hooks, `history-coverage.md` 6 steps): (1) early-return when `!BleProvider.isConnected`; (2) `await _ble.fetchRingHistory('<vital>')` (10–15s); (3) decode `List`, per entry `dayIndex`/`day_index` (skip outside 0..6), `data` via vital proven keys, skip empty; (4) persist per day (`upsertHr/Spo2/Hrv/Steps`, `insertBp/Stress(source:ring_history)`); (5) on write quietly reload trend (`_load7DayTrend(quiet:true)`) or visible day (`_loadDay(force:true)` steps); (6) `try/catch(_){}` silent + steps `_loadGen` guard. Payload `[{"dayIndex":0,"data":{…}}]`. |
| VIT-46 | Sugar/lipids: `getHealthSettings{sugarLipids}` reads + `setHealthSettings` writes monitor-state toggles (temperature/rri/emotion); honest empty states; continuous-glucose values remain stub. OTA (`DfuHandle` file-check init/send/check/end + `otaProgress`) is real; firmware `firmware_updates` download needs device smoke test. |
| VIT-47 | Manual-measure triggers mapped end-to-end: `manualModeHeart/BP/SpO₂/Hrv/Pressure/Temperature/Three(POC)`, `readHeartRate`, `insertHeartRate/Spo2/Hrv/Temperature`, `cancelHeartRate`. Deliberately unmapped (no consumer — do not add without feature): Emotion/RRI/Manual-SpO₂/3-point-temp families, `ManualHR` single/range, `oneClickMeasurement`, `startOneKey/endOneKey`, `classicBluetooth*/RTK-SPP`. |
| VIT-48 | `BleProvider` alerts (`_maybeAlert:1190-1464`) delegate to `HealthEngine` severity (no local thresholds). |

---

## 8. Acceptance criteria

- [ ] With ring connected, automatic HR/SpO2/etc. appear on Home within a few loop cycles; hero shows `latest` (e.g. `65`) while AVG pill stays `87` → not frozen; interval backlog after 2h disconnected → `12` backfilled points populate hourly chart.
- [ ] Manual measure updates UI and survives restart via Room and/or cloud; second tap cancels (`Cancelled`); disconnect mid-measure → `DISCONNECTED`, `currentOwner()==null`, next tap works; immediate re-tap never `BUSY`.
- [ ] Past-day history loads when online; offline today still works from Room; empty past date during BLE wait shows single card with spinner + `Cancel measurement`.
- [ ] BP labels match AHA table incl. `139/95→Stage2`, `179/70→Stage2`, `125/85→Elevated`; `classifyBp` alias tests pass via config.
- [ ] Sleep screen shows stages + score when ring has data; `total<=0` falls back to DB; Health Connect stage-written sleep reads back (deep+light+rem) with correct overnight end.
- [ ] Stress screen has no broken manual path (loop-only by design; history backfill present).
- [ ] Trends hidden until 2+ days (BP 2+ paired days); sleep empty shows two glass cards with 20 px gap; `flutter analyze` no errors; `flutter test` passes (engines incl. `parseIntervalJson d/f/e/g`, `parseTempReadings`, `TrendMath`, `health_engine` band edges).
- [ ] `logcat -s MeasurementLoop:D BlePlugin:D | grep -E "BUSY|TIMEOUT|Reply already|candidate=|errCode|runCycle|YIELDED|COMPLETED"`, `sqlite3 … "select vital,status from measurement_attempt …"`, `app_incidents source='heart_rate_screen'` show no double-reply, no false `success`, expected errors local-only.
- [ ] `adb logcat -s MeasurementLoop:D | grep -E "runCycle|YIELDED|COMPLETED"`: cooldown gap ≈180s (→15 min when healthy ×2 cycles); `BleConnectionService` 30s stable / backoff when disconnected.

---

## 9. Related

- [04-home-dashboard.md](./04-home-dashboard.md)  
- [11-data-sync-storage.md](./11-data-sync-storage.md)  
- `architecture/Data_Layer.md`
- `docs/engining/*.md`, `docs/health-eng/*.md`, `docs/qring/phase-1-core-vitals-flow.md`, `docs/qring/phase-2-detailed-health.md`, `docs/fix-aa/*`, `docs/fix-ab/02-05`, `docs/heart-rate-attempt/*`, `docs/mappings/*`, `docs/bugs-fixes/06-health-connect-sleep-fix.md`, `docs/archive/eval/01-02`, `docs/changes-18/*`
