# 02 — Device Pairing & BLE Connection

| Field | Value |
|-------|-------|
| **Status** | Shipped |
| **Primary platform** | Android (vendor SDK required) |
| **Key code** | `BlePlugin.kt`, `BleConnectionService.kt`, `lib/services/ble_service.dart`, `lib/providers/ble_provider.dart`, `ring_scan_sheet.dart`, `device_bind_screen.dart` |
| **Native package** | `com.medxai.sundr` (namespace = applicationId, `build.gradle.kts:11,21,32`; manifest `package="com.medxai.sundr"`; application `.QRingApplication`; activity `.MainActivity`; zero `com.example` remnants) |
| **Channels** | `com.medxai.sundr/ble` (MethodChannel), `com.medxai.sundr/ble_events` (EventChannel), `com.medxai.sundr/phone_mode` — Dart (`lib/config.dart:20-23`) ↔ Kotlin (`MainActivity.kt` `BLE_METHOD_CHANNEL`/`BLE_EVENT_CHANNEL`/`PHONE_MODE_METHOD_CHANNEL`) exact match |
| **Vendor SDK** | `android/app/libs/qring_sdk_1.0.0.55.aar` (`com.oudmon.ble.*`, `BleOperateManager` javap surface is authoritative; QRing 1.0.1.131 ref app `com.app.cq.ring`, versionCode 131, same SDK family `oudmon` ×621 — release dex R8-obfuscated so no static per-method diff) |

---

## 1. Purpose

Discover, bond, and maintain a connection to a SUNDR/QRing smart ring so vitals, settings, OTA, and workouts can operate.

---

## 2. Constraints

- All BLE traffic goes through the **closed-source vendor AAR** (`android/app/libs/qring_sdk_*.aar`, `com.oudmon.ble.*`).
- Flutter never opens GATT directly; it uses MethodChannel / EventChannel (`com.medxai.sundr/ble`, `com.medxai.sundr/ble_events`).
- Real BLE testing requires a **physical Android device**; emulator has no usable BLE stack for this product.
- Foreground service owns connection lifecycle independent of Flutter UI process.
- Build constraint (CRIT, `eval/04.3`, `eval/07.5`): `compileSdk = 36` < `targetSdk = 37` violates AGP rule `compileSdk >= targetSdk` — fix to `compileSdk = 37` (SDK 37 stable as of 2026) or `targetSdk = 36` before any stable build. `ndkVersion = "28.2.13676358"` must exist on CI/dev images. `versionCode = 1`, `versionName = "1.0.0"` — bump discipline required.

---

## 3. User-facing entry points

| Entry | UI | When |
|-------|-----|------|
| Home device pill | `ring_scan_sheet.dart` (modal) | Primary everyday path |
| Onboarding / Settings | `device_bind_screen.dart` (full screen) | First-time or explicit rebind |
| Auto-reconnect | Native service | Last known address + logged-in user |

---

## 4. Pairing flow

```
Idle → Scanning → Connecting → Service discovery → Bond check
  → (bond if needed) → Bind success (CMD_BIND_SUCCESS, retry ≤3)
  → Connected
```

### Requirements

| ID | Requirement |
|----|-------------|
| BLE-01 | Start/stop BLE scan on user action; auto-stop scan after ~20s if no selection. |
| BLE-02 | Filter advertisements to product name prefixes (e.g. `R08_`, `R02_` / SUNDR naming). |
| BLE-03 | Show discovered devices with signal strength (RSSI) indication. |
| BLE-04 | On select, connect GATT, complete service discovery, ensure bond if required. |
| BLE-05 | On bind success, persist device address for reconnect (`SharedPreferences` / native). |
| BLE-06 | Provide “connect to last known device” when advertising stopped but device still bondable. |
| BLE-07 | Disconnect path clears or marks connection state; UI reflects disconnected. |
| BLE-08 | Auto-reconnect when logged in, Bluetooth on, and address known — including after reboot (`BootReceiver`). |
| BLE-09 | Do not start intrusive pairing prompts on the login screen (gate on `user_logged_in`). |
| BLE-10 | Emit connection, battery, and scan events to Flutter via EventChannel. |

