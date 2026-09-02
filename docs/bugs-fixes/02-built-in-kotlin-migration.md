# 02 — Built-in Kotlin Migration (App + Plugins)

> Goal: Silence `WARNING: applies the Kotlin Gradle Plugin, which will cause build failures in future versions of Flutter` and align with AGP 9.3.1 + Flutter 3.47 (built-in Kotlin requires ≥3.47).

## Diagnosis
`flutter build appbundle` logs:

```
WARNING: Your app: android/app/build.gradle.kts applies KGP (org.jetbrains.kotlin.android)
WARNING: Plugins that apply KGP: device_info_plus, health, package_info_plus, share_plus, speech_to_text
Future Flutter will fail if plugins apply KGP.
```

Root cause: AGP 9 removed `kotlin-android` plugin application; Flutter embeds Kotlin via `android.builtInKotlin=true`. Current repo:

* `android/gradle.properties` → `android.builtInKotlin=false` + `android.newDsl=false` (legacy, added by Flutter migrator)
* `android/app/build.gradle.kts:6` → `id("org.jetbrains.kotlin.android")` + `id("com.google.devtools.ksp")` while `kotlin { jvmTarget }` already uses new DSL (`2.4.10`) — duplicate.

## Plan — App (you control)

### A. `android/gradle.properties`
```properties
# Before
android.builtInKotlin=false
android.newDsl=false
# After (Flutter ≥3.47)
android.builtInKotlin=true
android.newDsl=false   # keep until all plugins migrated; flip after 02-verify
```
Per https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers#verify-flags-in-the-gradle-properties-file — `builtInKotlin=true` requires Flutter 3.47+, which we have (3.47.2).

### B. `android/app/build.gradle.kts`
```kotlin
// Before
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")   // ← REMOVE
    id("com.google.devtools.ksp")
    id("dev.flutter.flutter-gradle-plugin")
}
// After
plugins {
    id("com.android.application")
    id("com.google.devtools.ksp")        // KSP stays (Room)
    id("dev.flutter.flutter-gradle-plugin")
}
// Keep:
kotlin {
    compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
}
```

### C. `android/build.gradle.kts` + `android/settings.gradle.kts`
Remove `id("org.jetbrains.kotlin.android") version "2.4.10" apply false` from both `plugins {}` blocks — built-in Kotlin supplies it. Keep `id("com.google.devtools.ksp") version "2.3.11" apply false` for Room.

### D. Validate
```bash
flutter clean
flutter build appbundle --release
# Expect: single warning for plugins still on KGP (until 02-plugin-upgrade), no app warning
```

## Plan — Plugins (you don’t control, but can influence)

| Plugin | Current | Latest (pub outdated) | Built-in Kotlin? | Action |
|--------|---------|-----------------------|------------------|--------|
| `device_info_plus` | 12.4.0 | 13.2.0 | Likely yes in 13.x (check CHANGELOG) | Upgrade via 01, re-build, confirm warning disappears |
| `package_info_plus` | 9.0.1 | 10.2.1 | Yes in 10.x | Upgrade |
| `share_plus` | 10.1.4 | 13.3.0 | Yes in 13.x | Upgrade (also fixes `Share` API) |
| `health` | 13.3.1 | 13.3.2 | Check; if still KGP, file issue | Upgrade to 13.3.2, check warning persists |
| `speech_to_text` | 7.0.0 | latest 7.x | Unknown | Check `pub.dev/changelog`; if still KGP, file issue |

If latest still applies KGP, follow https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers#report-incompatible-kotlin-gradle-plugin-usage-to-plugin-authors template and pin or fork until upstream migrates. Our CI will keep `android.builtInKotlin=false` fallback until all 5 are clean, then flip to `true`.

## Verification Matrix
* `flutter build appbundle --release` → no `app` KGP warning (pass)
* `flutter build appbundle` still warns for remaining plugins → track in `docs/bugs-fixes/02-plugin-tracker.md` until 0
* `android/app/build.gradle.kts` no longer contains `org.jetbrains.kotlin.android`

## References
* https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin
* https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers
* Flutter issue #181383, #183910
