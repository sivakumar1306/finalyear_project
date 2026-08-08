# 09 — Phone Modes & Reminders

| Field | Value |
|-------|-------|
| **Status** | Shipped on Android; iOS DND unsupported |
| **Key code** | `AlarmModeProvider`, `PhoneModePlugin.kt`, `PhoneModeNotifier.kt`, reminder screens, prayer screens |

---

## 1. Phone modes (Focus / Prayer / Base)

### Purpose

Automate phone interruption filter (Do Not Disturb) based on a user-selected mode for focus or short prayer sessions.

### Modes

| Mode | Product intent |
|------|----------------|
| **Base** | Normal interruptions (default). |
| **Focus** | DND / reduced interruptions for deep work. |
| **Prayer** | Short DND window; auto-off after ~1 minute (native Handler, not Dart Timer). |

### Requirements

| ID | Requirement |
|----|-------------|
| MODE-01 | User can select mode from Home segment and/or Alarms & Notifications settings. |
| MODE-02 | On Android, mode applies system interruption filter when permission granted. |
| MODE-03 | Prayer auto-off is implemented **natively** so it survives Flutter engine death while process lives. |
| MODE-04 | Today’s mode sessions can be listed for feedback (`getPhoneModeSessionsToday`). |
| MODE-05 | iOS: no public DND API — UI may keep local state only; do not claim system DND. |
| MODE-06 | Sleep reminder scheduling coexists without corrupting SharedPreferences types (string-encoded times for native readers). |

### Prayer feature surfaces

- `prayer_session_screen.dart` — active session UX  
- `prayer_summary_screen.dart` — end summary  
- `prayer_history_screen.dart` — past sessions  
- `prayer_schedule_screen.dart` / prefs — schedule configuration  

---

## 2. Drink reminder

| ID | Requirement |
|----|-------------|
| REM-10 | User enables/disables drink reminder. |
| REM-11 | Configure time window + interval; push to ring via `get/setDrinkReminder`. |
| REM-12 | Settings readable after reconnect. |

Screen: `drink_reminder_screen.dart` (`/drink-reminder`).

---

## 3. Sedentary reminder

| ID | Requirement |
|----|-------------|
| REM-20 | User enables/disables sedentary reminder. |
| REM-21 | Configure window, interval, and step threshold. |
| REM-22 | Persist via `get/setSedentaryReminder` to ring/native. |

Screen: `sedentary_reminder_screen.dart` (`/sedentary-reminder`).

---

## 4. Sleep schedule / reminder

| ID | Requirement |
|----|-------------|
| REM-30 | User can set preferred sleep reminder time. |
| REM-31 | SharedPreferences encoding must remain compatible with native `getInt`/`getString` expectations (do not “fix” types without updating native readers). |
| REM-32 | Sleep reminder notifier can fire as local Android notification when due. |

---

## 5. Acceptance criteria

- [ ] Android: selecting Focus changes interruption filter (with notification policy access).  
- [ ] Prayer mode returns to Base after ~1 minute even if UI is closed.  
- [ ] Drink and sedentary settings round-trip after app restart with ring connected.  
- [ ] iOS does not crash on mode toggle.

---

## 6. Related

- [04-home-dashboard.md](./04-home-dashboard.md)  
- [10-settings-device.md](./10-settings-device.md)  
