# 01 — Authentication & Onboarding

| Field | Value |
|-------|-------|
| **Status** | Shipped |
| **Primary platform** | All Flutter targets (Supabase Auth); BLE pair step is Android-first |
| **Key code** | `lib/screens/auth/*`, `lib/screens/onboarding/*`, `lib/services/supabase_service.dart` |

---

## 1. Purpose

Establish identity, collect a minimal health profile, optionally pair a ring, then enter the main app.

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

### 2.4 Password recovery

| Screen | Behavior |
|--------|----------|
| Forgot password | Request recovery email / code path via Supabase |
| Recovery code | Enter code from email |
| Reset password | Set new password |

*(Screens: `forgot_password_screen.dart`, `recovery_code_screen.dart`, `reset_password_screen.dart`.)*

### 2.5 Onboarding (profile)

Shared chrome: `onboarding_shell.dart` — step dots, SKIP, Continue, design tokens.

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

### 2.6 Log out

Settings → Account → confirm → `SupabaseService.signOut` → route `/`.  
Native `user_logged_in` flag and `configureSync` must clear / reconfigure so background reconnect does not run for a logged-out user.

### 2.7 Account deletion

Supabase RPC `delete_user_account()` (SECURITY DEFINER, `auth.uid()` only) removes user-owned rows and `auth.users`.  
UI entry lives under account settings; must only call while authenticated.

---

## 3. Functional requirements

| ID | Requirement |
|----|-------------|
| AUTH-01 | Support email/password sign-up and sign-in via Supabase Auth. |
| AUTH-02 | Persist session via `supabase_flutter`; restore on next launch. |
| AUTH-03 | On every auth state change, update native sync config (URL, anon key, user id, access token) and `user_logged_in`. |
| AUTH-04 | Incomplete profiles cannot skip past onboarding permanently without filling name (routing gate on splash/login). |
| AUTH-05 | Password minimum 6 characters client-side; server is source of truth. |
| AUTH-06 | Onboarding profile fields stored in `user_profiles` (or equivalent) with RLS owner access. |
| AUTH-07 | Ring pairing is optional at onboarding; user can bind later from Home or Settings. |
| AUTH-08 | User can log out and delete account; delete removes cloud personal data per migration. |

---

## 4. Data model (profile)

Collected during onboarding / editable later in Profile Edit:

| Field | Type | Notes |
|-------|------|-------|
| name / full_name | string | Completeness gate |
| age | int | 1–100 |
| gender | string | Gates women’s health card |
| height_cm | int | 100–250 |
| weight_kg | double | 20–250 |
| emergency_contact_* | optional | Also managed under fall detection / contacts |

Model: `lib/models/onboarding_data.dart`.

---

## 5. Acceptance criteria

- [ ] New user can sign up, complete onboarding, land on Home.
- [ ] Returning user with profile skips onboarding.
- [ ] Abandoned onboarding (account exists, no name) re-enters onboarding after login.
- [ ] Logout returns to splash/auth; background ring reconnect does not prompt while logged out.
- [ ] Invalid credentials show a clear error without crashing.
- [ ] Password recovery path completes for a valid email (environment-dependent).

---

## 6. Out of scope / gaps

- Social / OAuth providers (unless added later).
- Multi-factor authentication.
- Full iOS Keychain nuances beyond `supabase_flutter` defaults.

---

## 7. Related

- [02-device-pairing-ble.md](./02-device-pairing-ble.md)  
- [11-data-sync-storage.md](./11-data-sync-storage.md)  
- `architecture/Flutter_App.md` initialization workflow  
