# 12 — Non-Functional Requirements

| Field | Value |
|-------|-------|
| **Status** | Mixed — requirements for release readiness |

---

## 1. Platforms

| ID | Requirement |
|----|-------------|
| NFR-01 | **Primary:** Android phone, `minSdk 26`, target/compile per project Gradle (`targetSdk` 35 / `compileSdk` 36 as configured). |
| NFR-02 | Real BLE features require physical device with Bluetooth. |
| NFR-03 | iOS/desktop folders may exist for Flutter tooling; **not** release targets for ring features unless explicitly staffed. |
| NFR-04 | Kotlin/Java 17 toolchain for Android module. |

---

## 2. Performance & battery

| ID | Requirement |
|----|-------------|
| NFR-10 | Foreground services must show ongoing notifications meeting Android policy. |
| NFR-11 | Measurement loop interval must balance data density vs ring battery; production default should not remain at aggressive test cooldown without sign-off. |
| NFR-12 | Continuous phone accel for fall detection: measure multi-hour battery delta vs baseline before marketing “always on safety”. |
| NFR-13 | UI should remain responsive during manual measurements (loading states; timeouts 8–90s by vital). |
| NFR-14 | Home and detail screens should render last-known data instantly from memory/Room without waiting for network. |

---

## 3. Reliability

| ID | Requirement |
|----|-------------|
| NFR-20 | BLE reconnect after transient disconnect without user re-pairing when bonded. |
| NFR-21 | BootReceiver restores monitoring path after reboot when user still logged in. |
| NFR-22 | Native SDK calls always race a timeout so Flutter Futures cannot hang forever. |
| NFR-23 | Workout and measurement coordinator prevent concurrent SDK ownership bugs. |
| NFR-24 | Incident reporting (`app_incidents` / `IncidentService`) captures uncaught Flutter/native errors when possible. |

---

## 4. Security & privacy

| ID | Requirement |
|----|-------------|
| NFR-30 | Health data treated as sensitive; RLS on all user tables. |
| NFR-31 | No service-role keys in the mobile binary. |
| NFR-32 | Transport HTTPS for Supabase and chat API. |
| NFR-33 | Account deletion and logout paths implemented before public store release. |
| NFR-34 | Privacy Policy and Terms screens accessible from settings. |
| NFR-35 | Fall prediction/alert copy must not present the app as a certified medical device unless certified. |

---

## 5. Permissions (Android)

Request and justify:

- Bluetooth scan/connect (and legacy location if required by OS version)  
- Notifications  
- Activity recognition / sensors (fall motion)  
- SMS / phone **only if** emergency auto-contact is enabled in a future release  
- Camera (ring camera feature)  
- Microphone (voice assist)  
- Exact alarms / DND policy access (modes & reminders)  
- Health Connect permissions when that bridge is used  

| ID | Requirement |
|----|-------------|
| NFR-40 | Deny paths must degrade gracefully (feature off, not crash). |
| NFR-41 | Background protection guidance for OEMs that kill services. |

---

## 6. Accessibility & UX quality

| ID | Requirement |
|----|-------------|
| NFR-50 | Permanent dark theme only; contrast sufficient for primary metrics (white ~0.95 on `#050505`). |
| NFR-51 | Follow `DESIGN.md` for any UI change.  
| NFR-52 | Critical actions (delete account, OTA, end workout) use confirmation dialogs. |

---

## 7. Internationalization

| ID | Requirement |
|----|-------------|
| NFR-60 | Initial release may be single-language (English) unless product expands. |
| NFR-61 | Units: support metric profile data (cm/kg); unit prefs service exists for future expansion. |

---

## 8. Testing & release

| ID | Requirement |
|----|-------------|
| NFR-70 | Automated tests currently minimal; before release add unit tests for fall polarity, adaptive weight Σ=1, and BP/status classifiers. |
| NFR-71 | Manual test matrix: pair, loop vitals, manual measure, workout, fall simulate, offline today, sync after reconnect. |
| NFR-72 | Release builds must use a production signing keystore (not debug). |
| NFR-73 | R8/Proguard keep rules for Room/Gson models remain valid. |
| NFR-74 | Vendor AAR present in `android/app/libs/` for all CI builds. |
| NFR-75 | CI/release workflow under `.github/workflows/` if used must build signed artifact. |

---

## 9. Observability

| ID | Requirement |
|----|-------------|
| NFR-80 | Fall risk and fall events logged for offline analysis. |
| NFR-81 | App incidents table for crash triage. |
| NFR-82 | Avoid logging full PII (tokens, precise address books) to incidents. |

---

## 10. Compliance posture (product statements)

Until regulatory clearance:

- Market as a **wellness / lifestyle** companion with safety *assistance*, not diagnostic equipment.  
- Fall features are **aids**, not substitutes for medical care or dedicated PERS devices.  

---

## 11. Related

- `DESIGN.md`  
- `FALL_DETECTION_STATUS.md`  
- [00-product-overview.md](./00-product-overview.md)  
