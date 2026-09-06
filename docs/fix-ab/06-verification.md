# 06 — Verification

* `dart analyze`, `flutter test` (new `MeasurementAttempt` tests).
* `adb logcat -s MeasurementLoop:D SdkGuard:D BlePlugin:D flutter:I | grep -E "BUSY|TIMEOUT|Reply already|isValidBpm|candidate=|isMasterEnabled|circuit OPEN"`.
* `adb shell run-as ... sqlite3 qring_local.db "select vital,status,error from measurement_attempt order by startedAt desc limit 5; select * from measurement_cycle order by id desc limit 5;"`.
* Supabase `app_incidents`: `process_relaunch_scheduled` 34/week → <2, `setState after dispose` 18 → 0, `source='heart_rate_screen'`.
* Manual: empty detail → `NotEnoughDataCard` spinner during `readHeartRate`; Settings → Measurement Log shows 3d grouped by `cycleId` + Failed toggle.
