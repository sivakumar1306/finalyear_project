# SUNDR Emergency Alert System — Plain-English Overview

**Audience:** clients, product owners, non-technical reviewers.
**Purpose:** explain what the emergency alert feature does today, what is wrong with it, and what we propose to build — in everyday language, no code.

---

## 1. What the feature is supposed to do

When someone wearing a SUNDR ring has a problem — for example the ring detects a possible fall — SUNDR should quickly tell the people who can help:

1. The **emergency contacts** the wearer saved in the app.
2. Those contacts should hear about it **instantly**, in a way they cannot miss.

That's the whole point: a senior or at-risk person takes a fall, and the right people get the alert automatically.

---

## 2. What happens today — and why it isn't good enough

Today, the app can send a **text message (SMS)** to the saved emergency contacts using the wearer's own phone. Here's the honest picture:

| Aspect | Today |
|---|---|
| SMS to saved contacts | Works, but only on the wearer's own phone |
| Can we confirm the SMS arrived? | **No.** The app sends it and hopes. There is no "message delivered" proof. |
| If the phone's SMS permission is off | The alert silently fails — nobody gets it |
| If the wearer's phone has no signal | The alert silently fails — nobody gets it |
| A contact who also uses SUNDR | Gets nothing special — no in-app alert |
| Proof of delivery (audit trail) | None |

**The problem in one sentence:** today the emergency SMS is "fire and forget" — we launch it and hope it lands, with no way to know, and several ways for it to fail silently. That's a placebo, and for an emergency feature that is not acceptable.

---

## 3. What we propose to build — the three-part alert system

We want to turn the current one-channel, unverifiable system into a **three-part system** that is dependable and provable:

```
A possible fall is detected on the ring
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

- If the phone is completely offline, the alert is saved and **kept trying automatically** until the phone is back online.
- Every text gets a **delivery receipt** — the provider tells us "delivered" or "failed", and we record it.

### Part 3 — In-app alert to contacts who use SUNDR (instant, free)
If a saved emergency contact is **also a SUNDR user** (and the two accounts are linked, see Section 4), they get an **instant app notification** — a loud pop-up on their phone — even if the SUNDR app is closed at the time. The alert shows who needs help, what happened, and a **live map location**.

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

Today the message is a generic sentence with no useful details. We propose:

> **"Sarah — possible fall detected.** Please check on me. My live location: [map link] — Sent by SUNDR"

- The wearer's **name**
- The **reason** (possible fall, fall prediction, or manual alert)
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
- Alerts now show **honest status**: "Text delivered to 2 contacts (1 via phone, 1 via backup)" instead of the current optimistic "SMS sent".

---

## 8. Safety and privacy

- **No sensitive health data** is put in text messages or alerts — just name, reason, and location link.
- **Two-sided consent** for in-app alerts (Section 4) — nobody is tracked without agreeing.
- Every alert is **logged** (who was notified, how, and whether it was delivered) so we can prove the system worked — and investigate if it didn't.
- Your existing account-deletion feature will also wipe the new alert data.

---

## 9. Work plan (what gets built, in order)

| Step | Deliverable | Depends on |
|---|---|---|
| 1. Cloud foundation | New database tables + cloud services for alerts, delivery tracking, and account linking | — |
| 2. Backup text messaging | Cloud-based text sending with delivery receipts | Step 1 + Twilio account |
| 3. In-app alerts | Firebase setup, instant notifications to linked SUNDR contacts | Step 1 + Firebase project |
| 4. Account linking | The "friend request" flow (request → accept → linked) | Step 1 |
| 5. Phone-side improvements | Honest delivery tracking on the phone + automatic backup when the phone can't send | Step 2 |
| 6. App screens | "Companion requests" screen, alert status messages, location in alerts | Steps 2–5 |
| 7. Testing | End-to-end test: simulate a fall → verify text delivered + in-app alert received | All |

Each step is tested before moving on, and the whole flow is demonstrated end-to-end before release.

---

## 10. What success looks like

After this work:

- ✅ A possible fall automatically alerts every saved emergency contact.
- ✅ Contacts who use SUNDR get an instant in-app alert (if they accepted the link).
- ✅ Every text has a delivery receipt — we can prove it arrived, and users see the real status.
- ✅ If the wearer's phone can't send, the backup always covers it (as long as the phone has internet at some point).
- ✅ No more silent failures and no more placebo.