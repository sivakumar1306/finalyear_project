# 08 — Security, Privacy & Permissions

> Refs are `file:line`. All confirmed by direct read.
>
> Status legend: ✅ fixed · 📋 addressed/documentary · ⏸️ deferred by decision · ❌ still open
> Status as of **2026-08-07**.

## 8.1 Supabase URL + anon key committed — expected, but env-tied — 📋 documented decision

`lib/config.dart:4-13` — committed prod URL + anon key as `String.fromEnvironment` fallback.
Anon keys are publishable only if RLS gates every table — which is now true and versioned
(8.2). Per-env anon keys remain a deployment preference, not a release blocker.

## 8.2 RLS is the critical gate — unverifiable for unmigrated tables — ✅ fixed

> **Fix (2026-08-06):** `20260806000000_missing_tables.sql` enables RLS and creates owner
> policies (`auth.uid() = user_id` / `= id`) on all 14 formerly-unversioned tables
> (`user_profiles`, `user_bp`, `user_emergency_contacts`, etc.), guarded for idempotence.
> With `20260807000000` the fresh-DB path also produces those tables (5.1).
>
> **Remaining:** one-time verification on the live dashboard that the manually-created
> tables didn't pre-exist with RLS disabled (policy creation is guarded, so a pre-existing
> table without RLS would have been left untouched). Cheap SQL check:
> `select relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
>  where n.nspname='public' and relname like 'user_%' and not relrowsecurity;`

## 8.3 Fake emergency contacts — the worst privacy/trust issue — ✅ fixed

> **Fix (2026-08-06):** seeding removed from both screens (`fall_detection_screen.dart`,
> `profile_edit_screen.dart`) — contacts start empty with a warning prompt. Native
> `EmergencySmsSender.schedule()` refuses to run the countdown until ≥1 contact with a
> digit exists (`EmergencySmsSender.kt:88-105`), and `EmergencyAutoCaller` no-ops on an
> empty list. (See 01.3 for full detail.)

## 8.4 Incidents table — PII exposure risk — ✅ fixed (app side)

> **Fix (2026-08-07):** `lib/services/incident_service.dart` now:
> * strips PII (phone / e-mail / JWT / `Bearer` tokens) from messages and stack traces,
> * adds an `app_env` marker (`production`/`development`, `APP_ENV` override),
> * rate-limits per source (10/min), dedupes identical reports (60 s), caps payload size.

`app_incidents` still permits anon INSERT — intentional, so pre-login crashes can be
reported (the table has no read policy, so an attacker cannot read others' rows; inserts
are now bounded client-side). A server-side insert rate-limit (e.g. a `security definer`
RPC or Postgres trigger) is a future hardening option.

## 8.5 Permissions — over-broad — ✅ fixed

> **Fix (2026-08-07):** removed from `AndroidManifest.xml` the permissions with **no
> consumer anywhere in Dart or Kotlin**:
> `READ_CALL_LOG`, `READ_SMS`, `RECEIVE_SMS`, `READ_CONTACTS` (emergency contacts are
> manually entered and stored in Room — nothing reads the device address book),
> `ACCESS_BACKGROUND_LOCATION` (no background location code exists),
> `POST_PROMOTED_NOTIFICATIONS`, `READ/WRITE_EXTERNAL_STORAGE` + `requestLegacyExternalStorage`
> (OTA picks files via Storage Access Framework; downloads go to app-private storage).

Remaining declared set is fully justified by consumers:

| Permission | Consumer |
|---|---|
| `SEND_SMS` | `EmergencySmsSender.kt` (fall alert SMS) |
| `CALL_PHONE`, `READ_PHONE_STATE` | `EmergencyAutoCaller.kt` (+ `BlePlugin.kt:2989`) |
| `RECORD_AUDIO` | `speech_to_text` AI-assist voice sheet (`lib/screens/assist/voice_listening_sheet.dart`) |
| `ACCESS_FINE/COARSE_LOCATION` | BLE scanning on Android < 12 (`permission_handler` request in `main.dart:43-52`) |
| Health Connect set | `lib/services/health_connect_service.dart` (per-metric READ/WRITE) |
| `ACCESS_NOTIFICATION_POLICY` | DND / phone-mode control (native) |
| `ACTIVITY_RECOGNITION` | step sync (`health_connect_service.dart:198-203`) |

## 8.6 Auto-SMS content — ✅ verified

`EmergencySmsSender.kt`:
- **No sensitive vitals in the SMS body** — static `DEFAULT_MESSAGE` (line 49-50) with no
  measurements or URLs.
- **Cooldown** — `SEND_COOLDOWN_MS = 15 min` prevents re-spam on repeated triggers
  (line 47, 74-79); pending countdowns are never restarted (82-86).
- **Cancel path** — 30 s cancellable countdown (`EmergencySmsCancelReceiver`,
  notification action), restored across process death (`restoreIfNeeded`, 179-201).
- **Guards** — refuses to send with an empty/fake contact list (88-105) or without
  `SEND_SMS` (234-245).

## 8.7 Privacy policy / terms — ✅ exists in-app (legal review still product-owned)

`lib/screens/settings/privacy_policy_screen.dart` (reachable from Settings → About →
Privacy Policy, `about_screen.dart:96`). Last updated July 25, 2026. A legal review for
store compliance (and, if required, a hosted URL for Health Connect's
`ACTION_SHOW_PERMISSIONS_RATIONALE` deep link) remains a product task, not code.

## 8.8 Network security — ✅ OK

HTTPS only (Supabase + Railway). No `usesCleartextTraffic` in any manifest.

## 8.9 SharedPreferences plaintext — ✅ OK

Prefs keys are plain; no vitals stored in prefs (vitals live in native Room). Acceptable.

## 8.10 Health Connect consent UX — ✅ verified

`lib/screens/settings/health_connect_screen.dart` drives the full flow: availability
check + Play Store install path (`_install`), first-run connect drives the OS consent
sheet via `requestAuthorization` (`_connect` / `_toggle`, including per-metric grants when
a type is newly enabled), denial is handled gracefully with a snackbar ("permission not
granted — nothing will sync"), and `revokeAll()` on disconnect. Android 14+ 30-day
history unlock is requested best-effort (`health_connect_service.dart:214-219`).

---

## Summary

| Item | Status |
|---|---|
| RLS for all app tables | ✅ versioned in migrations (verify live once) |
| Fake emergency contacts | ✅ removed |
| SMS/CALL/RECORD_AUDIO permission surface | ✅ trimmed to consumers; justified set remains |
| `app_incidents` PII / flood risk | ✅ scrubbed + rate-limited + env-tagged |
| Privacy policy | ✅ in-app screen (legal review outstanding) |
| Health-connect consent UX | ✅ verified |
| HTTPS-only | ✅ OK |
