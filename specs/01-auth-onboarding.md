# 01 — Authentication & Onboarding

| Field | Value |
|-------|-------|
| **Status** | Shipped |
| **Primary platform** | All Flutter targets (Supabase Auth); BLE pair step is Android-first |
| **Key code** | `lib/screens/auth/*`, `lib/screens/onboarding/*`, `lib/services/supabase_service.dart` |
| **Status legend** | See `specs/README.md`: Shipped / Partial / Stub / Planned |

---

## 1. Purpose

Establish identity, collect a minimal health profile, optionally pair a ring, then enter the main app. Profile completeness gates Home; RLS gates every row; logout/deletion must fully revoke access and data.

---

## 2. User flows

### 2.1 Cold start (splash)

1. App launches → `SplashScreen` (`/`).
2. Short brand delay (~600ms).
3. Branch:
   - **No session** → Get-started / login entry (SUNDR branding).
   - **Session + complete profile** (`full_name` non-empty) → `/home`.
   - **Session + incomplete profile** → onboarding name step.

### 2.2 Sign up

1. User enters email, password, confirm password.
2. Client validation:
   - All fields required.
   - Password length ≥ 6.
   - Password matches confirm.
3. `SupabaseService.signUp` creates account.
4. Always route into **onboarding** (new profiles are incomplete).

### 2.3 Log in

1. Email + password → `SupabaseService.signIn`.
2. Load profile:
   - Named profile → `/home`.
   - Incomplete → onboarding.
3. Auth errors shown inline (cleaned `Exception:` prefix).
4. On every auth state change, push sync credentials (URL, anon key, user id, access token) + `user_logged_in` to native via `configureSync` so background reconnect matches the signed-in user.

### 2.4 Password recovery

| Screen | Behavior |
|--------|----------|
| Forgot password | Request recovery email / code path via Supabase |
| Recovery code | Enter code from email |
| Reset password | Set new password |

*(Screens: `forgot_password_screen.dart`, `recovery_code_screen.dart`, `reset_password_screen.dart`.)*

### 2.5 Onboarding (profile)

Shared chrome: `onboarding_shell.dart` — step dots, SKIP, Continue, `GlassCard` tokens (blur 28 / radius 20 / padding 16, `AppTheme.kPad`/`kRadiusCard`, gold `#C9A86E`), SafeArea on every step (eval 3.5 VERIFIED pattern).

| Step | Screen | Data | UI |
|------|--------|------|-----|
| 1 | Name | First / full name | Text field |
| 2 | Age | 1–100 | Wheel picker |
| 3 | Gender | String (card grid) | 2×2 cards |
| 4 | Height | 100–250 cm | `RulerPicker` |
| 5 | Weight | 20–250 kg | `RulerPicker` |
| 6 | Emergency contact | Optional name + phone | Form (if present in flow) |
| 7 | Pair ring | Action only | Pair now / later |

**Persistence rule:** Collect into `OnboardingData` in memory; **upsert profile once at the end** of the pair-ring step (or skip path), not on every intermediate Continue.

After save:

- **Pair my ring** → `/home` then push `/device-bind`.
- **I'll do this later / SKIP** → `/home` only.

> Emergency-contact safety (eval CRIT-2, integrated): NEVER auto-seed fake contacts (`9999999999`, `+91 000 000 0000` — previously in `fall_detection_screen.dart:107-114`, `profile_edit_screen.dart:89-93`). Empty list stays empty; the real SMS/call path (`EmergencySmsSender`, `EmergencyAutoCaller`) must have no dialable placeholder. Linking a contact to a SUNDR user (friend-request: offer → accept → linked, `caregiver_links`/`caregiver_link_requests`) is future work — today a contact is name + phone only.

### 2.6 Log out

Settings → Account → confirm → `SupabaseService.signOut` → route `/`.
Native `user_logged_in` flag and `configureSync` must clear / reconfigure so background reconnect does not run for a logged-out user. `clearPersonalData` is thorough (eval-confirmed good): stops loops, drops Room `qring_local.db`, clears native prefs, cancels notifications.

### 2.7 Account deletion

Supabase RPC `delete_user_account()` (SECURITY DEFINER, `auth.uid()` only) removes user-owned rows and `auth.users`.
UI entry lives under account settings; must only call while authenticated. Must also wipe new alert data (`emergency_alerts`, `emergency_alert_deliveries`, `caregiver_*`, `user_push_tokens`).

---

## 3. Functional requirements

