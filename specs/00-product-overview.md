# 00 — Product Overview

| Field | Value |
|-------|-------|
| **Product name** | SUNDR (package: `qring_flutter`) |
| **Category** | Smart-ring companion / luxury health monitoring |
| **Primary platform** | Android (BLE + foreground services) |
| **Backend** | Supabase (Auth + Postgres); separate REST chat API |
| **Hardware** | QRing-class BLE smart ring via vendor AAR (`qring_sdk_*.aar`) |
| **Status** | Pre-release / active development |

---

## 1. Vision

SUNDR is a premium companion app for a smart ring. It continuously monitors vitals, surfaces calm scientific insights, and differentiates on **safety**: cardiovascular / syncope-oriented fall *risk* prediction plus phone-motion *active* fall detection with local alerts.

Visual and product positioning (from `DESIGN.md`): closer to **Whoop / Oura / Apple Health** than a flashy fitness tracker — premium, minimal, dark, trustworthy.

---

## 2. Goals

### Primary

1. Pair and keep a reliable BLE connection to the ring in the background.
2. Collect and display core vitals (HR, SpO2, BP, stress, HRV, steps, sleep, temperature) with offline-first “today” data.
3. Persist durable history in Supabase for trends and cross-session continuity.
4. Provide fall risk scoring and corroborated fall detection with local user alerts.
5. Support workouts, women’s health (when applicable), phone Focus/Prayer modes, and an AI health assistant.

### Non-goals (current release)

- Medical device certification or clinical diagnosis claims.
- Mechanical trip-and-fall prediction from ring IMU (SDK does not expose continuous accel/gyro).
- Caregiver cloud push and auto-dial emergency (deferred; see fall spec).
- Full iOS parity for BLE background measurement and DND automation.
- Light mode UI.

---

## 3. Personas

| Persona | Needs |
|---------|--------|
| **Everyday wearer** | Pair ring once, see today’s vitals and sleep, set goals, work out. |
| **At-risk adult / caregiver-aware user** | Fall risk awareness, emergency contacts, “I’m okay” dismiss path. |
| **Wellness-focused user** | Cycle tracking, stress/HRV trends, AI assist Q&A. |
| **Power user** | Health intervals, display/touch settings, OTA firmware, Health Connect. |

---

## 4. Platforms & stack (summary)

| Layer | Tech |
|-------|------|
| UI | Flutter, Provider, permanent dark theme |
| Native critical path | Kotlin foreground service, Room DB, vendor BLE SDK |
| Cloud | Supabase Auth + Postgres (RLS) |
| Chat | External REST API (`CHAT_API_BASE_URL`) |
| Design | `DESIGN.md` glassmorphism + gold accent `#C9A86E` |

See `architecture/Overview.md` for diagrams.

---

## 5. Feature map

| Domain | Spec | Status |
|--------|------|--------|
| Auth & onboarding | [01](./01-auth-onboarding.md) | Shipped |
| Device pairing & BLE | [02](./02-device-pairing-ble.md) | Shipped |
| Vitals monitoring | [03](./03-vitals-monitoring.md) | Shipped (temp partial) |
| Home & shell | [04](./04-home-dashboard.md) | Shipped |
| Fall detection & safety | [05](./05-fall-detection-safety.md) | Partial (live but unvalidated prediction) |
| Workouts | [06](./06-workouts.md) | Shipped |
| Women’s health | [07](./07-womens-health.md) | Shipped |
| AI Assist | [08](./08-assist-chat.md) | Partial (backend dependency) |
| Phone modes & reminders | [09](./09-phone-modes-reminders.md) | Shipped (Android) |
| Settings & device | [10](./10-settings-device.md) | Partial (some stubs) |
| Data & sync | [11](./11-data-sync-storage.md) | Shipped |
| Non-functional | [12](./12-non-functional.md) | Mixed |

### Known stub / incomplete surfaces

- Sugar & lipids detail (placeholder UI).
- Sport record raw dump (minimal parsing).
- Records index (hardcoded subtitles).
- Select notifications (local state only).
- Caregiver push, auto-dial, full-screen fall overlay (planned).
- Release signing keystore (debug signing used for release builds today).

---

## 6. Information architecture

```
Splash
 ├─ Auth (login / sign-up / recovery)
 ├─ Onboarding (name → age → gender → height → weight → [emergency] → pair ring optional)
 └─ MainShell (3 tabs)
      ├─ Home (dashboard, scan sheet, mode selector, fall banner)
      ├─ Assist (chat + history)
      └─ Settings (device, health, account, fall detection, …)
```

Named routes are defined in `lib/app.dart`. Deep feature screens use routes; flow screens (auth steps, chat, active workout) often use `Navigator.push`.

---

## 7. Core design principles (product)

1. **Offline-first for “today”** — Local Room is source of truth for continuous readings; cloud is history and multi-day trends.
2. **Hardware-native for reliability** — BLE loop, fall analysis, and background sync run in Kotlin, not only Dart.
3. **Safety over hype** — Fall *prediction* is scoped to syncope/cardiovascular signals, not general mechanical falls.
4. **Information first** — Metrics readable within ~1 second; UI effects support data (`DESIGN.md`).
5. **User control on emergencies** — Local alert with dismiss; auto-call is not current scope.

---

## 8. Success metrics (product-level)

| Metric | Intent |
|--------|--------|
| Pair success rate | Users complete first ring bind without support |
| Background uptime | Foreground service reconnects after kill/reboot |
| Sync lag | Background readings appear in cloud within one sync cycle |
| Fall motion FP rate | Low false positives after g-unit threshold fix (measure on-device) |
| Fall prediction validity | Correlate logged scores vs real near-falls (open research task) |
| Crash / incident volume | `app_incidents` table + client reporting |

---

## 9. Related docs

- `architecture/Overview.md` — system diagram  
- `DESIGN.md` — visual system  
- `FALL_DETECTION_STATUS.md` — fall shipping status  
- `KNOWLEDGE_TRANSFER.md` — engineer onboarding  
