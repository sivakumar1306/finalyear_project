# 10 — Settings, Device Controls & Account

| Field | Value |
|-------|-------|
| **Status** | Partial (core shipped; some stubs) |
| **Key code** | `lib/screens/settings/*`, OTA, FAQ, legal screens |

---

## 1. Purpose

Central place for device configuration, health intervals, account management, safety features, and support content.

---

## 2. Settings hub

`settings_screen.dart` — ring info card + navigation list into sub-screens.

Must surface connection/battery summary consistent with `BleProvider`.

---

## 3. Device & ring settings

| Screen / route | Requirements | Status |
|----------------|--------------|--------|
| Device settings index | Navigation only | Shipped |
| Display settings | Brightness, screen-on duration, clock style, 24h, wrist orientation | Shipped |
| Advanced settings | Battery saving, AGPS, touch, intelligent settings, prayer reminder flags | Shipped |
| Touch control | Enable sensor; live gesture log; client double-tap synthesis (~400ms) | Shipped |
| Gesture settings | Configure ring gestures | Shipped |
| Find device | Trigger ring find/alert if SDK supports | Shipped / SDK-dependent |
| Ring camera | Camera shutter integration via ring events | Shipped / partial |
| Target profile | Daily steps/calories/sleep/distance targets + body profile to ring | Shipped |
| Health settings | Per-vital monitor toggle + intervals | Shipped |
| Notification settings | ANCS, DND window, per-app, music control | Shipped |
| Select notifications | Alert-type picker, persisted (`NotificationPrefs`) and honored by live phone alerts | Partial (ring-side persist open) |
| Drink / sedentary | See [09](./09-phone-modes-reminders.md) | Shipped |
| OTA | Pick `.bin`, confirm, progress bar via events | Shipped |
| Fall detection | See [05](./05-fall-detection-safety.md) | Partial |
| Health Connect | Android Health Connect bridge (`health` package): 8 types read/write (steps, HR, HRV, SpO2, sleep, BP, temperature, menstruation) | Partial (enabled-subset auth; verify Android 14+ UX on device) |
| Measurement log | Per-vital History entry + flag-gated settings entry (`AppConfig.includeMeasurementLog`) | Shipped |
| Sugar & lipids | Ring monitor-state reads + channel toggles (`get/setHealthSettings`) | Shipped (continuous-glucose BLE itself is a `"[]"` stub) |
| Background protection | OEM battery whitelist guidance | Shipped / OEM-specific |
| Card settings | Home card layout prefs | Shipped |
| Goal setting | Goals prefs | Shipped |
| Alarms & notifications | Modes + sleep reminder + session history | Shipped |
| Prayer schedule | Schedule prefs | Shipped |

### OTA requirements

| ID | Requirement |
|----|-------------|
| SET-10 | User selects firmware `.bin` via file picker. |
| SET-11 | Confirm destructive/time-consuming update before start. |
| SET-12 | Show live progress from native DFU state machine. |
| SET-13 | Cloud catalog table `firmware_updates` (version, URL, notes, mandatory flag) drives the in-app releases list; auto-update prompts remain future. |

---

## 4. Account & profile

| Screen | Requirements | Status |
|--------|--------------|--------|
| Account & system | Profile nav, logout, factory reset, delete account | Partial (some placeholders historically) |
| Profile edit | Edit name/gender/age/height/weight → Supabase upsert | Shipped |
| Privacy policy | Static legal content | Shipped |
| Terms of service | Static legal content | Shipped |
| FAQ | Support content | Shipped |
| About | Version / branding | Shipped |

| ID | Requirement |
|----|-------------|
| SET-20 | Logout clears session and native login/sync flags. |
| SET-21 | Delete account calls server RPC and returns user to auth. |
| SET-22 | Factory reset of ring (if exposed) must confirm and only when connected. |

---

## 5. Stub / incomplete (explicit, verified 2026-09-19)

| Feature | Expected completion |
|---------|---------------------|
| Select notifications → ring | Persist choices on-ring and honor in ring alert pipeline (phone pipeline already honors them) |
| Continuous-sugar / ECG BLE | Real SDK calls (`getContinuousSugar` returns `"[]"` stub, `startEcgMeasure` returns `"{}"` stub) |
| Sport type detail depth | Parse ring per-type trace fields beyond current stub screen |
| Records index | No such screen exists — remove from scope or spec it as new work |

---

## 6. Acceptance criteria

- [ ] Health settings toggle disables a vital in the loop (observable after reconnect/cycle).  
- [ ] Display setting change reflects on ring UI.  
- [ ] OTA progress advances during a test firmware transfer on supported hardware.  
- [ ] Profile edit updates Home greeting/name.  
- [ ] Logout requires re-authentication to access Home data.  

---

## 7. Related

- [02-device-pairing-ble.md](./02-device-pairing-ble.md)  
- [01-auth-onboarding.md](./01-auth-onboarding.md)  