| ID | Requirement (integrated) |
|----|--------------------------|
| AUTH-01 | Support email/password sign-up and sign-in via Supabase Auth. |
| AUTH-02 | Persist session via `supabase_flutter`; restore on next launch. |
| AUTH-03 | On every auth state change, update native sync config (URL, anon key, user id, access token) and `user_logged_in`. |
| AUTH-04 | Incomplete profiles cannot skip past onboarding permanently without filling name (routing gate on splash/login). |
| AUTH-05 | Password minimum 6 characters client-side; server is source of truth. |
| AUTH-06 | Onboarding profile fields stored in `user_profiles` (single squashed `supabase/migrations/00000000000000_init.sql`, 34 tables) with RLS owner access (`auth.uid() = user_id`). Hardcoded Supabase URL + anon key in `lib/config.dart` is publishable by design — RLS is the gate; never ship service-role key. |
| AUTH-07 | Ring pairing is optional at onboarding; user can bind later from Home or Settings. |
| AUTH-08 | User can log out and delete account; delete removes cloud personal data per migration (`delete_user_account()`). Logout runs full `clearPersonalData`. |
| AUTH-09 | Gender collected at onboarding gates the women’s-health card and AWHE pipeline (`CycleEngine.phaseName(day,cycleLen,periodLen)`: ≤pLen menstruation, ≤13 follicular, ≤16 ovulating, else luteal). No cycle prediction without gender + cycle history + sensor availability. |
| AUTH-10 | Auth/onboarding UI follows `DESIGN.md` card system (`rgba(255,255,255,0.06)`, `0.5px rgba(255,255,255,0.09)`, blur 28, radius 20 via `AppTheme.kRadiusCard`, padding 16 via `AppTheme.kPad`, gold `#C9A86E` only accent, `AppTheme.card 0xFF111111`/`card2 0xFF1A1A1A`/`div 0xFF242424`); no per-screen `_kCard/_kBorder` copies; SafeArea on every step; empty states distinguish `no data yet` from `integration failure`. |
| AUTH-11 | No silent error swallowing on auth paths: do not use bare `ErrorWidget.builder → SizedBox.shrink`; surface inline errors and log to `app_incidents` without PII spam. Severity for triage: **[CRIT]** wrong data/fake-number dial/build failure; **[HIGH]** silent no-op/blocked flow; **[MED]** inconsistency/dead UX; **[LOW]** cosmetic. |
| AUTH-12 | MethodChannel identity `com.medxai.sundr/ble` (+ `/ble_events`, `/phone_mode` in `lib/config.dart:20-23`) and package `com.medxai.sundr` consistent across Gradle/manifest/Kotlin; `supabase_flutter` session is the only auth store (no iOS Keychain nuance beyond defaults). |

---

## 4. Data model (profile)

Collected during onboarding / editable later in Profile Edit:

| Field | Type | Notes |
|-------|------|-------|
| name / full_name | string | Completeness gate |
| age | int | 1–100 |
| gender | string | Gates women’s health card + AWHE |
| height_cm | int | 100–250 |
| weight_kg | double | 20–250 |
| emergency_contact_* | optional | Also managed under fall detection / contacts; never fake-seeded; future `caregiver_links` opt-in |

Model: `lib/models/onboarding_data.dart`. Cloud: `user_profiles` (RLS owner-only). Native: `emergency_contact` Room entity; sync credential keys `device_address`, `user_logged_in`.

---

## 5. Acceptance criteria

- [ ] New user can sign up, complete onboarding, land on Home.
- [ ] Returning user with profile skips onboarding.
- [ ] Abandoned onboarding (account exists, no name) re-enters onboarding after login.
- [ ] Logout returns to splash/auth; background ring reconnect does not prompt while logged out; `clearPersonalData` drops local DB + prefs.
- [ ] Invalid credentials show a clear error without crashing (no swallowed `ErrorWidget` blank).
- [ ] Password recovery path completes for a valid email (environment-dependent).
- [ ] No fake emergency contact exists after onboarding; empty list stays empty.
- [ ] Delete account removes `user_profiles` + vitals + alert/link rows + `auth.users` via `delete_user_account()`.

---

## 6. Out of scope / gaps

- Social / OAuth providers (unless added later).
- Multi-factor authentication.
- Full iOS Keychain nuances beyond `supabase_flutter` defaults.
- Companion link-request/accept UI (`caregiver_link_requests` tables exist, UI not built — see SMS doc §4; product-level only here).
- Cloud SMS backup invocation (`supabase/functions/send-emergency-alert` built, not invoked).

---

## 7. Related

- [02-device-pairing-ble.md](./02-device-pairing-ble.md)
- [11-data-sync-storage.md](./11-data-sync-storage.md)
- `architecture/Flutter_App.md` initialization workflow
- `docs/sms/emergency-alerting-system.md` §§4/8 (linking, privacy — product-level)
- `docs/archive/eval/00-EXECUTIVE-SUMMARY.md` (CRIT-2 fake contacts, RLS, `clearPersonalData`)
- `docs/archive/scratch_docx.txt` (AWHE gender-gated vision)
