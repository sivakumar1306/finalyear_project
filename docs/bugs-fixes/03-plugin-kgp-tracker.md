# 03 — Plugin KGP Tracker (Built-in Kotlin Readiness)

> Live tracker for the 5 plugins that `flutter build` reports as `applies KGP`. Update after every `flutter pub upgrade`.

| Plugin | pubspec current | pub outdated latest | Upgraded? | Still warns `applies KGP`? | Changelog says Built-in Kotlin? | Issue filed |
|--------|-----------------|---------------------|-----------|----------------------------|----------------------------------|-------------|
| `device_info_plus` | 12.4.0 → **13.2.0** | 13.2.0 | ✅ 2026-09-02 | **No** ✅ | Yes (13.x) | — |
| `health` | 13.3.1 → **13.3.2** | 13.3.2 | ✅ 2026-09-02 | **Yes** ❌ | No — still `kotlin-android` (build fails if `builtInKotlin=true`) | ☐ |
| `package_info_plus` | 9.0.1 → **10.2.1** | 10.2.1 | ✅ 2026-09-02 | **No** ✅ | Yes (10.x) | — |
| `share_plus` | 10.1.4 → **13.3.0** | 13.3.0 | ✅ 2026-09-02 | **No** ✅ | Yes (13.x) | — |
| `speech_to_text` | 7.0.0 | 7.0.0 | ✅ checked | **Yes** ❌ | Check https://pub.dev/packages/speech_to_text/changelog | ☐ |
| `firebase_core` | 3.15.2 → **4.14.0** | 4.14.0 | ✅ 2026-09-02 | **Yes** ❌ (new) | No | ☐ |
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

