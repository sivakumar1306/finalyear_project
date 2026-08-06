# 08 — Security, Privacy & Permissions

## 8.1 Supabase URL + anon key committed — expected, but env-tied — [MED]

`lib/config.dart:4-9` — committed prod URL (`https://eixcdjvfbwrziudieodr.supabase.co`) + anon key as `String.fromEnvironment` fallback. Anon keys are publishable **only if RLS gates every table**. Since ~14 app tables aren't in migrations, their RLS state is unverified (see 05.1/8.2).

## 8.2 RLS is the critical gate — unverifiable for unmigrated tables — [CRIT]

RLS confirmed only for the 6 migrated tables (05.3). For `user_profiles`, `user_bp`, `user_emergency_contacts`, etc., there is **no versioned policy**. If they were created in the dashboard without RLS, any user with the anon key can read every user's vitals and emergency contacts. Must verify live + add migrations.

## 8.3 Fake emergency contacts — the worst privacy/trust issue — [CRIT]

Two screens seed fabricated contacts (`9999999999`, `+91 000 000 0000`) (01.3). On the real pipeline these get SMS/call attempts. Users' safety expectations are built on fake data.

## 8.4 Incidents table — PII exposure risk — [MED]

`app_incidents` (migration exists, RLS: anon insert + auth insert + service full, `20260803000000_app_incidents.sql`) receives Flutter crash payloads (`lib/main.dart:80-107`). Risks:
- stack traces can embed health values/URLs/tokens if exceptions stringify them,
- **anon can INSERT** — an attacker can flood the table (no write-rate limit) and read side-effects,
- no environment marker (dev/test/prod) in the payload → production table pollution.

Recommend: strip PII at `IncidentService.reportIncident`, add env field, rate-limit, service-role-only inserts.

## 8.5 Permissions — over-broad, verified — [HIGH]

Declared (main manifest): `READ_CONTACTS`, `READ_PHONE_STATE`, `READ_CALL_LOG`, `RECEIVE_SMS`, `READ_SMS`, `SEND_SMS`, `RECORD_AUDIO`, `CALL_PHONE`, background + fine location, Health Connect full read/write set, `POST_PROMOTED_NOTIFICATIONS`.

Requested at startup (`lib/main.dart:22-32`): bluetooth*, location, notification, **sms, phone**.

Issues:
- **`RECORD_AUDIO` has no consumer found** — Play will reject or demand justification.
- SMS/call permissions are needed only if auto-emergency ships (spec says it should NOT — 01.2). If it ships, permissions are consistent; if not, they're a review risk.
- `ACCESS_BACKGROUND_LOCATION` needs a foreground-service justification.
- Health Connect: `READ_HEALTH_DATA_HISTORY` + write set is broad; confirm only needed permissions are requested.

## 8.6 Auto-SMS content — verify — [MED]

`EmergencySmsSender.kt` — message text + recipients (Room `emergency_contacts`) — confirm: no sensitive vitals in the SMS body; cooldown between consecutive sends (falls can re-trigger); cancel path (`EmergencySmsCancelReceiver`) works.

## 8.7 Privacy policy / terms — missing — [LOW]

No privacy-policy asset found. Health-data app → legal release blocker (outside code scope, flag for product).

## 8.8 Network security — [OK]

HTTPS only (Supabase + Railway). No `usesCleartextTraffic` found in manifests.

## 8.9 SharedPreferences plaintext — [LOW]

Prefs keys stored plain; vitals live in Room (native) — acceptable; no vitals in prefs found.

## 8.10 Health Connect consent UX — [MED]

`health_connect_service.dart` — Android 14+ requires the Health Connect permission flow; confirm first-run UX drives OS consent and handles denial gracefully.

---

## Summary

| Item | Risk |
|---|---|
| RLS for ~14 unmigrated tables | **CRIT — verify urgently** |
| Fake emergency contacts | **CRIT — remove seeding** |
| SMS/CALL/RECORD_AUDIO permission surface | HIGH (review/justify) |
| `app_incidents` anon-insert + PII | MED |
| Privacy policy | missing |
| Health-connect consent UX | verify |
| HTTPS-only | OK |