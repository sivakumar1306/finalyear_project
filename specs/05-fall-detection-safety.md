# 05 — Fall Detection & Safety (INTEGRATED)

| Field | Value |
|-------|-------|
| **Status** | Partial — Phases 1–3 built + phone-SMS path honest; cloud-Twilio backup built-not-invoked; FCM receive built-dormant; prediction live but **not validated** against real falls |
| **Key docs** | `specs/FALL_DETECTION_STATUS.md`, `architecture/Health_Analysis.md`, `docs/sms/emergency-alerting-system.md`, `docs/archive/eval/01-CONFIRMED-BUGS-LOGIC.md`, `docs/archive/eval/02-STUBS-PLACEHOLDERS-DEMO-DATA.md`, `docs/archive/eval/08-SECURITY-PRIVACY-PERMISSIONS.md` |
| **Key code** | `analysis/FallRiskAnalyzer.kt` (`currentTier()`), `analysis/FallMotionDetector.kt` (`snapshot()`, 50Hz), `analysis/FallAlertNotifier.kt`, `analysis/FallPredictionNotifier.kt`, `analysis/EmergencySmsSender.kt` (`schedule`/`sendNow`/`status`/`cancel`/`restoreIfNeeded`), `analysis/EmergencySmsResultReceiver.kt`, `analysis/EmergencyAutoCaller.kt` (`placeIfEnabled`/`placeCall`/`setEnabled`/`status`), `BlePlugin.kt` (`getFallRiskScore`/`getFallEvents`/`getMotionSnapshot`/`getEmergencySmsStatus`/`sendEmergencySms`/`cancelEmergencySms`/`simulateFallEvent`/`simulateFallPrediction`/`simulateFallRiskTrigger`), `fall_detection_screen.dart` (`/fall-detection`), Flutter `services/fall_prediction/*` (`fall_prediction_engine.dart` `baseAlpha/Beta/Gamma/Delta`, `layer3_motion.dart` `parseNativeFallEvents`/`recentMotionPeak`/`gaitVariabilityFromStepSlots`, `fall_prediction_provider.dart` `motionSnapshot`/`trailingFalls`), `services/push_notification_service.dart` (`PushNotificationService`), `supabase/functions/send-emergency-alert/index.ts` (`COOLDOWN_MS`, `normalizePhone`) |

---

## 1. Purpose

1. **Predict** elevated near-term fall *risk* from cardiovascular / syncope-oriented vitals patterns.
2. **Detect** likely falls using phone motion + vitals corroboration (ring SDK exposes no continuous accel/gyro stream).
3. **Alert** via three-part system: (1) phone-SMS best-effort free, (2) cloud-Twilio guaranteed backup, (3) in-app FCM push to linked SUNDR contacts.

**Clinical honesty:** mechanical trip-and-fall often has no physiological prodrome. Prediction is scoped as **syncope/cardiovascular pre-fall signal**, not universal fall predictor.

---

## 2. Product scope & explicit non-scope

### In scope

- Vitals-based risk score 0–100 + tier logged on every analysis (`fall_risk_log` Room).
- Live predictive alerts for HIGH/CRITICAL/OVERRIDE with cooldown.
- Phone accelerometer/gyro three-phase detector (free-fall → impact → stillness) at 50 Hz.
- Corroboration window ±30 s (`CORROBORATION_WINDOW_MS = 30_000L`) against vitals spikes before local fall alert.
- Local notification with "I'm okay" dismiss + 30 s cancelable SMS countdown.
- Emergency contacts persisted natively (Room `emergency_contact`) + optional cloud mirror `user_emergency_contacts`.
- Phone-SMS receipt ledger (SENT/DELIVERED/unknown after 90 s) via `getEmergencySmsStatus`.
- UI: score, history, contacts, debug simulation tools (SIMULATION-labeled, no SMS).

### Out of scope / deferred (with status 2026-09-19)

