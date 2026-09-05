# 03 — Plugin KGP Tracker (Built-in Kotlin Readiness)

> Live tracker for plugins `flutter build` reports as `applies KGP`. Update after every `flutter pub upgrade`. Branch `chore/health-connector-migration` 2026-09-02.

| Plugin | pubspec current | pub outdated latest | Upgraded? | Still warns `applies KGP`? | Changelog says Built-in Kotlin? | Issue filed |
|--------|-----------------|---------------------|-----------|----------------------------|----------------------------------|-------------|
| `device_info_plus` | 12.4.0 → **13.2.0** | 13.2.0 | ✅ 2026-09-02 | **No** ✅ | Yes (13.x) | — |
| `health` | 13.3.1 → **13.3.2** → **REMOVED** | 13.3.2 | ✅ removed on branch | **N/A** — replaced by `health_connector` | No — still `kotlin-android` (blocked `builtInKotlin=true`) | — |
| `health_connector` | — → **3.10.0** | 3.10.0 | ✅ 2026-09-02 | **No** ✅ | Yes — `Support built-in Kotlin` `health_connector_hc_android` | — |
| `package_info_plus` | 9.0.1 → **10.2.1** | 10.2.1 | ✅ 2026-09-02 | **No** ✅ | Yes (10.x) | — |
| `share_plus` | 10.1.4 → **13.3.0** | 13.3.0 | ✅ 2026-09-02 | **No** ✅ | Yes (13.x) | — |
| `speech_to_text` | 7.0.0 → **7.4.0** (`^7.1.0` → 7.4.0 resolved) | 7.4.0 | ✅ 2026-09-02 | **Yes** ❌ | No — `android/build.gradle:12 kotlin-android` still, `compileSdk` missing for AGP 9 | ☐ needs issue |
| `firebase_core` | 3.15.2 → **4.14.0** | 4.14.0 | ✅ 2026-09-02 | **Yes** ❌ | Changelog says `migrate native to Kotlin` but `firebase_core_platform_interface` still KGP? `flutter build` still lists `firebase_core` | ☐ investigate transitive |
| `geolocator` | 13.0.4 → **14.0.3** | 14.0.3 | ✅ 2026-09-02 | **No** ✅ | Yes | — |
| `permission_handler` | 11.4.0 → **13.0.1** | 13.0.1 | ✅ 2026-09-02 | **No** ✅ | Yes | — |

### How to check
```bash
flutter pub upgrade --major-versions  # per 01
flutter build appbundle --release 2>&1 | Select-String "applies the Kotlin Gradle Plugin"
```
If a plugin still warns after being on `latest`, open an issue using Flutter’s template:

```
Title: Migrate plugin to built-in Kotlin
Body: I am using <plugin> … AGP 9 removed KGP … https://github.com/flutter/flutter/issues/181383 … please use built-in Kotlin per https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors
```

### Decision
Keep `android.builtInKotlin=false` until tracker is all “No” (0 warnings). Then flip to `true` per `02-built-in-kotlin-migration.md`.

