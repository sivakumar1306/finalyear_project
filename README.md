# SUNDR — Smart Ring Health Companion

A Flutter + native Android health-monitoring app for the QRing-class BLE smart ring. Continuous
vitals tracking (heart rate, SpO2, blood pressure, stress, HRV, sleep, temperature, steps),
women's-health cycle prediction, fall prediction with emergency SMS/call escalation, workout
tracking, reminders, and a glassmorphic dark UI per `DESIGN.md`.

## Repo layout

| Path | Contents |
|---|---|
| `lib/` | Flutter app: `screens/` (home, health, settings, onboarding, …), `providers/` (BleProvider, WorkoutProvider, …), `services/` (BleService, SupabaseService, …), `widgets/` (shared cards, charts, typography), `models/`, `theme/` |
| `lib/_deprecated/` | Dead code kept for reference; not imported anywhere |
| `android/` | Native host: `BlePlugin.kt` Method/EventChannel bridge, Room DB, foreground services, fall-risk analysis (package `com.sundr.myapp`) |
| `ios/`, `linux/`, `macos/` | Scaffolding only — Android is the active target |
| `architecture/`, `specs/` | Architecture docs and feature specifications |
| `docs/archive/` | Historical evaluation artifacts (dated snapshots, may reference old names) |
| `supabase/` | Backend schema/migrations |

## Quick start

```sh
flutter pub get
flutter run          # requires a real BLE-capable Android device for ring features
```

- The vendor BLE SDK is checked in at `android/app/libs/qring_sdk_1.0.0.50.aar` — the build needs it.
- Release builds use `key.properties` (see `android/app/build.gradle.kts` and `key.properties.example`).

## Verification

```sh
flutter analyze --no-fatal-infos
flutter test
flutter build apk --debug
```

## Docs

- `CLAUDE.md` / `DESIGN.md` — design system rules (read before touching UI)
- `KNOWLEDGE_TRANSFER.md` — the full codebase orientation document
- `Architecture.md` + `architecture/` — system architecture
- `specs/` — feature specifications
- `FALL_DETECTION_STATUS.md` — fall-prediction pipeline status