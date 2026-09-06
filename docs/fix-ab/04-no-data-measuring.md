# 04 — No-Data Measure Card Measuring State

## Problem

`if (!hasData && !_loading && !_loadingDay && !_dayOffline) NotEnoughDataCard` is exclusive of `RealTimeCard` (`heart_rate:688`, `blood_oxygen:708`, `hrv:735`, `stress:624`, `temperature:683`, `blood_pressure:761`). `_measuring` not in guard → empty+measuring shows static card, hero only `···`.

## Fix (reuse `not_enough_data_card.dart:9-68`)

* Add `final bool measuring=false` to `NotEnoughDataCard:12`, `onPressed: (isConnected && !measuring)`, `child: measuring ? CircularProgress Indicator(gold) : Text(measureLabel)` (same spinner as `RealTimeCard:91`).
* Pass `measuring:_measuring` in 6 screens (`heart_rate:692`, `blood_oxygen:712`, `hrv:739`, `stress:628`, `temperature:687`, `blood_pressure:765`). Keep `sleep:701` + `steps:644` without button.

## Verification

* Empty past date → single card with spinner during 5-90s BLE wait.