- Continuous ring IMU fall detection (SDK `qring_sdk_1.0.0.50.aar` `com.oudmon.ble.*` streams none continuously; only `manualModeHeartRateRawData` bundles accel X/Y/Z in short diagnostic session).
- Claiming general mechanical trip-and-fall prediction from vitals alone.
- Cloud SMS backup invocation — **built, not invoked** (`supabase/functions/send-emergency-alert` exists, no app caller).
- FCM live delivery — **partial**: token registration + receive/display (`/companion-alert`) live but dormant without Firebase config; link-request UI missing.
- Full-screen lockscreen overlay — planned.
- FD-33 auto SMS/call: **product-approved 2026-08-06** (was deferred "unless explicitly product-approved later"). Auto-SMS stays countdown-cancelable; auto-call stays behind explicit opt-in toggle `setAutoCallOnFallEnabled`.

---

## 3. Architecture (three phases + three-part alert)

```
Phase 1 — Predictive (vitals)
  NewReadingEvent(simulated) → FallRiskAnalyzer.onNewReading → fall_risk_log (always)
    → (HIGH/CRITICAL/OVERRIDE + ALERT_COOLDOWN_MS) → FallPredictionNotifier.notifyPrediction(simulated)
    → (if !simulated) EmergencySmsSender.schedule(reason="prediction")

Phase 2 — Active detection (phone motion)
  Accel/Gyro 50Hz (SAMPLE_RATE_HZ=50, WINDOW_SECONDS=2.0, ANALYSIS_INTERVAL_MS=200)
    → FallMotionDetector.analyzeWindow → fall_event (always, incl. non-corroborated)
    → checkVitalsCorroboration(±30s HR/stress/SpO2) → Phase 3

Phase 3 — Local alert + three-part fan-out
  FallAlertNotifier.notifyFall → notification + "I'm okay" + EmergencySmsSender.schedule(reason="fall")
    → Part 1 phone SmsManager (free best-effort)
    → Part 2 cloud Twilio via send-emergency-alert edge fn (backup, pending wiring)
    → Part 3 FCM push to ACCEPTED caregiver_links with user_push_tokens (pending Firebase + link UI)
```

Both detectors run inside existing BLE foreground service (`BleConnectionService`); no second service. `FallRiskAnalyzer.currentTier()` (`@Volatile _lastTier`, default `"LOW"`) drives `MeasurementLoopManager` adaptive cooldown.

---

## 4. Phase 1 — Fall risk score (native `FallRiskAnalyzer.kt`)

| ID | Requirement |
|----|-------------|
| FD-01 | On each persisted vital reading (`onNewReading(event)`), compute score 0–100 + tier (`LOW/HIGH/CRITICAL/OVERRIDE`). |
| FD-02 | Inputs: sedentary HR anomalies, SpO₂, BP extremes / pulse pressure, stress vs 5-min baseline (`BASELINE_WINDOW_MS = 5*60_000L`), HRV drops vs baseline when available. |
| FD-03 | **Hard override:** `CRITICAL_SPO2 = 88`; SpO₂ < 88 → `ScoreResult(100, "OVERRIDE")` with `components["override"]="spo2_critical"`. |
| FD-04 | Log every computation to Room `fall_risk_log` regardless of tier (silent measurement). |
| FD-05 | For HIGH/CRITICAL/OVERRIDE, `maybeAlert` fires `FallPredictionNotifier` subject to `ALERT_COOLDOWN_MS = 15*60_000L` (~15 min). |
| FD-06 | Predictive copy must not overclaim (risk / "might fall", not guaranteed fall). |
| FD-07 | `currentTier(): String = _lastTier` must stay `@Volatile` (written BACKGROUND thread, read by `MeasurementLoopManager` main thread; posts `RiskTierChangeEvent`). |

### Flutter multi-layer model (UI explainability, `FallPredictionEngine`)

