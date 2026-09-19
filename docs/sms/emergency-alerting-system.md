# SUNDR Emergency Alert System — Plain-English Overview

**Audience:** clients, product owners, non-technical reviewers.
**Purpose:** explain what the emergency alert feature does today, what is wrong with it, and what we propose to build — in everyday language, no code.

---

## 1. What the feature is supposed to do

When someone wearing a SUNDR ring has a problem — for example the **phone detects a possible fall** (phone accelerometer + vitals corroboration; the ring SDK exposes no continuous motion stream, so detection is phone-side, not ring-side) — SUNDR should quickly tell the people who can help:

1. The **emergency contacts** the wearer saved in the app.
2. Those contacts should hear about it **instantly**, in a way they cannot miss.

That's the whole point: a senior or at-risk person takes a fall, and the right people get the alert automatically.

---

## 2. What happens today — and why it isn't good enough

Today, the app can send a **text message (SMS)** to the saved emergency contacts using the wearer's own phone. Here's the honest picture:

| Aspect | Today |
|---|---|
| SMS to saved contacts | Works, but only on the wearer's own phone |
| Can we confirm the SMS arrived? | **Partially.** The app attaches SENT/DELIVERED receipts per contact (`EmergencySmsSender` receipt ledger, `EmergencySmsResultReceiver`); unanswered receipts settle to `unknown` after ~90s. There is still no carrier-grade "read" proof. |
| If the phone's SMS permission is off | The send fails and the status snapshot reports the error instead of succeeding silently |
| If the wearer's phone has no signal | The alert cannot go out from the phone — no cloud backup sends it yet (backup edge function exists but is never invoked) |
| A contact who also uses SUNDR | Gets an in-app alert **if** Firebase is configured and accounts are linked — otherwise nothing special |
| Proof of delivery (audit trail) | Per-contact sent/delivered/unknown snapshot via `getEmergencySmsStatus`; cloud `emergency_alerts` / `emergency_alert_deliveries` tables exist but are not yet written by the phone path |

**The problem in one sentence:** the phone SMS path now tracks its own delivery honestly, but it is still a single channel with no cloud backup — if the wearer's phone can't send, nobody gets the alert.

---

## 3. What we propose to build — the three-part alert system

We want to turn the current one-channel, unverifiable system into a **three-part system** that is dependable and provable:

```
A possible fall is detected on the phone (accelerometer + vitals corroboration)
                  │
                  ▼
         SUNDR cloud service  ◄── the "brain" in the internet
                 │
     ┌───────────┼───────────────┐
     ▼           ▼               ▼
  1. Text      2. Text        3. In-app
  message      message        alert
  sent by      sent by        to contacts
  the wearer's the SUNDR      who also use
  phone        cloud          SUNDR
  (cheap,      (guaranteed —  (instant pop-up
  best effort)  our safety     alert, even if
                 backup)       their app is closed)
```

### Part 1 — Text message from the wearer's phone (best effort, free)
The app keeps sending the SMS from the wearer's own phone when possible. This part is free, but it can fail (permission off, no signal) — so it is only the **first attempt**, not the whole plan.

### Part 2 — Text message from the SUNDR cloud (the safety backup)
If the phone-based text fails for any reason, the alert is automatically re-sent **from the internet** (through a text-message provider, like Twilio). This works even if the wearer's phone has no signal or SMS permission is off. This is the part that guarantees the text actually goes out.

> **Status (2026-09-19):** the cloud sender exists (`supabase/functions/send-emergency-alert`) but **no app code invokes it yet**, so this backup is built, not live. Until it is wired, an offline phone means no alert.

- If the phone is completely offline, the alert is saved and **kept trying automatically** until the phone is back online.
- Every text gets a **delivery receipt** — the provider tells us "delivered" or "failed", and we record it.

### Part 3 — In-app alert to contacts who use SUNDR (instant, free)
If a saved emergency contact is **also a SUNDR user** (and the two accounts are linked, see Section 4), they get an **instant app notification** — a loud pop-up on their phone — even if the SUNDR app is closed at the time. The alert shows who needs help, what happened, and a **live map location**.

> **Status (2026-09-19):** the receiving half is implemented — FCM token registration to `user_push_tokens` (`PushNotificationService`), foreground/background handlers, and the `/companion-alert` screen all exist — but the service stays dormant until Firebase credentials are configured, and the link-request/accept UI (Section 4) is not built yet.

> **Important:** the text message goes to *every* saved emergency contact. The in-app alert goes only to contacts who use SUNDR **and** have agreed to be linked (privacy protection, see Section 4).

---

## 4. Linking accounts — a "friend request" style flow

Today, a contact is just a name and a phone number. To send the in-app alert, SUNDR needs to know which contact is a real SUNDR user. We handle this the same way people handle social-media friend requests — nobody gets linked without both sides agreeing:

1. The wearer saves an emergency contact. If that phone number belongs to a SUNDR user, the app offers: **"This person is on SUNDR — send them a link request?"**
2. The other person gets a notification: **"Your friend asked to make you their emergency contact. Accept?"**
3. Only after they **accept** do the two accounts become linked.
4. From then on, that contact gets both the text message **and** the instant in-app alert.

