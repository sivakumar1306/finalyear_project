# Phase 4 — Multimedia & Sport Granularity

> **Status:** STARTED `2026-08-27` — hub exists, per-type detail pending — 3 weeks est. Closes QRing vs Sundr `91/240` activities gap for sport/media.

## QRing Reference
- **Sport 20 types:** `activity_aerobics.xml/running/cycling/swimming/hiking/yoga/...` 20 `newy` activities + `activity_sport.xml/detail_calorie/distance/go/prepare/running` `fragment_day_sport/week/month/year` `SportPlusRepository` `sport_plus_detail(device_address,date_str,start_time,sport_type,duration,distance,calories,steps,rate_value,avg_rate)` `gps_detail` `BleSport` `AppSportRsp` (`classes5.dex` +20).
- **Watchface:** `WatchFaceInstallActivity`, `PlateFragment/diy/Market`, `WatchFaceRepository` download `http://api2.qcwxkjvip.com/download/watchface`.
- **Album/Ebook/Music:** `AlbumActivity/PhotoGallery`, `EbookManagerActivity`, `MusicManagerActivity/Album`, `AlbumToDeviceActivity` `ContactActivity`, `CameraActivity` (`CameraReq` already in `BlePlugin:200+`).
- **Display:** `ScreenLightActivity`, `GoalSetting`.

## Sundr Now
- Single `workouts_screen:1050` generic 12 `WorkoutCategory` `workout_model:338` (130+ sports strings) + `active_workout:412` + `WorkoutService.kt:294` foreground, `syncSportRecords:2123` raw JSON stub `specs/00:87`.
- `ring_camera_screen:317` shutter only + `scanMediaFile` passthrough, `display_settings_screen:145` brightness/clockStyle/orientation, `musicians` `gesture_settings:227 toggleMediaPlayPause` only.

## Plan

### 4.1 Sport Granularity
- Keep `workouts_screen` as hub; add `lib/screens/workouts/sport_type_detail_screen.dart` per QRing `sport_type` (run, cycle, swim etc.) parsing `ReadDetailSportDataReq` via `SportPlusHandle` (existing import `BlePlugin:99`).
- `android/.../BlePlugin` expose `getSportDetail(type, date)` → `BleService.getSportDetail` → `ReadingRepository`? Actually `sport_plus_detail` is ring-stored, not Room — cache to `user_workouts` with `workout_type`.
- `lib/models/workout_model.dart` extend `WorkoutCategory.sports` already covers QRing 20 mapped to 12 categories; add `perSportTarget` map.

### 4.2 Watchface
- `lib/screens/watchface/watchface_store_screen.dart` grid `WatchMarketFragment` + `WatchFaceDiyFragment` (DIY omitted first cut — gallery + install only).
- Native `BlePlugin` `FileHandle` OTA `startOta(filePath)` already; reuse for watchface `DownloadWithoutNotification`.

### 4.3 Album/Ebook/Music
- `lib/screens/album/album_screen.dart` browse `albumRepository` local storage (no new Supabase — device-local).
- `lib/screens/ebook/ebook_screen.dart` stub reader `EbookManager` font.
- `lib/screens/music/music_album_screen.dart` list `MusicRepository` albums.

### 4.4 GPS Trace
- `lib/screens/workouts/gps_trace_screen.dart` polyline from phone `geolocator` (ring has no coordinates; `google_maps_flutter` is **not** a dependency — custom polyline), store to `user_workouts.locations` (column already in schema).

### Completion Table (2026-08-27 14:00)

| # | Item | Location | Status | Notes |
|---|------|----------|--------|-------|
| 1 | `workout_model` 12 categories 130+ sports | `lib/models/workout_model.dart:338` | ✅ Completed | Already covers QRing 20 mapped |
| 2 | `workouts_screen` hub + `active_workout` | `lib/screens/workouts/workouts_screen.dart` (1219 lines) | ✅ Completed |  |
| 3 | `sport_type_detail_screen.dart` per-type detail | `lib/screens/workouts/sport_type_detail_screen.dart` | ✅ Completed (stub) | File exists; ring per-type trace depth pending |
| 4 | `watchface_store_screen.dart` `WatchMarketFragment` | `lib/screens/watchface/watchface_store_screen.dart:1` | ✅ Completed (stub) | `GlassCard` + route `/watchface`, reuse `FileHandle` OTA |
| 5 | `album_screen.dart` / `ebook_screen.dart` / `music_album_screen.dart` | `lib/screens/album/*` | ✅ Completed (stub) | Files exist; `scanMediaFile` passthrough exists |
| 6 | `gps_trace_screen.dart` polyline | `lib/screens/workouts/gps_trace_screen.dart` | ✅ Completed (stub) | Phone-GPS polyline, no `google_maps_flutter` dep |

### Next: scaffold `sport_type_detail_screen` shell then `watchface_store`.

### Acceptance
- 20 sport types selectable, detail shows `duration/distance/calories` from ring trace not just generic.
- Watchface install progress via `ota_screen:424` existing `DfuHandle`.

### Risks
- GPS needs `ACCESS_FINE_LOCATION` already `AndroidManifest`; map key.
