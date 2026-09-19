# QRing 1.0.1.131 (reference app) notes

- Package `com.app.cq.ring`, `versionCode 131`, `versionName 1.0.1.131`,
  XAPK `QRing_1.0.1.131_apkcombo.com.xapk` (118 MB, base APK + splits).
- Uses the same `com.oudmon.ble` SDK family (`oudmon` ×621,
  `BleOperateManager` ×10 in dex), but the release dex is R8-obfuscated,
  so per-method comparison against our AAR (`qring_sdk_1.0.0.55.aar`,
  unobfuscated) is not possible statically.
- Our AAR's `javap` surface is therefore the authoritative API list
  (see `sdk-vs-plugin.md`); the ring protocol (dayIndex `0..6` history
  buffer) is identical across both.
- QRing declares Health Connect `WRITE_STEPS`, `WRITE_HEART_RATE`,
  `WRITE_SLEEP`, `WRITE_TOTAL_CALORIES_BURNED` — our app additionally
  writes SpO₂, HRV, BP, and temperature (`tryWrite*` in
  `health_connect_service.dart`).
- No newer history opcodes were recoverable from the obfuscated dex;
  if a future QRing release documents a larger ring buffer, bump the
  `count` in `fetchRingHistory` and the screens' trend windows together.
