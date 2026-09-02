# 01 — Dependency Upgrade Plan (Latest by Design)

> Goal: Eliminate `flutter pub outdated` drift (30 stale) by moving every direct + transitive dependency to its latest resolvable version, matching the “latest by design” rule.

## Current State (2026-09-02, Flutter 3.47.2)
`flutter pub outdated` reports 30 packages stale:

| Bucket | Packages |
|--------|----------|
| **Direct 7** | `firebase_core 3.15.2 → 4.14.0`, `firebase_messaging 15.2.10 → 16.6.0`, `geolocator 13.0.4 → 14.0.3`, `health 13.3.1 → 13.3.2`, `package_info_plus 9.0.1 → 10.2.1`, `permission_handler 11.4.0 → 13.0.1`, `share_plus 10.1.4 → 13.3.0` |
| **Transitive 21** | `_flutterfire_internals 1.3.59→1.3.77`, `carp_serializable 2.0.1→3.0.0`, `clock 1.1.2→1.1.3`, `code_assets 1.2.1→2.0.0`, `device_info_plus 12.4.0→13.2.0`, `device_info_plus_platform_interface 7.0.3→8.1.0`, `firebase_core_platform_interface 6.0.3→8.1.1`, `firebase_core_web 2.24.1→3.11.0`, `firebase_messaging_platform_interface 4.6.10→4.10.0`, `firebase_messaging_web 3.10.10→4.2.5`, `geolocator_android 4.6.2→5.0.3`, `hooks 2.0.2→2.2.0`, `material_color_utilities 0.13.0→0.13.1`, `objective_c 9.5.0→9.6.0`, `package_info_plus_platform_interface 3.2.1→4.1.0`, `permission_handler_android 12.1.0→14.0.0`, `share_plus_platform_interface 5.0.2→7.2.0`, `stack_trace 1.12.1→1.12.2`, `test_api 0.7.12→0.7.13`, `win32 5.15.0→6.4.0`, `win32_registry 2.1.0→3.0.3` + `cli_util 0.4.2→0.6.0` (dev) |

`pubspec.yaml` pins coarse ranges (`firebase_core ^3.0.0`, `permission_handler 11.4.0` exact, `share_plus 10.1.4` exact) — prevents `pub upgrade` from resolving latest.

## Upgrade Strategy

### Step 1 — Unpin & widen ranges (pubspec.yaml)
```yaml
firebase_core: ^4.14.0
firebase_messaging: ^16.6.0
geolocator: ^14.0.3
health: ^13.3.2
package_info_plus: ^10.2.1
permission_handler: ^13.0.1
share_plus: ^13.3.0
# Keep other deps (provider, shared_preferences, etc.) on ^ latest; let transitive float
```
Keep `sdk: ^3.12.0` (Flutter 3.47 requires Dart 3.13). Verify `health 13.3.2` still supports `health_connect` style used in `health_connect_service.dart`.

### Step 2 — Majors
```bash
flutter pub upgrade --major-versions
# Review pubspec.lock diff; commit lockfile
flutter pub get
flutter analyze
```

### Step 3 — Breaking-change sweep
| Package | Major bump risk | Check |
|---------|-----------------|-------|
| `permission_handler 11→13` | Android 13+ notification permission, `Permission.notification` enum move | `BleProvider` permission flow |
| `share_plus 10→13` | API `Share.share` → `SharePlus.instance.share` | `home_screen.dart` `Share.share` call |
| `package_info_plus 9→10` | `PackageInfo.fromPlatform()` deprecation | `BleProvider` `getPackageInfo` |
| `firebase_core 3→4` | `_flutterfire_internals` 1.3.59→1.3.77, `FirebaseOptions` init | `main.dart` `SupabaseService.initialize` unaffected, but `firebase_core` init no-op |
| `geolocator 13→14` | `Geolocator.checkPermission` return type | `geolocator` only via `qibla_service.dart`? |
| `device_info_plus 12→13` | `deviceInfo.iosInfo` deprecation | `BleProvider` device info |

### Step 4 — Native side
No `android/build.gradle.kts` version changes required for these Dart packages, but `health 13.3.2` bumps `androidx.health:health-connect-client` transitive — test on API 26 device.

### Step 5 — Verification
```bash
flutter pub outdated   # should report 0 stale direct deps
flutter analyze
flutter build appbundle --release
```

### Rollback
If a major breaks ring SDK (`health`/`geolocator`), pin that single dep back to last working `^` and file `docs/bugs-fixes/01-xxx-rollback.md`.

## Ownership
*Direct deps upgraded by design every sprint; transitive float via `pub upgrade`.*