---

## 5. Connection states (UI)

UI should expose at least:

- Disconnected / Idle  
- Scanning  
- Connecting  
- Connected (with optional battery %)  
- Error / timeout (non-fatal; allow retry)

`BleProvider` is the Flutter source of truth for connection fields consumed by Home and Settings.

---

## 6. Background service

| ID | Requirement |
|----|-------------|
| BLE-11 | `BleConnectionService` runs as a foreground service with a persistent notification while monitoring is active. |
| BLE-12 | Service starts early in app launch (`main.dart`) but reconnect loop respects login flag. |
| BLE-13 | System Bluetooth off/on handled via receivers without crashing the process. |
| BLE-14 | After device reboot, service can restart and attempt reconnect when appropriate. |
| BLE-15 | `BleConnectionService.onCreate` (`:149-170`) calls `startForeground(NOTIF_ID, notif)` inside try/catch honoring the ~5 s `startForeground` contract, then `MeasurementLoopManager.start:177`; `onStartCommand:187` returns `START_STICKY`. |
| BLE-16 | `onCreate` catches `ForegroundServiceStartNotAllowedException` (API 31 background-start restriction), not just generic `Exception`; on that path enqueue the WorkManager fallback and return without crashing (proposal status — see BLE-30). |
| BLE-17 | `lib/main.dart:45-61` splits `Permission.notification:52` out of the bulk `.request()`: if denied → request; if permanentlyDenied → `openAppSettings()`; result is honored, not ignored. |
| BLE-18 | `await _bleChannel.invokeMethod('startForegroundService'):57` handles `FGS_DENIED` / `FGS_START_NOT_ALLOWED` (PlatformException) instead of swallowing; on denial show the battery-saving GlassCard (see BLE-31). |
| BLE-19 | Receivers registered in manifest: `BootReceiver`, `SundrBluetoothReceiver`, `SundrSystemBluetoothReceiver` — Bluetooth + `BOOT_COMPLETED` wiring present. |
| BLE-20 | Native SDK calls always race an explicit timeout runnable (`BlePlugin.kt` 2913-line structure: explicit timeout runnables, `AtomicBoolean` double-resolve guards, coordinator acquire/release for manual measurements, retry logic for bind/temperature sync) so Flutter Futures never hang forever. |

---

## 7. Commands surface — full integrated inventory

Source of truth: `docs/mappings/sdk-vs-plugin.md` (verified 2026-09-19 from `qring_sdk_1.0.0.55.aar` javap + `BlePlugin.kt` + `ble_service.dart`, incl. `fetchRingHistory` dispatcher). Ring history buffer `dayIndex 0..6` (today … 6 days ago), bounded Dart-side by `kRingHistoryMaxDays = 7` (`ble_service.dart`); "view all history from the ring" = range fetch `startDay=0, count=7`.

### 7.1 Connection / device (mapped ✅)

| ID | Requirement |
|----|-------------|
| BLE-21 | Bridge exposes `connect`, `disconnect`, `isConnected`, `connectionState`, `startScan`, `bleCreateBond`, `findDevice`, `getBattery`, `getFirmwareVersion`, `setTime`, `startOta` end-to-end (channel → `BleOperateManager.getInstance()` → Dart). |

### 7.2 History families — getToday / getSingle(day) / getRange(start,count)

