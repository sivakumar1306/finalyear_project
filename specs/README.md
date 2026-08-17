# SUNDR / Vital Monitoring — Product & Feature Specs

This folder holds **product and feature specifications**: what the system must do, for whom, and under what constraints.

| Doc type | Location | Purpose |
|----------|----------|---------|
| **Specs (this folder)** | `specs/` | Requirements, user flows, acceptance criteria, status |
| **Architecture** | `architecture/`, `Architecture.md` | How it is built (layers, interop, data) |
| **Design system** | `DESIGN.md` | UI colors, glassmorphism, typography, cards |
| **Knowledge transfer** | `KNOWLEDGE_TRANSFER.md` | Screen-by-screen and code map for engineers |
| **Fall status** | `FALL_DETECTION_STATUS.md` | Fall feature shipping status and open work |

## Naming

| Name | Where used |
|------|------------|
| **SUNDR** | User-facing brand (splash, `MaterialApp` title) |
| **sundr** | Flutter package name |
| **com.sundr.myapp** | Android namespace, MethodChannel prefixes |
| **QRing** | Vendor SDK / legacy internal names |

All names refer to the same product.

## Spec index

| # | Document | Covers |
|---|----------|--------|
| 00 | [product-overview.md](./00-product-overview.md) | Vision, personas, platforms, feature map, status |
| 01 | [auth-onboarding.md](./01-auth-onboarding.md) | Splash, sign-up, login, password recovery, profile onboarding |
| 02 | [device-pairing-ble.md](./02-device-pairing-ble.md) | Scan, pair, reconnect, bond lifecycle |
| 03 | [vitals-monitoring.md](./03-vitals-monitoring.md) | Continuous + manual vitals, detail screens, thresholds |
| 04 | [home-dashboard.md](./04-home-dashboard.md) | Main shell, home cards, navigation |
| 05 | [fall-detection-safety.md](./05-fall-detection-safety.md) | Risk score, active fall, alerts, emergency contacts |
| 06 | [workouts.md](./06-workouts.md) | Categories, live session, history |
| 07 | [womens-health.md](./07-womens-health.md) | Cycle calendar, phases, symptoms |
| 08 | [assist-chat.md](./08-assist-chat.md) | AI assistant, history, chat API |
| 09 | [phone-modes-reminders.md](./09-phone-modes-reminders.md) | Focus / Prayer / Base, drink & sedentary reminders |
| 10 | [settings-device.md](./10-settings-device.md) | Device, health, display, OTA, account |
| 11 | [data-sync-storage.md](./11-data-sync-storage.md) | Room, Supabase, offline-first, RLS |
| 12 | [non-functional.md](./12-non-functional.md) | Performance, privacy, permissions, platforms |

## Status legend (used in all specs)

| Status | Meaning |
|--------|---------|
| **Shipped** | Implemented and exercised on device |
| **Partial** | Core path works; gaps, stubs, or unvalidated edges remain |
| **Stub** | UI or scaffolding only; not wired end-to-end |
| **Planned** | Documented intent; not built |

## How to use these docs

1. **Product / PM** — Start with `00-product-overview.md`, then the feature spec for the epic.
2. **Engineering** — Spec for *what*; `architecture/` + `KNOWLEDGE_TRANSFER.md` for *how*.
3. **UI work** — Read `DESIGN.md` before any visual change (`CLAUDE.md` enforces this).
4. **Acceptance** — Each feature spec lists acceptance criteria; mark done only when criteria pass on a real Android + ring where BLE is required.
