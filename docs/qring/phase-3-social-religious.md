# Phase 3 — Social & Religious (Quran/Qibla, Muslim Goal V2, Friends/Lover, Nutrition)

> **Status:** STARTED `2026-08-27` — doc only, 0% code — 2–3 weeks est. Preserves QRing MENA market while keeping Sundr premium dark (`DESIGN.md`).

## QRing Reference
- **Muslim:** `activity_muslim.xml/detail/goal/v2/more`, `fragment_day_muslim.xml/month`, `MuslimRepository` `muslim_detail(device_address,date_str,interval,index_str,counts,unix_time)` `muslim_total`, `worship_time_entity(worship_uuid,date_str,worship_time,is_selected,offset_time)` `quran_entity(content_uuid,title_json,is_collection)`, `customer_praise_entity(praise_count)`, `anla_name_entity(arabic_name,chinese,english)` `QiblaDirection(lastQiblaAngle)` `Adhan` lib `calculateQiblaDirection` (`classes5.dex` `7Lcom/oudmon/ble/.../MuslimReq`, `res/layout/activity_muslim*.xml`).
- **Friends/Lover:** `activity_friends_home/ranking/lover_space/memorial`, `FriendsRepository/LoverRepository` `RingStepUpdateEvent`, `syncFriendsDataToServer(StepModel/LunchSleep)` (`classes5.dex` +14 activities).
- **Nutrition:** 30 `config/activity/*` `NutritionActivity/Calorie/Carbohydrates/Protein/Vitamins` + `GoalSetting` `qc_goal_*` (`res/layout/activity_nutrition.xml`).

## Sundr Now
- Prayer only `lib/screens/prayer/prayer_session:651/prayer_history:620/prayer_summary:280` + `PhoneModePlugin:130` Focus/Prayer DND (`specs/09` shipped Android).
- `advanced_settings_screen:104` `muslimMode` toggle only.
- `companion_alert_screen:216` SOS, 0 hits `friends|lover|quran|qibla`, `goal_setting:454` steps/calories/sleep only.

## Plan

### 3.1 Muslim Expansion
- `lib/services/qibla_service.dart` `SensorManager` `TYPE_ROTATION_VECTOR` + `Geolocator` + `adhan2` `Qibla` → `bearing`.
- `lib/screens/quran/quran_screen.dart` asset `assets/quran/quran.json` (`qring_extracted/quran.json:117321`) + `QuranChapterDetail` bookmark `is_collection` in `quran_entity`; `QiblaScreen` compass `CustomPainter` (reuse `DESIGN.md` gold `#C9A86E`).
- `lib/screens/prayer/muslim_goal_v2_screen.dart` offset time `MuslimOffsetTimeDialog` (`layout_dialog_muslim_offset_time.xml`).
- `supabase` table `user_quran_bookmarks(user_id,content_uuid,is_collection)`, `user_worship_times` mirror `worship_time_entity`.

### 3.2 Friends/Lover (reuse caregiver)
- Extend `supabase 20260821000000_emergency_alerting.sql` caregiver links: `user_friends(user_id,friend_user_id, status)` + `lover_links` reuse `caregiver_links` type column.
- `lib/screens/social/friends_screen.dart` `Ranking` `step_detail` share, `LoverSpace` memorial, `MyQrCode` `QRCodeScan` (existing `qr_code_scan` dep).
- `BleProvider syncFriendsDataToServer` stub call `FriendsRepository.sync`.

### 3.3 Nutrition
- `lib/models/nutrition_model.dart` `NutritionLog(date, calories, carbs, protein)` + `lib/screens/nutrition/nutrition_screen.dart` reuse `MetricChartCard`.
- `supabase user_nutrition_logs(user_id,date,calories)` unique.

### Completion Table (2026-08-27 14:00 — Phase 3 kickoff)

| # | Item | Location | Status | Notes |
|---|------|----------|--------|-------|
| 1 | `qibla_service.dart` `SensorManager` + `Geolocator` + `adhan2` | `lib/services/qibla_service.dart:1` | ✅ Completed (stub) | Bearing calc done, compass stream stub `yield 0` |
| 2 | `quran_screen.dart` + `assets/quran/quran.json` `quran_entity` bookmark | `lib/screens/quran/quran_screen.dart:1` | ✅ Completed (stub) | GlassCard + placeholder, 117321 bytes `qring_extracted/quran.json` |
| 3 | `QiblaScreen` compass `CustomPainter` gold `#C9A86E` | `lib/screens/quran/qibla_screen.dart:1` | ✅ Completed (stub) | `GlassCard` `QiblaService.bearing` demo `Riyadh→Kaaba` |
| 4 | `muslim_goal_v2_screen.dart` offset dialog | `lib/screens/prayer/muslim_goal_v2_screen.dart` | ⬜ Not Started | `layout_dialog_muslim_offset_time` |
| 5 | `user_quran_bookmarks` + `user_worship_times` Supabase | `supabase/migrations/20260902_quran.sql` | ⬜ Not Started |  |
| 6 | `user_friends` + `lover_links` (reuse `caregiver_links`) | `supabase/migrations/20260902_social.sql` | ⬜ Not Started |  |
| 7 | `friends_screen.dart` ranking + `LoverSpace` + `MyQrCode` | `lib/screens/social/friends_screen.dart:1` | ✅ Completed (stub) | `GlassCard` + routes `/friends` |
| 8 | Nutrition `nutrition_model.dart` + `nutrition_screen.dart` | `lib/models/nutrition_model.dart:1` + `lib/screens/nutrition/nutrition_screen.dart:1` | ✅ Completed (stub) | `MetricChartCard` stub, routes `/nutrition` |
| 9 | Routes `/quran /qibla /friends /nutrition` | `lib/app.dart:34,60` | ✅ Completed | 28 routes now |

### Next: scaffold `qibla_service` + `quran_screen` shell (glass) in Phase 3 kickoff.

### 3.4 Acceptance
- Qibla bearing within `±5°` of QRing `lastQiblaAngle`.
- Quran chapter list loads offline.
- Friends invite via QR works without ring (pure cloud).

## Risks
- Keep `lib/screens/settings/faq_screen.dart:46` QRing FAQ verbatim but Sundr `DESIGN.md` dark — avoid light `qring_extracted` bg (`res/layout` white).