| Vital | SDK today | SDK single | SDK range | Channel | Dart | UI backfill | Status |
|---|---|---|---|---|---|---|---|
| Steps | `getTodayStepDetail` | `getStepDetail` | `getStepDetails` | `getStepsToday`/`getTodaySteps`/`getSteps`/`getStepsList` | ✅ all + `fetchRingHistory('steps')` | 🔶 `steps_screen._pullRingHistory` | ✅ |
| Heart rate | `getTodayHeartRate` | `getHeartRate` | `getHeartRates` | `getTodayHeartRate`/`getHeartRate`/`getHeartRates` | ✅ all + dispatcher | 🔶 `heart_rate_screen._pullRingHistory` | ✅ |
| Blood pressure | `getTodayBloodPressure` | `getBloodPressure` | `getBloodPressures` | all three | ✅ all + dispatcher | 🔶 `blood_pressure_screen._pullRingHistory` | ✅ |
| Pressure (stress) | `getTodayPressure` | `getPressure` | `getPressures` | `getTodayPressure`/`getPressure`/`getPressureList` | ✅ all + dispatcher | 🔶 `stress_screen._pullRingHistory` | ✅ |
| HRV | `getTodayHrv` | `getHrv` | `getHrvs` | `getTodayHrv`/`getHrv`/`getHrvList` | ✅ all + dispatcher | 🔶 `hrv_screen._pullRingHistory` | ✅ |
| Blood oxygen | `getTodayBloodOxygen` | `getBloodOxygen` | `getBloodOxygens` | all three | ✅ all + dispatcher | 🔶 `blood_oxygen_screen._pullRingHistory` | ✅ |
| Temperature | `getTodayTemperature` | `getTemperature` | `getTemperatures` | all three | ✅ all + dispatcher | ❌ blocked (semantics unverified) | ⚠️ |
| Sleep | `getTodaySleep` | `getSleep` | `getSleeps` | `getTodaySleep`/`getSleep`/`getSleepList` | ✅ all + dispatcher | 🔶 `sleep_screen._loadHistory` (pre-existing ref impl, `getSleepList(0, 7)`) | ✅ |
| Sport | `getTodaySport` | `getSport` | `getSports` | `getTodaySport`/`getSport`/`getSports` (+ legacy `getSportRecords`/`syncSportRecords` via `SportPlusHandle`) | ✅ all + `fetchRingHistory('sport')` | 🔶 `workouts_screen._pullRingSports` auto-merge | ✅ |
| Sport GPS | `SportLocation{mRateReal}` only — no lat/lng fields exist | n/a (HR samples, not coordinates) | — | — | Ring GPS impossible; phone GPS during manual workouts → `user_workouts.locations` → `gps_trace_screen` | ✅ (phone-side) |
| Emotion | `getTodayEmotion` | `getEmotion` | `getEmotions` | — | — | — | ❌ no consumer |
| Manual HR | `getTodayManualHeartRate` | `getManualHeartRate` | `getManualHeartRates` | `getTodayManualHeartRate`/`syncManualHeartRate` only | ⚠️ single/range missing | — | ⚠️ |
| Manual SpO₂ | `getTodayManualBloodOxygen` | `getManualBloodOxygen` | `getManualBloodOxygens` | — | — | — | ❌ |
| 3-point temp | `getTodayThreeTemperature` | `getThreeTemperature` | `getThreeTemperatures` | — (`manualTemperature_POC` only) | — | — | ❌ device-dependent |
| RRI | `getRriBlockList`/`getRriBlock` | `getRriHistory` | — | — | — | — | ❌ no consumer |

| ID | Requirement |
|----|-------------|
| BLE-22 | Every range API returns `[{"dayIndex": N, "data": {…same shape as single-day…}}]`; parsers accept both `dayIndex` and snake `day_index`, skip entries outside 0..6, skip empty days. |
| BLE-23 | All `_pullRingHistory` hooks follow the standard wiring pattern: early-return when `BleProvider.isConnected` false → `await _ble.fetchRingHistory('<vital>')` (bounded by Dart-side 10–15 s per-call timeouts) → per-day parse with the vital's proven keys → persist via existing `SupabaseService` upsert/insert (`upsertHr/Spo2/Hrv/Steps`, `insertBp/Stress` with `source: ring_history`) → quiet trend reload (`_load7DayTrend(quiet: true)` / steps `_loadDay(force: true)`) → whole body in `try/catch (_) {}` silent-offline, steps additionally generation-guarded via `_loadGen`. |
| BLE-24 | Verified range-payload contracts (gson, from AAR field lists): Steps `List<BleStepDetails>` via `ActivityEngine.parseIntervalJson` keys `d/f/e/g`; HR `ReadHeartRateRsp` map `array` fallback `mHeartRateArray` (signed→unsigned, keep 30–220); BP `List<BlePressure>` `{time, sbp, dbp}`, `time` s-or-ms auto-normalized by magnitude, keep 70–250/40–150; Pressure `PressureRsp` map `pressureArray` bytes (unsigned, drop 0xFF, clamp 0–100); HRV `HRVRsp` map `d` fallback `pressureArray` (unsigned, drop 0xFF) — NOTE today path (`BleProvider._parseAndSaveHrv`) reads only `d`, history hook (`hrv_screen._pullRingHistory`) covers both; SpO₂ `BloodOxygenEntity` map `array`+`minArray`+`maxArray` (keep 1–100); Temperature `IntervalTemperatureEntity` map `{array, values[{value1..3}], interval}` semantics unverified, NOT consumed; Sleep `SleepDisplay` map via `SleepEngine.parseSleepData`; Sport `SportPlusEntity` map `{mSportType→name, mStartTime(s), mDuration(s), mDistance(m), mCalories, mRateAvg, steps}` → history row + `insertWorkout`, `TYPE_APP_*` deduped by start second, mCalories kcal-vs-小卡 auto (≥10000 → ÷1000). |

