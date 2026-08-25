# QRing Parity Roadmap — Sundr

> **Source:** `com.app.cq.ring v1.0.1.131` (`C:\Users\sugee\Downloads\QRing_1.0.1.131_apkcombo.com.xapk` → `qring_unpack` 3386 entries, `qring_extracted` dex) vs `Vital2026` `lib/` 160 dart, `BlePlugin.kt:3114`, `MeasurementLoopManager:582`, `supabase` 9 migrations.

## Vision
Bring Sundr to **QRing functional parity** where it matters for health accuracy, then extend with Sundr’s premium safety (fall risk, Health Connect) and luxury UX (`DESIGN.md` `#C9A86E` glassmorphism). Do not replicate QRing’s packer obfuscation or light-theme.

## Principles
- **Offline-first `today`**: Room `qring_local.db` is source of truth, Supabase is history. `ReadingRepository.daySummaryFromRaw` + `DailyVitalSummaryEntity` rollup.
- **QRing blob fidelity**: Ring logs autonomous interval blobs even when phone off (`heart_rate_detail` 1/day `interval/index_str/value TEXT`). Phone *polling* alone (`MeasurementLoopManager` `3min` round-robin) is sparse — must backfill via `LargeDataHandler`.
- **Hero = latest, stats = avg/min/max**: QRing shows last measured badge + discrete dots; AVG inertia (`87` freeze) is anti-pattern. Every vital detail + home card foregrounds `latest` with `avg` secondary and `avg · no fresh reading` stale pill after `30min`.
- **No fake buckets**: Do not inject `hourly[now.hour]=avg` when no slot; leave gap (QRing leaves slot empty).

## Phase Map

| Phase | Scope | Status | Completion | Doc |
|-------|-------|--------|------------|-----|
| **1** | Core vitals unified data flow (HR/SpO₂/HRV/Temp) — latest hero, interval backfill, median de-bias, cloud polish, home/cards | **Completed** `2026-08-26` | 100% — all `latest` heroes, interval `HR/SpO₂/Temp`, `MeasurementLoopManager` lower-median, 80 tests pass | `phase-1-core-vitals-flow.md` |
| **2** | Detailed health: ECG, Breath, Blood Sugar continuous/Lipids, Pressure interval, One-Key | **In Progress** `2026-08-27 13:00` — models + migration + 3 screens + routes `/ecg /breath /blood-sugar` live, wrappers `getEcgHistory` | 45% — scaffolding done, native BLE `EcgReq` pending | `phase-2-detailed-health.md` |
| **3** | Religious & social: Quran/Qibla, Muslim Goal V2, Friends/Lover, Nutrition | **In Progress** `2026-08-27 14:00` — `QiblaService` bearing, `Quran/Qibla/Friends/Nutrition` stubs + routes `/quran /qibla /friends /nutrition` | 35% — 5 stubs `GlassCard` `DESIGN.md` | `phase-3-social-religious.md` |
| **4** | Multimedia & sport granularity: Watchface Store, Album/Ebook/Music, 20 sport types, GPS trace | **In Progress** `2026-08-27 14:00` — `watchface_store` stub + route `/watchface` | 20% — hub exists, per-type detail + GPS pending | `phase-4-multimedia-sport.md` |
| **5** | System polish: `qc_setting_*` parity (42 ids), OTA, `LargeDataHandler` 13 handlers, Supabase `40+` tables, release signing | **In Progress** — 7/13 handlers, 29/40 tables | 35% — settings 60% parity | `phase-5-system-polish.md` |

### Progress Overview (2026-08-27 14:00)

| Metric | QRing | Sundr Before | Sundr Now | Delta |
|--------|-------|--------------|-----------|-------|
| `LargeDataHandler` families | 9 | 4/9 (44%) | 7/9 (78%) `HR/SpO₂/Temp interval` added | +33% |
| Supabase tables | 40+ | 26 | 29 (`+user_ecg/breath/blood_sugar`) | +3 |
| Named routes `lib/app.dart` | ~240 Act. | 21 | 29 (`+ecg/breath/blood-sugar +quran/qibla/friends/nutrition/watchface`) | +8 |
| Health screens hero `latest` | 100% | 25% (only Temp/BP/Stress) | 71% (HR/SpO₂/HRV added) | +46% |
| `qc_setting_*` parity | 42 ids | 60% | 60% (no regression) | — |
| Glass screens new | — | — | 8 new `breath/ecg/blood-sugar/quran/qibla/friends/nutrition/watchface` all `AppTheme.bg` `GlassCard` `MetricChartCard` | +8 |

## Cross-cutting Stack
- **BLE:** `android/app/libs/qring_sdk_1.0.0.55.aar` (`IntervalHeartRateEntity{dayIndex,interval,array:List<Int>}`, `IntervalBloodOxygenEntity`, `IntervalTemperatureEntity{array:List<Float>, values:List<IntervalTemperature>}`, `IIntervalHeartRateCallback` etc.) via `BlePlugin.kt` `LargeDataHandler` + `BleOperateManager` + `CommandHandle`.
- **Native DB:** `QRingDatabase.kt:64` `ReadingEntities.kt:197` tables `reading_heart_rate/spo2/hrv/temperature/blood_pressure/stress/steps` + `daily_vital_summary` `(vital,dayEpochMs)` PK.
- **Cloud:** `supabase/migrations` `user_hr/spo2/hrv/steps` + per-event `user_bp/stress/temp` + streaming `user_hr_readings` etc. Missing `user_ecg/breath/blood_sugar/quran` etc.
- **UX:** `DESIGN.md` dark `05,05,05` glass `rgba(255,255,255,0.06) blur 28px radius 20` orb `70px 40-60%`.

See each phase file for file-level `absolute path:line` change lists and acceptance criteria.
