# 03 — Heart Rate Always Crashes (XAPK QRing_1.0.1.131 Cross-Check)

## XAPK Evidence (`QRing_1.0.1.131_apkcombo.com.xapk`, 118MB)

* QRing dex (`classes4/5.dex`) references `syncManualHeartRateList` (1 hit each) + `MyDeviceNotifyListener` (36 hits) + `ManualHeartRate`/`DetailBean(m,v)` + `queryManualHeart`/`saveManualHeartRate` — its one-click HR = live notify **plus** ring-recorded manual-list sync. Our app never called `syncManualHeartRateList` (no handler existed).
* Our SDK `qring_sdk_1.0.0.55.aar` already contains `syncManualHeartRateList`, `getManualHeartRate(s)`, `getTodayManualHeartRate`, `ManualHeartRate{index,data[]}`, `ILargeDataManualHeartRateResponse` — no SDK upgrade needed.
* `StartHeartRateRsp.class` (SDK) exposes `getErrCode()` — our code never checked it, so ring "not worn / weak signal" errors became silent 60s TIMEOUTs.
* Our `readHeartRate` streaming (`manualModeHeart(cb,false)`, stop `(null,true)`) matches SDK signature; frame-type gate (`getHeartRate()>0`, else `type==12 → value`) retained.

## Ranked Causes

* **H1 BUSY→TIMEOUT:** `MeasurementLoopManager:52 OWNER="loop"` + `POST_STOP_SETTLE 2s:51` + `PREEMPT 200ms:57` vs `BlePlugin:828 MANUAL_ACQUIRE_TIMEOUT` (was 4000, now 8000). Loop holds lock for median agreement `measureHeartRate:229` (2 consecutive `abs≤12`, lower-median). Manual tap sets `manualRequestPending`, `watchForPreempt:217` yields but release delayed 2s → deadline expires → `BUSY:837` → retry → 8 fails → `SdkGuard.open 45s`.
* **H2 Double-reply:** `BlePlugin:994 postDelayed 60s TIMEOUT` not cancelled on `onDeviceDisconnected:673` → `result.success(null):980` then `result.error(TIMEOUT)` → `IllegalStateException: Reply already submitted` → process death, `CrashStore:77`. Fixed via stored `timeoutRunnable` + `removeCallbacks` on success paths.
* **H3 Ignored errCode:** ring error frames counted as "no data" until timeout. Now fail-fast `HR_ERR_<code>` with "keep ring snug" message.
* **H4 No list fallback:** streaming miss = total failure. Now `syncManualHeartRate` large-data fallback (QRing parity) before surfacing failure.

## Fix Implemented

* `BlePlugin.kt:141` `MANUAL_ACQUIRE_TIMEOUT 4000→8000`; `readHeartRate:951` early `SDK_GUARD_OPEN` / `NOT_CONNECTED` guards; errCode fail-fast `HR_ERR_*`; stored `timeoutRunnable` cancelled on success; new `syncManualHeartRate` bridge (`LargeDataHandler.syncManualHeartRateList` → `ILargeDataManualHeartRateResponse.manualHeart` → `[{index,data:[{m,v}]}]` JSON).
* `MeasurementLoopManager.kt:311` auto path skips `errCode!=0` frames (log, don't count as candidate).
* `ble_service.dart` `syncManualHeartRate()` wrapper.
* `heart_rate_screen.dart:436` streaming → `_tryManualListFallback()` (latest valid 30-220 from list) → mapped `_measureErrorMessage` (`BUSY`/`TIMEOUT`/`NOT_CONNECTED`/`SDK_GUARD_OPEN`/`HR_ERR_*`).

## Verification

* `logcat -s MeasurementLoop:D BlePlugin:D | grep -E "BUSY|TIMEOUT|Reply already|candidate=|errCode"`, `sqlite3 ... "select vital,status from measurement_attempt ..."`, `app_incidents source='heart_rate_screen'`.
* `flutter test` 113 passed after change.