### 7.3 Manual-measure triggers (mapped ✅)

| ID | Requirement |
|----|-------------|
| BLE-25 | Bridge exposes `manualModeHeart`, `manualModeBP`, `manualModeSpO2`, `manualModeHrv`, `manualModePressure`, `manualTemperature`, `manualThreeTemperature` (POC), `readHeartRate`, `insertHeartRate`, `insertHrv`, `insertSpo2`, `insertTemperature`, `cancelHeartRate`. |

### 7.4 Interval write path — ReadingRepository + BlePlugin dispatch + dedup (phase-1)

| ID | Requirement |
|----|-------------|
| BLE-26 | Native `ReadingRepository.kt:67-151` exposes `insertHeartRateAt(bpm,measuredAt,cycleId,source):67-84`, `insertSpo2At:87-99`, `insertHrvAt:122-141`, `insertTemperatureAt:134-151`. |
| BLE-27 | `BlePlugin.kt:449, 2819-2855, 993-1151` dispatches `insertHeartRate/insertSpo2/insertHrv/insertTemperature` + `syncInterval*Detail`; every `insert*` runs `repo.startCycle → insert*At → completeCycle → EventBus NewReadingEvent`. |
| BLE-28 | `syncIntervalHeartRateDetail` inflates `IntervalHeartRateEntity{dayIndex,interval,array}` → timestamp `dayStart + idx*interval*60k + 30k`, `insertHeartRateAt(source=interval_sync)` with ±30 s dedup; `syncIntervalSpo2Detail` (`bigData.IntervalBloodOxygenEntity`, `IIntervalBloodOxygenCallback`) same; `syncIntervalTemperatureDetail` handles `array:List<Float>` + `values:List<IntervalTemperature>` (`value1`) → `valueC/10` normalized to 30–45 range. |
| BLE-29 | Dart bridge `lib/services/ble_service.dart:663-682` exposes `insertHeartRate/insertSpo2/insertHrv/insertTemperature/syncIntervalHeartRateDetail/syncIntervalSpo2Detail/syncIntervalTemperatureDetail`. Interval blobs arrive via `LargeDataHandler` (~22 s transfer) → `BlePlugin syncInterval*Detail` → `insert*At` → Room → `safeRefreshDailySummary` → `daily_vital_summary`; phone poll (`MeasurementLoopManager` adaptive FAST 180 s / SLOW 900 s) uses same path (`source=auto_cycle`); manual tap uses same path (`source=manual`) → `getTodaySummary` → provider latest+avg. |

### 7.5 Deliberately unmapped — do not add without a feature

| ID | Requirement |
|----|-------------|
| BLE-30 | Emotion family, RRI family, Manual-SpO₂ family, 3-point-temp family, `ManualHR` single/range, `oneClickMeasurement`, `startOneKey`/`endOneKey` direct channels, `classicBluetooth*` / RTK-SPP APIs remain unmapped (no app consumer). Temperature history backfill is *blocked, not unmapped*: needs one live-ring `getTemperatureList` sample to pin `array` vs `values[]` semantics. Fall/motion has no SDK surface — phone-only by design (`FallMotionDetector` 50 Hz phone accel/gyro while armed → Room `fall_event` → Dart via `getFallEvents`; monitoring state via `getMotionSnapshot`); do not add ring-IMU channels without a new streaming SDK. |

