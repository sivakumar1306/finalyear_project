# 04 — Verification Checklist (After 01 + 02)

Run in order after upgrades.

```bash
# 1. Dependencies clean?
flutter pub outdated          # expect 0 direct stale
flutter pub get

# 2. Static analysis?
flutter analyze               # expect 0 errors (2 info curly_braces in sleep_screen is ok)

# 3. Built-in Kotlin app warning gone?
flutter build appbundle --release 2>&1 | Select-String "Your Android app project"
# expect no line for `app` (only plugin list remains until 03 is green)

# 4. Full build?
flutter build appbundle --release   # 60-90s, expect √ Built

# 5. Runtime smoke
flutter run -d android  # check Health Connect, permission_handler 13, share_plus 13, package_info_plus 10 still work
```

If `flutter build` fails with `KSP version 2.3.11 does not match Kotlin 2.4.10`, update `android/build.gradle.kts` KSP to `2.3.10` or `2.3.11` paired with Kotlin `2.4.10` per https://kotlinlang.org/docs/ksp overview (KSP 2.3.x line supports Kotlin 2.4).

Commit: `pubspec.yaml`, `pubspec.lock`, `android/app/build.gradle.kts`, `android/gradle.properties`, `android/build.gradle.kts`, `android/settings.gradle.kts`, `docs/bugs-fixes/*.md`.