**Why this flow?** It protects privacy (nobody gets alerts about you without agreeing) and it confirms the right person is connected (the wearer sees the matched person's name before sending the request).

---

## 5. What the alert message looks like

Actual templates sent today (`EmergencySmsSender`, no name personalization; the wearer's last-known location is appended as a map link when a fresh fix exists):

- Fall: *"We have detected a fall. We have detected that you may have potentially fallen. — Sent by SUNDR Fall Detection"*
- Prediction: *"You might fall soon... We have detected multiple signs that you might fall down in the next 2-3 minutes. Take a seat and contact your caretaker. — Sent by SUNDR Fall Detection"*

Proposed improvement (adds name + explicit reason + live map link):

> **"Sarah — possible fall detected.** Please check on me. My live location: [map link] — Sent by SUNDR"

- The wearer's **name**
- The **reason** (possible fall = phone-motion detection corroborated by vitals; fall prediction = vitals-based risk score; or manual alert)
- A **live map link** to the wearer's current location (taken at the moment of the alert)

(The wearer's saved home address stays where it is — we only use the live location in the alert.)

---

## 6. What we need from you (the client)

The system needs two paid services, both standard industry tools:

| Service | What it does | What you need to do |
|---|---|---|
| **Twilio** (text-message provider) | Guarantees text messages are actually delivered and reports delivery status | Create a free trial Twilio account, buy a phone number (~$1/month + ~$0.0075 per text). We handle everything else. |
| **Firebase / FCM** (Google's notification service) | Delivers the instant in-app alerts to SUNDR users | Create a free Firebase project and give us its configuration file. We handle everything else. |

**Cost note:** the phone-based text messages stay free. Only the *backup* texts (sent from the cloud) cost money, and only when they are actually used. Typical cost: fractions of a cent per message.

---

## 7. What changes for the user (the wearer / their contacts)

- **No change in daily life.** They keep saving emergency contacts exactly as today.
- One new, optional step: a **"Link with a SUNDR friend"** button when saving a contact whose number is a SUNDR user.
- Contacts who use SUNDR see a new **"Companion requests"** section where they accept or decline.
- Alerts now show **honest status**: the `getEmergencySmsStatus` snapshot (remaining countdown, sent/delivered/unknown per contact, errors) instead of an optimistic "SMS sent". Note: the snapshot does not split "via phone vs via backup" per contact — there is no backup sender yet.

---

## 8. Safety and privacy

- **No sensitive health data** is put in text messages or alerts — just name, reason, and location link.
- **Two-sided consent** for in-app alerts (Section 4) — nobody is tracked without agreeing.
- Every alert is **logged** (who was notified, how, and whether it was delivered) so we can prove the system worked — and investigate if it didn't.
- Your existing account-deletion feature will also wipe the new alert data.

---

## 9. Work plan (what gets built, in order)

| Step | Deliverable | Depends on | Status (2026-09-19) |
|---|---|---|---|
| 1. Cloud foundation | New database tables + cloud services for alerts, delivery tracking, and account linking | — | **Partial:** tables exist (`emergency_alerts`, `emergency_alert_deliveries`, `caregiver_links`, `caregiver_link_requests`, `user_push_tokens`) but phone path doesn't write them yet |
| 2. Backup text messaging | Cloud-based text sending with delivery receipts | Step 1 + Twilio account | **Built, not invoked:** edge function exists, no app caller |
| 3. In-app alerts | Firebase setup, instant notifications to linked SUNDR contacts | Step 1 + Firebase project | **Partial:** token registration + receive/display implemented, dormant without Firebase config |
| 4. Account linking | The "friend request" flow (request → accept → linked) | Step 1 | **Not built** (tables only) |
| 5. Phone-side improvements | Honest delivery tracking on the phone + automatic backup when the phone can't send | Step 2 | **Partial:** receipt ledger + status snapshot done; backup failover pending Step 2 |
| 6. App screens | "Companion requests" screen, alert status messages, location in alerts | Steps 2–5 | **Partial:** `/companion-alert` display screen exists; requests UI pending |
| 7. Testing | End-to-end test: simulate a fall → verify text delivered + in-app alert received | All | Not done |

Each step is tested before moving on, and the whole flow is demonstrated end-to-end before release.

---

## 10. What success looks like

After this work:

- ✅ A possible fall automatically alerts every saved emergency contact (phone SMS path; cloud backup pending Section 9, Step 2).
- ✅ Contacts who use SUNDR get an instant in-app alert (if Firebase is configured and they accepted the link — link UI pending).
- ✅ Every phone text carries a SENT/DELIVERED/unknown receipt — we can show real status, and users see the snapshot.
- ✅ If the wearer's phone can't send, the backup always covers it (as long as the phone has internet at some point). *(Requires Step 2 wiring — not yet true.)*
- ✅ No more silent failures and no more placebo. *(Permission/signal failures now surface as errors in the status snapshot rather than succeeding silently.)*