---

## 8. Battery / foreground hardening (fix-ab/01 + changes-18, integrated)

| ID | Requirement |
|----|-------------|
| BLE-31 | `isIgnoringBatteryOptimizations` / `requestIgnoreBatteryOptimizations` (via `PowerManager`, `BlePlugin.kt:375`) + Home battery `GlassCard` are LANDED: `GlassCard` (margin h16, padding 16, orb amber `#FBBF24`, icon `battery_alert_rounded` 36 px in `glassButton 0x08FFFFFF`, title 14 px w500 white 0.95 "Background tracking may be restricted", body 12 px textSec, CTAs `Allow` gold `#C9A86E` → `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` + `Not now` snooze 7 d `battery_prompt_dismissed_until`), shown above `ALL METRICS` sliver (`HomeScreen:694`), once per 7 d, only if `loggedIn && isMasterEnabled`. `main.dart:45` queries the channel after bulk request; if false && loggedIn, set flag for the card. |
| BLE-32 | `ShortSyncService` + `WorkScheduler`/`MeasurementWorker.kt` + `enqueueWorkManagerFallback` + `FOREGROUND_SERVICE_SHORT_SERVICE` manifest entry are PROPOSED, not landed (zero `WorkManager` hits in `android/`, no `SHORT_SERVICE` in manifest): add `<uses-permission FOREGROUND_SERVICE_SHORT_SERVICE/>`, service `android:foregroundServiceType="shortService"`; `WorkScheduler` (`androidx.work:work-runtime-ktx:2.9`, `build.gradle.kts:92`) `CoroutineWorker` checks `MeasurementConfig.isMasterEnabled() && prefs flutter.user_logged_in && BleSdkLifecycle.isConnected()`, then single `walkSequence` subset (STEPS→HR→SpO2) + `SupabaseSyncManager.maybePush()`; periodic 15 m + expedited 1-shot. Dart wraps `startForegroundService` in `try on PlatformException (FGS_START_NOT_ALLOWED) → enqueueWorkManagerFallback` + GlassCard "Background tracking running in battery-saving mode (15 min)". |
| BLE-33 | Adaptive measurement timeouts (changes-18): per-vital rolling average (last 5, `responseTimes: ConcurrentHashMap<String, MutableList<Long>>`) → `adaptiveTimeout = max(avg × 1.5, 15 s)` (`MIN_TIMEOUT_MS = 15_000`, `TIMEOUT_HEADROOM_FACTOR = 1.5`, `ROLLING_WINDOW = 5`), clamped at fixed ceilings 60 s (HR/SpO2/Stress/BP) / 90 s (HRV/Temp); worst-case BLE-active ~7 min/cycle → typical ~2 min (60–80% cut). |
| BLE-34 | Adaptive cooldown: `FAST_COOLDOWN_MS = 180_000` (3 min, anomaly mode) / `SLOW_COOLDOWN_MS = 900_000` (15 min, healthy mode), `NORMALCY_CONFIRM_CYCLES = 2` (2+ consecutive normal `FallRiskAnalyzer.currentTier()` cycles stretch 3→15 min; any anomaly resets to 3 min; `YIELDED_TO_MANUAL → WORKOUT_RECHECK_MS`). Per-vital worst-case timeouts: Steps instant (passive), HR 60 s, SpO2 60 s, Stress 60 s, BP 60 s, HRV 90 s, Temp 90 s, each +2 s post-stop settle = 414 s worst case. |
| BLE-35 | `BleConnectionService` poll (`:81-117`): connected && stable (`connected && wasConnected`) → 30 s; freshly connected → 8 s; `SdkGuard.isOpen()` → 30 s; disconnected → exponential `BACKOFF_STEPS_MS` 8 s → 15 s → 30 s → 60 s → 120 s. CPU wake-ups ~10,800/day → ~2,700/day (−75%); BLE duty ~70% → ~15–30%. `WorkoutProvider.dispose()` sets `_isWorkoutActive = false` (`:308-344` hrLoop 4 s / stepsLoop 2 s fire-and-forget fix); `PrayerSessionProvider` adds `dispose()` canceling the 1 s timer + `stopWorkout()` + `setCycleCooldownMs(180000)` restore. Ring HR firmware interval `setHeartRateSetting(enable: true, interval: 10)` (`ble_provider.dart:1599-1602`) kept at 10 min per user request (QRing official 30–60 min noted, skipped). Debug via `adb logcat -s MeasurementLoop / BleConnectionService / FallRiskAnalyzer`; success = `app_incidents` `process_relaunch_scheduled` (34 rows/week `ForegroundServiceDidNotStartInTimeException`, e.g. 2026-08-07 18:54:17Z/19:05:12Z bursts) drops to <2. |
| BLE-36 | Smoothing (phase-1 `MeasurementLoopManager.kt:229-327`): lower-median `sorted[(size-1)/2]` (was upper-median `sorted[size/2]` pinning 87 for `[65,87]`), pin band `|Δ| ≤ 12` (was 8), with lower-median rationale comment. |

