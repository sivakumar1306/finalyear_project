# Vital Monitoring — Explainable Fall-Risk Prediction from Smart-Ring Data

Final-year project (VIT Chennai). A Flutter + native Android app for a QRing-class BLE smart
ring with three parts:

1. **Home** — live vitals cards (heart rate, SpO₂, HRV, stress, blood pressure, temperature,
   sleep, and women's health for female users). Each card opens a detail screen with charts.
2. **AI Assist** — chat over your own ring data, backed by the FastAPI + LangGraph agent in
   [`vtial_ring_backend_version1`](https://github.com/sivakumar1306/vtial_ring_backend_version1)
   (`AppConfig.chatApiBaseUrl` in `lib/config.dart`).
3. **Fall Prediction** — the four-layer explainable fall-risk engine (physiology, recovery,
   motion, women's health) with adaptive weights, a red-flag override, and an
   explainable-AI breakdown of the score.

Login/sign-up, onboarding and ring pairing are kept as supporting flows. The UI follows
`DESIGN.md`.

## Repo layout

| Path | Contents |
|---|---|
| `lib/screens/home/` | Home dashboard and vitals cards |
| `lib/screens/health/` | Vital detail screens opened from the cards |
| `lib/screens/assist/` | AI Assist chat and its vital chat cards |
| `lib/screens/fall_prediction/` | Fall Prediction tab |
| `lib/services/fall_prediction/` | Fall-risk engine (layers 1–4, adaptive weights, red-flag override) |
| `lib/providers/` | `BleProvider` (ring data), `FallPredictionProvider`, `MainTabProvider` |
| `android/` | Native host: `BlePlugin.kt` bridge, Room DB, foreground service, on-device fall analysis (package `com.sundr.myapp`) |
| `specs/`, `eval/` | Feature specifications and evaluation notes |
| `supabase/` | Backend schema/migrations |

## Quick start

```sh
flutter pub get
flutter run          # requires a real BLE-capable Android device for ring features
```

- The vendor BLE SDK is checked in under `android/app/libs/` — the build needs it.
- Release builds use `key.properties` when present, otherwise debug signing.

## Verification

```sh
flutter analyze --no-fatal-infos
flutter test
flutter build apk --release --target-platform android-arm64
```

CI runs analyze + tests and builds an installable arm64 APK (artifact `vital-monitoring-apk`).
