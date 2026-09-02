# 05 — Upgrade Results (2026-09-02, Flutter 3.47.2 / Dart 3.13.2)

## Action Executed
1. **pubspec.yaml** — direct deps widened to `^` latest per `01`:
   - `permission_handler: ^13.0.1` (was `11.4.0` exact)
   - `share_plus: ^13.3.0` (was `10.1.4` exact)
   - `firebase_core: ^4.14.0` (was `^3.0.0`)
   - `firebase_messaging: ^16.6.0` (was `^15.0.0`)
   - `geolocator: ^14.0.3` (was `^13.0.1`)
   - `health: ^13.3.2` (was `^13.3.1`)
   - `package_info_plus: ^10.2.1` (was `^9.0.1`)
2. `flutter pub upgrade --major-versions` → **32 dependencies changed** (`_flutterfire_internals 1.3.59→1.3.77`, `device_info_plus 12.4.0→13.2.0`, `permission_handler_android 12.1.0→14.0.0`, `win32 5.15→6.4`, etc.). Committed `pubspec.lock`.
3. Fixed `share_plus` 10→13 breaking API: `Share.share` → `SharePlus.instance.share(ShareParams(...))` in `lib/screens/home/home_screen.dart:932`, `lib/screens/social/friends_screen.dart:58`, `lib/screens/workouts/workout_detail_screen.dart:156`, `lib/widgets/screenshot_share.dart:24`.
4. Attempted **Built-in Kotlin migration** per `02`:
   - Set `android.builtInKotlin=true` + removed `id("org.jetbrains.kotlin.android")` from `android/app/build.gradle.kts`.
   - Build **failed**: `health-13.3.2/android/build.gradle:25 Failed to apply plugin 'kotlin-android' — no longer required since AGP 9.0`. Also `compileSdk not specified` in health.
   - **Reverted** to `android.builtInKotlin=false` and restored `id("org.jetbrains.kotlin.android")` — required until upstream `health` migrates. Documented in `android/gradle.properties` comment.
5. `flutter pub outdated` after upgrade:
   - `direct dependencies: all up-to-date.`
   - `transitive: material_color_utilities 0.13.0→0.13.1, cli_util 0.4.2→0.6.0, test_api 0.7.12→0.7.13` — constrained by Flutter SDK, acceptable.
6. `flutter analyze` → **2 info** only (`sleep_screen:605,649 curly_braces` pre-existing). No errors. Deprecated `Share` warnings resolved.
7. `flutter build appbundle --release` → **√ Built 66.8MB in 327.3s** (was 66.7MB pre-upgrade). Warnings:
   - `app` still applies KGP (expected, kept for compat)
   - Plugins still applying KGP: **`firebase_core, health, speech_to_text`** (down from 5: `device_info_plus, health, package_info_plus, share_plus, speech_to_text`). So `device_info_plus 13.2.0`, `package_info_plus 10.2.1`, `share_plus 13.3.0`, `geolocator 14.0.3`, `permission_handler 13.0.1` are now clean.

## KGP Tracker Update (see 03)
| Plugin | Before | After | Still warns? |
|--------|--------|-------|--------------|
| device_info_plus | 12.4.0 | 13.2.0 | **No** |
| package_info_plus | 9.0.1 | 10.2.1 | **No** |
| share_plus | 10.1.4 | 13.3.0 | **No** |
| geolocator | 13.0.4 | 14.0.3 | **No** |
| permission_handler | 11.4.0 | 13.0.1 | **No** |
| health | 13.3.1 | 13.3.2 | **Yes** — still `kotlin-android` |
| firebase_core | 3.15.2 | 4.14.0 | **Yes** |
| speech_to_text | 7.0.0 | 7.0.0 | **Yes** |

Action: Keep `android.builtInKotlin=false` until those 3 migrate; file issues per `02` template when ready. Next Flutter upgrade (`≥3.48`) may force `true` — monitor `03`.

## Next Steps
- Watch `health`, `firebase_core`, `speech_to_text` changelogs for “migrate to built-in Kotlin”; re-run `02` steps when they land.
- Keep `pubspec.yaml` on `^` latest — run `flutter pub outdated` weekly; direct deps now `auto-float`.