Dart engine computes HSI / risk layers for settings UI (physiological, recovery, motion, women's health, adaptive weights).

| ID | Requirement |
|----|-------------|
| FD-10 | Document polarity: **HSI = stability (higher better)**; **risk score = higher worse**. |
| FD-11 | UI prefers **Fall Risk Score**, not ambiguous "Fall Confidence Score". |
| FD-12 | Adaptive weights renormalize so Σw = 1 (`adaptive_weight_engine_test.dart`; `getHsiGlobalWeights`). Base: `baseAlpha=0.35` physiological, `baseBeta=0.30` recovery, `baseGamma=0.20` motion, `baseDelta=0.15` women's health. `computeHsiBase` uses fixed base; `computeHsiAdj` uses dynamic `hsiWeights['physiological'/'recovery'/'motion'/'womens_health']`. |
| FD-13 | Open issues (recovery term polarity, triple-counting history, missing personal baselines) are P0/P1 backlog before research claims. UI label is **Risk Reasoning**, never AI Reasoning (`explainable_ai_dashboard.dart` already honest; eval 02.6 ALREADY HONEST). |

### Layer-3 motion sourcing (Flutter `Layer3MotionData` + `Layer3MotionService`)

No continuous IMU (ring SDK streams none; phone sensors run only while armed on HIGH-tier risk). Unknown stays `null`, never healthy constant:

| Field | Source | Rule |
|-------|--------|------|
| `fh` + `trailingFalls` | Primary: native Room `fall_event` via `BleProvider.getFallEvents(limit: 500)` → `Layer3MotionService.parseNativeFallEvents` (365-day filter `now.subtract(Duration(days:365))`, dev-simulated rows excluded). Secondary: Supabase `falls` merged in (covers history past 90-day local purge + other devices). Cache TTL 1 h (`_cachedTrailingFalls`, fallsStale check; 15-min baseline comment). | Known-zero → `fh=0.0`; no source → `fh=null` (coverage penalizes honestly). |
| `acc` / `gyr` | Most recent non-simulated native event's `metadataJson` `peakG`/`peakGyro` via `recentMotionPeak(nativeRows)` (`_cachedMotionPeak`), only if < 24 h old. | Event-driven impact signal. Stale/absent → `null`. |
| `gait` | Step-pattern CV proxy `gaitVariabilityFromStepSlots(todayStepsByInterval)`: CV over active 15-min slots up to now, ≥6 slots required, CV ≤ 1.0 → 0.0, saturates 0.5. | Heuristic proxy, not clinical gait. Never dominates MO. Insufficient → `null`. |
| `psw` / `ortho` | No source (no sway test, no posture-change timestamps). | Always `null`. |
| `plnt` | No smart insole (`hasSmartInsole = (mData.plnt != null)` false). | Always `null` (motion weights zero it). |
| Monitoring state | `BlePlugin.getMotionSnapshot` → `FallMotionDetector.snapshot()`: `sensorsActive`, `windowsAnalyzed`, `maxMagnitudeG` (`maxMagnitudeGSeen`), `lastPeakG`, `lastPeakGyro`. Exposed via `FallPredictionProvider.motionSnapshot`. | **Not scored** — sensors run only in HIGH-tier windows so sample is biased. |

| ID | Requirement |
|----|-------------|
| FD-14 | Trailing history prefers native `fall_event` over Supabase `falls`; merge both, exclude dev-simulated rows, 365-day window, `limit: 500`, TTL 1 h. |
| FD-15 | `acc`/`gyr` only from < 24 h non-simulated event peak via `recentMotionPeak`; else `null`. |
| FD-16 | `gait` proxy conservative (no penalty at normal variability, capped) labeled heuristic in code. |
| FD-17 | `getMotionSnapshot` output never feeds scoring — monitoring state only. |

---

## 5. Phase 2 — Active motion detection (`FallMotionDetector.kt`)

| ID | Requirement |
|----|-------------|
| FD-20 | Sample phone accelerometer ~50 Hz (`SAMPLE_RATE_HZ=50f`, 20 000 µs sampling, 5 s batching); gyroscope optional confidence boost (`GYRO_SPIKE_RAD_S=4.0f`). |
| FD-21 | Free-fall: magnitude < `FREE_FALL_G=0.4f` g for minimum duration (~80 ms contiguous samples). |
| FD-22 | Impact: `peakG > IMPACT_G=3.0f` g within ~500 ms of free-fall end. |
| FD-23 | Post-impact stillness: ≥ `STILLNESS_SAMPLE_RATIO=0.35f` samples within `STILLNESS_DEVIATION_G=0.35f` g — mandatory (not bypassable by gyro spike alone). |
| FD-24 | Minimum confidence `MIN_CONFIDENCE=0.55f` to accept candidate. |
| FD-25 | Thresholds in **g-units** (`GRAVITY=9.81f` divisor), never raw m/s² mistaken for g (regression: old code ~10× too sensitive, FP on walking; validated drop test 76% confidence). |
| FD-26 | Log **all** candidates to Room `fall_event` (incl. non-corroborated) with `peakG`/`peakGyro` in `metadataJson`. |
| FD-27 | Corroborate with vitals spike (HR `heartRateBetween`, stress `stressBetween`, SpO₂) in `CORROBORATION_WINDOW_MS=30_000L` (±30 s) before Phase 3. Battery guard: `SENSOR_AUTO_OFF_MS=10*60*1000L`, `COOLDOWN_MS=8_000L` between candidates. |

---

## 6. Phase 3 — Local alerting + three-part emergency system

### 6.1 Local alert

| ID | Requirement |
|----|-------------|
| FD-30 | High-priority local notification only on corroborated events (`FallAlertNotifier.notifyFall`). |
| FD-31 | "I'm okay" action dismisses without emergency side effects. |
| FD-32 | Tap opens Fall Detection settings (`/fall-detection`). |
| FD-33 | Auto SMS/call ships **product-approved 2026-08-06** (eval 01.2 ⏸️): auto-SMS countdown-cancelable; auto-call gated by `EmergencyAutoCaller.setEnabled` opt-in toggle; empty list blocks (see FD-61). |

### 6.2 Three-part alert system (infused from `docs/sms/emergency-alerting-system.md`)

| Part | Transport | Cost | Status 2026-09-19 |
|------|-----------|------|-------------------|
| 1. Phone SMS (best-effort, free) | `EmergencySmsSender` via `SmsManager` + `EmergencySmsResultReceiver` SENT/DELIVERED PendingIntents (`ACTION_SMS_SENT`/`ACTION_SMS_DELIVERED`, `EXTRA_PHONE/NAME/PART/TOTAL`), receipt ledger in `qring_emergency_sms` prefs, `getEmergencySmsStatus` snapshot | Free | Live + honest |
| 2. Cloud SMS (guaranteed backup) | Edge fn `supabase/functions/send-emergency-alert` via Twilio (`TWILIO_ACCOUNT_SID`/`TWILIO_AUTH_TOKEN`/`TWILIO_FROM_NUMBER`), writes `emergency_alerts` + `emergency_alert_deliveries`, `COOLDOWN_MS=15*60*1000` | ~$1/mo number + ~$0.0075/text; only backup texts cost | Built, not invoked (no app caller; offline phone = no alert until wired) |
| 3. In-app push (instant, free) | FCM via `PushNotificationService` (`initialize`/`syncToken`/`_registerToken` upsert `user_push_tokens`, `firebaseMessagingBackgroundHandler`, `_handleForegroundMessage`, `_openAlert` → `/companion-alert`); only to ACCEPTED `caregiver_links` with token | Free (needs Firebase project + `FIREBASE_API_KEY/PROJECT_ID/SENDER_ID/APP_ID` via `--dart-define`, `firebaseConfigured` gate) | Partial: receive/display live, dormant without config; link-request UI missing |

Today-state table (honest):

| Aspect | Today |
|---|---|
| SMS to saved contacts | Works, phone-only |
| Confirm arrival | Partial: per-contact SENT/DELIVERED/unknown; unanswered settle `unknown` after `RECEIPT_TIMEOUT_MS=90*1000L`; no carrier-grade read proof |
| SMS permission off | Send fails; `status()` reports `hasPermission:false` + `lastError`, never silent success |
| No signal | Cannot go out; cloud backup exists but never invoked |
| SUNDR-to-SUNDR contact | In-app alert **if** Firebase configured + accounts linked; else nothing special |
| Audit trail | Per-contact snapshot via `getEmergencySmsStatus`; cloud `emergency_alerts`/`emergency_alert_deliveries` exist but phone path doesn't write them yet |

| ID | Requirement |
|----|-------------|
| FD-40 | Optional countdown before SMS/call; user can cancel. Phone-side: `COUNTDOWN_SECONDS=30`, `EmergencySmsSender.schedule(reason)` starts, `cancel()` clears + `KEY_LAST_CANCELED_AT`, `restoreIfNeeded` re-arms across process death from `KEY_ACTIVE/KEY_SEND_AT/KEY_REASON`, tick/watchdog Runnables on main `Handler`, `SafetyLiveUpdate`. `status()` returns `active/secsRemaining/reason/countdownSeconds/lastSentAt/lastSentCount/lastError/lastCanceledAt/hasPermission/sendInProgress/queuedCount/deliveredCount/failedCount/perContact`. Cloud failover pending. |
| FD-41 | Caregiver push via FCM (`user_push_tokens(user_id,fcm_token,platform,updated_at)` unique `(user_id,fcm_token)`). Receiving half live; cloud sender never invoked; link-request UI missing. Transport decision still open (FCM vs Supabase realtime) per `FALL_DETECTION_STATUS.md`. |
| FD-42 | SMS/call uses onboarding/settings emergency contacts (native Room `emergency_contact` feeds pipeline); auto-call behind explicit opt-in toggle (`EmergencyAutoCaller.isEnabled/placeIfEnabled/placeCall`). |
| FD-43 | Edge fn contract: `POST send-emergency-alert` with `{reason: fall\|prediction\|manual, message?, triggeredBy: device\|manual\|cloud_fallback, location: {lat,lng,accuracy}, contacts: [{name,phone}]}`; auth Bearer wearer JWT (`SupabaseConfig.accessToken`); `normalizePhone` strips `[^0-9+]`; missing Twilio/FCM degrade to `skipped` delivery rows; `CORS_HEADERS` allow `authorization,x-client-info,apikey,content-type`. |

### 6.3 Message templates (keep table)

Actual phone templates (`EmergencySmsSender.getMessageForReason`, no name personalization; live location map link appended when fresh fix within `LOCATION_MAX_AGE_MS=30*60_000L`):

| Reason | Template |
|--------|----------|
| `fall` | "We have detected a fall. We have detected that you may have potentially fallen. — Sent by SUNDR Fall Detection" |
| `prediction` | "You might fall soon... We have detected multiple signs that you might fall down in the next 2-3 minutes. Take a seat and contact your caretaker. — Sent by SUNDR Fall Detection" |
| `heart_rate` | "We are concerned ... Your heart rate rose to {hr} BPM while you seemed to be in-active for the last 10 minutes. — Sent by SUNDR Fall Detection" |
| `manual` / else | "I may have fallen and need help. Please check on me as soon as possible. — Sent by SUNDR Fall Detection" |

Proposed improvement (adds name + explicit reason + live map link):

> "Sarah — possible fall detected. Please check on me. My live location: [map link] — Sent by SUNDR"

Must include wearer **name**, **reason** (possible fall = phone-motion + vitals corroboration; prediction = vitals risk score; manual), **live map link** at alert moment. Saved home address stays put; only live location in alert.

| ID | Requirement |
|----|-------------|
| FD-44 | SMS templates per table above; `heart_rate` variant includes HR value. |
| FD-45 | Proposed template adds name + reason + map link; must not regress to optimistic "SMS sent" — surface `getEmergencySmsStatus` snapshot (remaining countdown, sent/delivered/unknown per contact, errors). Snapshot does not split phone-vs-backup per contact (no backup sender yet). |
| FD-46 | **Privacy:** no sensitive health data in SMS/alerts — just name, reason, location link. No vitals/measurements/URLs beyond map link in body. |

### 6.4 Account linking ("friend request" flow)

1. Wearer saves contact. If number belongs to SUNDR user, offer "This person is on SUNDR — send link request?"
2. Other person gets notification: "Your friend asked to make you their emergency contact. Accept?"
3. Only after **accept** are accounts linked (`caregiver_links`).
4. Thereafter contact gets text **and** instant in-app alert.

Why: privacy (nobody tracked without agreeing) + confirms right person (wearer sees matched name first).

| ID | Requirement |
|----|-------------|
| FD-47 | Linking tables: `caregiver_link_requests(id,requester_id,target_user_id,contact_name,contact_phone,status pending\|accepted\|declined\|canceled,created_at,responded_at)` unique `(requester_id,target_user_id,contact_phone)`; `caregiver_links(id,wearer_user_id,caregiver_user_id,contact_name,contact_phone,created_at)` unique `(wearer_user_id,caregiver_user_id)`. RLS per migration; `delete_user_account()` wipes both via `to_regclass` guard. |
| FD-48 | In-app alerts only to ACCEPTED links with token (two-sided consent). Text goes to *every* saved contact; in-app only to linked SUNDR users. |
| FD-49 | Screens: "Link with a SUNDR friend" button on save; "Companion requests" accept/decline section; `/companion-alert` display screen (exists, 216 lines, SOS). Requests UI pending — must build. |

---

## 7. Emergency contacts + safety guards (eval-infused)

| ID | Requirement |
|----|-------------|
| FD-50 | User can add/edit/remove contacts (`BleProvider.getEmergencyContacts/addEmergencyContact/updateEmergencyContact/deleteEmergencyContact`, `syncEmergencyContactsFromCloud`). |
| FD-51 | Contacts stored in **native Room** (`ReadingRepository.allEmergencyContacts`) so background actions read them; cloud mirror `user_emergency_contacts(user_id,local_id,...)` unique `(user_id,local_id)` for backup/sync. |
| FD-52 | Optional cloud mirror upserted on change; never blocks local pipeline. |
| FD-60 | **Fake-contact ban (eval 01.3/08.3 ✅ fixed 2026-08-06):** never seed `Mom → +91 000 000 0000`, `9999999999`, or `Default Emergency`. Both screens (`fall_detection_screen.dart:107-114`, `profile_edit_screen.dart:89-93`) start empty with warning prompt. `9999999999` is one digit from emergency lines — must never appear. |
| FD-61 | **Digit-guard + cooldown + cancel (eval 08.6 ✅ verified):** `EmergencySmsSender.schedule()` refuses countdown until ≥1 contact with a digit exists (`EmergencySmsSender.kt:88-105`, `namedPhones` filter `any{isDigit}` + `distinctBy`); `EmergencyAutoCaller.placeIfEnabled` no-ops on empty; `SEND_COOLDOWN_MS = 15*60_000L` prevents re-spam (never restart pending countdown); 30 s cancelable countdown via `EmergencySmsCancelReceiver` notification action; `restoreIfNeeded (179-201)` restores across death; `SEND_SMS` permission checked (`234-245`, `hasSendSmsPermission`), `DEFAULT_MESSAGE (49-50)` carries no vitals. |
| FD-62 | **Demo isolation (eval 01.4/02.2 ✅ fixed 2026-08-06):** `simulateFallEvent` inserts real `FallEventEntity` + `FallAlertNotifier.notifyFall` + safety live-update but **must not** call `EmergencySmsSender.schedule` or `EmergencyAutoCaller.placeIfEnabled`; `simulateFallPrediction` must not schedule SMS; `simulateFallRiskTrigger` posts `NewReadingEvent(simulated=true)` and `FallRiskAnalyzer.maybeAlert(...,simulated)` skips SMS (`if (!simulated)`), notifications labeled SIMULATION stating no SMS/call. Real paths (`FallMotionDetector`, `FallRiskAnalyzer`) untouched. `BleProvider.simulateFallEvent/simulateFallPrediction/simulateFallRiskTrigger/checkPendingFallPrediction` stay debug-only. |

---

## 8. Fall Detection settings UI (`fall_detection_screen.dart`, `/fall-detection`)

Must show: current risk score/tier (real engine, not placeholder); explainable layers if Flutter engine active (**Risk Reasoning** disclosure); fall event history (native `fall_event`, simulated excluded from scoring); contacts management (empty-state warning); debug menu (simulate tiers, fall notification, synthetic vital through real pipeline with `simulated=true`).

---

## 9. Cloud schema (emergency subset; full 34-table list in spec 11)

- `emergency_alerts(id,wearer_user_id,reason,message,location_lat,location_lng,location_accuracy_m,triggered_by device\|manual\|cloud_fallback,triggered_at)` index `(wearer_user_id,triggered_at desc)`.
- `emergency_alert_deliveries(id,alert_id→emergency_alerts,caregiver_user_id→auth.users null,on delete set null,contact_name,contact_phone,channel device_sms\|cloud_sms\|fcm_push,status queued\|sent\|delivered\|failed\|skipped,detail,created_at,updated_at)` index `(alert_id)`.
- `user_push_tokens(user_id,fcm_token,platform default 'android',updated_at)` unique `(user_id,fcm_token)`.
- `falls(id,user_id,timestamp,severity,created_at)` index `(user_id,timestamp desc)` — Supabase-only 365-day trailing source; nothing native writes it today.
- `fall_risk_log`, `fall_event` — **local Room only**, purged after 90 days (`RETENTION_RAW_DAYS`). Never synced. Read via `getFallRiskScore`/`getFallEvents`/`getMotionSnapshot`.

---

## 10. Work plan (from `docs/sms/emergency-alerting-system.md` §9, statuses 2026-09-19)

| Step | Deliverable | Depends on | Status |
|---|---|---|---|
| 1. Cloud foundation | Tables + services for alerts, delivery tracking, linking | — | Partial: tables exist (`emergency_alerts`,`emergency_alert_deliveries`,`caregiver_links`,`caregiver_link_requests`,`user_push_tokens`) but phone path doesn't write them |
| 2. Backup text messaging | Cloud SMS + receipts | Step 1 + Twilio account | Built, not invoked: edge fn exists, no app caller |
| 3. In-app alerts | Firebase setup, instant notifications | Step 1 + Firebase project | Partial: token registration + receive/display done, dormant without config |
| 4. Account linking | Friend-request flow (request → accept → linked) | Step 1 | Not built (tables only) |
| 5. Phone-side improvements | Honest tracking + auto backup | Step 2 | Partial: receipt ledger + snapshot done; failover pending Step 2 |
| 6. App screens | Companion requests, status messages, location | Steps 2–5 | Partial: `/companion-alert` exists; requests UI pending |
| 7. Testing | E2E: simulate fall → verify text + in-app | All | Not done |

Client needs: **Twilio** trial + number (~$1/mo + ~$0.0075/text; phone SMS stay free, only backup costs, fractions of a cent) + **Firebase** project config file. No daily-life change except optional "Link with a SUNDR friend" + "Companion requests" section.

---

## 11. Acceptance criteria

- [ ] Risk score updates after real ring readings; appears on Fall Detection screen.
- [ ] SpO₂ < 88 path yields OVERRIDE score 100 in analyzer logs.
- [ ] Drop test detected with confidence; walking/running FP acceptable after g-unit fix.
- [ ] Uncorroborated candidates log but do not notify.
- [ ] Corroborated path shows notification dismissible with "I'm okay".
- [ ] Contacts survive restart; empty list blocks SMS/call with error (no fake seeds).
- [ ] Simulation tools exercise notification/score without SMS/call, labeled SIMULATION with `simulated=true`.
- [ ] History reflects native `fall_event` (simulated excluded); < 24 h real peaks feed `acc`/`gyr`, else `null` with coverage penalty.
- [ ] `layer3_motion_sources_test.dart` passes (parsing, 24 h freshness, gait bounds); `fall_prediction_test.dart` + `adaptive_weight_engine_test.dart` pass (Σw=1).
- [ ] `getEmergencySmsStatus` shows honest per-contact SENT/DELIVERED/unknown (90 s settle), permission/signal failures as errors.
- [ ] E2E (when wired): offline-phone alert retries until online; every text has receipt; no silent failures/placebo.

---

## 12. Open validation work

1. Multi-hour battery impact of continuous sensors (`SENSOR_AUTO_OFF_MS`, batching).
2. Correlate logged scores vs real/near falls.
3. Align Flutter HSI/FRS math with native semantics; fix polarity/baseline; validate gait CV proxy + 24 h peak window on real data.
4. Caregiver push product decision (FCM vs Supabase realtime) + Firebase credentials + link UI + Step-2 wiring.
5. Ring-side motion corroboration via `manualModeHeartRateRawData` trigger — untried (rate/reliability unknown).

---

## 13. Related

- `FALL_DETECTION_STATUS.md`, `architecture/Health_Analysis.md`, `docs/sms/emergency-alerting-system.md`
- [11-data-sync-storage.md](./11-data-sync-storage.md) (cloud tables, RLS, delete wipe)
- [12-non-functional.md](./12-non-functional.md) (permissions `SEND_SMS`/`CALL_PHONE`/`READ_PHONE_STATE`, privacy policy)