---

## 9. Acceptance criteria

- [ ] User can scan, see only relevant rings, and connect successfully.
- [ ] After force-stop of UI, service can still hold or restore connection when process allowed.
- [ ] After reboot (with permissions), service restarts and reconnects if user was logged in.
- [ ] Disconnect from Settings/UI updates Home device pill.
- [ ] Scan timeout does not leave UI stuck in scanning forever.
- [ ] Last-device connect works when advertising is silent.
- [ ] `flutter analyze --no-pub` clean; `flutter test` 123 passed; `gradle :app:compileDebugKotlin` BUILD SUCCESSFUL.
- [ ] Detail heroes show `latest` (e.g. 65) while AVG pill stays historical (e.g. 87) — not frozen; 2 h disconnected → ~12 backfilled interval points populate hourly chart.
- [ ] `adb shell dumpsys activity services | grep BleConnectionService` shows the service; `process_relaunch_scheduled` <2/week.
- [ ] Range pull `0..6` for Steps/HR/BP/Pressure/HRV/SpO₂/Sleep/Sport lands rows with `source: ring_history`; Temperature remains blocked pending one live-ring sample.

---

## 10. Known limitations

- Vendor SDK does **not** expose continuous raw accelerometer/gyro streams for fall IMU (see fall spec; phone-only by design).
- Temperature one-click paths may be unreliable (vital often disabled by default); `IntervalTemperatureEntity$IntervalTemperature` nested-float vs `array` dual path needs field test (`supportTemperatureBoth`); pressure interval has no SDK entity — poll-only.
- Blood Sugar / ECG interval families missing (`getContinuousSugar` returns `"[]"` stub, `startEcgMeasure` returns `"{}"` stub); HRV LargeData gated on firmware `supportHrv` flag (`getDeviceSupport`).
- iOS BLE integration is not the active product path.
- QRing declares Health Connect `WRITE_STEPS`, `WRITE_HEART_RATE`, `WRITE_SLEEP`, `WRITE_TOTAL_CALORIES_BURNED`; our app additionally writes SpO₂, HRV, BP, temperature (`tryWrite*` in `health_connect_service.dart`).

---

## 11. Related

- [03-vitals-monitoring.md](./03-vitals-monitoring.md)  
- [10-settings-device.md](./10-settings-device.md)  
- `architecture/Native_Android.md`, `architecture/InterOp.md`
- `docs/mappings/sdk-vs-plugin.md`, `docs/mappings/history-coverage.md`, `docs/mappings/qring-1.0.1.131-notes.md`
- `docs/qring/phase-1-core-vitals-flow.md`, `docs/fix-ab/01-battery-and-foreground.md`, `docs/changes-18/battery-analysis.md`, `docs/changes-18/implementation-details.md`, `docs/changes-18/summary.md`
