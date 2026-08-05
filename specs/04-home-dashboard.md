# 04 — Home Dashboard & Main Shell

| Field | Value |
|-------|-------|
| **Status** | Shipped |
| **Key code** | `lib/screens/main_shell.dart`, `lib/screens/home/*`, `lib/providers/main_tab_provider.dart`, `home_card_provider.dart` |

---

## 1. Purpose

Provide the primary daily health overview after login: connection status, key vitals at a glance, modes, and navigation into detail features.

---

## 2. Main shell

| ID | Requirement |
|----|-------------|
| HOME-01 | Post-login shell has **three tabs**: Home, Assist, Settings (`IndexedStack` + custom bottom nav). |
| HOME-02 | Bottom nav follows design system (blur / dark / gold active state). |
| HOME-03 | **Workout lock:** if a workout is active, switching tabs is blocked; user is guided back to `ActiveWorkoutScreen`. |
| HOME-04 | On restart with in-progress workout (SharedPreferences), shell restores into active workout after provider init. |

---

## 3. Home screen content

### 3.1 Header / device

| ID | Requirement |
|----|-------------|
| HOME-10 | Show user greeting / name from profile when available. |
| HOME-11 | Device pill shows connection state; tap opens ring scan sheet. |
| HOME-12 | Battery level when connected, if provided by SDK/events. |

### 3.2 Metric cards

Home surfaces summary cards for (configurable via card settings where implemented):

- Steps / activity score  
- Heart rate  
- SpO₂  
- Stress  
- HRV  
- Blood pressure  
- Sleep  
- Women’s health (gender-gated)  
- Fall prediction banner (when predictive alert active)  

| ID | Requirement |
|----|-------------|
| HOME-20 | Tapping a metric card navigates to its detail route. |
| HOME-21 | Status badges/colors align with detail-screen classifiers. |
| HOME-22 | Pull-to-refresh reloads provider/native summaries. |
| HOME-23 | Card visibility/order can be customized (`HomeCardProvider` / card settings) where feature is enabled. |

### 3.3 Alarm / phone mode segment

| ID | Requirement |
|----|-------------|
| HOME-30 | Segmented control for **Focus / Base / Prayer** modes on Home. |
| HOME-31 | Mode changes drive DND automation on Android (see [09](./09-phone-modes-reminders.md)). |

### 3.4 Fall prediction banner

| ID | Requirement |
|----|-------------|
| HOME-40 | When a predictive fall notification was opened or flag is set, Home shows a banner with take-action / dismiss. |
| HOME-41 | Support both cold start (`consumeFallPredictionFlag`) and warm resume (lifecycle) deep-link paths. |

---

## 4. Side panel & secondary home UI

- Side panel (if present) for quick navigation / shortcuts.  
- Ring scan sheet: primary pair path (see [02](./02-device-pairing-ble.md)).  
- Card settings screen for layout preferences.

---

## 5. Design requirements

| ID | Requirement |
|----|-------------|
| HOME-50 | Permanent dark theme; background `#050505`; accent gold `#C9A86E`. |
| HOME-51 | Prefer existing glass cards / shared widgets (`GlassCard`, `DataCard`, `StatCard`, etc.). |
| HOME-52 | Metrics identifiable within ~1 second (information-first). |

---

## 6. Acceptance criteria

- [ ] Logged-in user lands on shell with Home selected.
- [ ] Cards show live or last-known values from `BleProvider`.
- [ ] Tap HR card opens heart rate detail.
- [ ] Active workout blocks tab switch.
- [ ] Scan sheet opens from device pill and can connect a ring.
- [ ] Fall banner appears when prediction flag is consumed.

---

## 7. Related

- [03-vitals-monitoring.md](./03-vitals-monitoring.md)  
- [05-fall-detection-safety.md](./05-fall-detection-safety.md)  
- `DESIGN.md`  
