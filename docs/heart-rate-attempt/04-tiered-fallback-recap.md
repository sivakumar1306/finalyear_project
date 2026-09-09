# 04 — Tiered strict/legacy extraction recap (earlier fix, still active)

## Strict tier (type-aware, junk-resistant)

* Manual `BlePlugin.readHeartRate` + auto `MeasurementLoopManager.measureHeartRate`
  accept `getHeartRate()>0` (type 13) or `type==12 → value`, gated on
  `VitalRanges.isValidBpm(30–220)`. Type-14 SpO2 frames, `0xFF` sentinels, and
  cross-vital bytes are rejected instead of persisted as bpm.
* Auto requires two consecutive candidates within 12 bpm (lower-median);
  manual returns the first strict value immediately. Neither gates on
  `rsp.status` (intermediate calibration frames lack `RESULT_OK`).

## Legacy fallback (pre-Aug24 mechanism, range-gated)

* Pre-Aug24 code was first-nonzero `getHeartRate else getValue` with no checks.
  Restored as second tier only: collected in parallel, median used solely when
  strict produced nothing by timeout. Still 30–220 gated per agreement.
* Tagged: auto source `auto_cycle_fallback`, attempt
  `valueJson {"extractor":"legacy",…}` (`strict` / `strict_timeout` otherwise).

## Honest logging

* `walkSequence` no longer marks a still-`RUNNING` HR attempt `success`; it
  records `failed_no_data`. `persist()` skips `NewReadingEvent` on rejected
  inserts (`id<=0`). Measurement Log `success` now means a row was written.
* Expected Dart failures (`TIMEOUT/HR_ERR_/BUSY/NOT_CONNECTED/SDK_GUARD_OPEN`,
  now also `CANCELLED/DISCONNECTED`) stay `debugPrint`-local; only unexpected
  errors reach `app_incidents`.

## Interval backfill

`syncInterval*Detail` array casts fixed (`List<*> filterIsInstance<Number>` +
`IntArray/FloatArray/DoubleArray`) so ring history blobs inflate into rows
instead of silently returning empty.
