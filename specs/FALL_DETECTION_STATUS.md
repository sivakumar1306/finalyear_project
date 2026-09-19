# Fall Detection Feature — Status

Last updated: 2026-07-07

## Background

Client shared a feature scope document (`FS-FD-001`, "Predictive and Active Fall Detection") specifying
a 2-week build assuming the ring SDK exposes raw accelerometer, gyroscope, EDA, and perfusion-index data
continuously over BLE. This was verified against the actual shipped SDK
(`android/app/libs/qring_sdk_1.0.0.50.aar`, package `com.oudmon.ble.*`) by decompiling it — none of those
signals are exposed as a continuous stream. The one exception: the SDK's manual raw-data heart-rate/SpO2
capture mode (`manualModeHeartRateRawData`) bundles accelerometer X/Y/Z alongside raw PPG, but only during
a short, manually-triggered diagnostic session, not a background feed.

Agreed counter-proposal with the client:
- Fall risk score (prediction) is scoped as a **syncope/cardiovascular pre-fall signal**, not a general
  fall predictor — mechanical trip-and-fall has no physiological prodrome, so no vitals-only engine can
  catch it.
- Active detection uses the **phone's** accelerometer (ring's isn't available continuously), corroborated
  by a concurrent vitals spike instead of a second accelerometer.
- No auto-dial to emergency contacts or 112 at this stage — client explicitly said "after the fall" is a
  sub-feature, not the focus, and wants prediction developed properly rather than skipped.
- Everything computes and logs silently before anything becomes a live, user-facing alert — so the
  false-positive rate can be measured on real data first.

## Done

- **Phase 1 — Fall Risk Score engine** (`FallRiskAnalyzer.kt`): computes a 0-100 score from heart rate,
  SpO2, blood pressure, stress, and HRV (if available) every time a real vital reading is saved. SpO2 < 88
  is an immediate critical override. Logs every computation silently (`fall_risk_log` table) — does not
  alert on its own yet.
- **Phase 2 — Active motion detection** (`FallMotionDetector.kt`): phone accelerometer + gyroscope
  three-phase detector (free-fall → impact → stillness), running inside the existing BLE foreground
  service rather than a new one. Requires corroboration from a concurrent vitals spike before being
  treated as a real fall — logs every candidate either way (`fall_event` table).
  - Found and fixed a real bug during on-device testing: g-unit thresholds were being compared against
    raw m/s² values, making the effective impact threshold ~10x too sensitive and causing false positives
    on ordinary walking. Fixed, plus added a genuine minimum free-fall duration and made post-impact
    stillness mandatory (previously bypassable by a gyroscope spike alone).
  - Validated on a real device: genuine drop test correctly detected (76% confidence); false positives
    from running/jumping/speed-walking dropped substantially after the fix.
- **Phase 3 — Local alert** (`FallAlertNotifier.kt`): fires a real Android notification, only on a
  corroborated event. "I'm okay" action dismisses it. No full-screen overlay, no caregiver push, no
  auto-dial yet.
- **UI** (`lib/screens/settings/fall_detection_screen.dart`): shows the real computed risk score (not a
  placeholder/demo calculation), a real fall-event history view, and emergency contacts persisted natively
  (Room database, not just in the Flutter app's memory) so a future notification/call action can read them.
- Debug tooling to test all of the above without needing a real fall or a lucky vitals spike: simulate a
  fall notification, and simulate a real vitals reading to confirm the risk-score engine computes and logs
  correctly end to end (confirmed working — produces the real "You might fall soon" alert).

## Not done yet

- **Battery impact measurement** — the phone's accelerometer/gyroscope now run continuously; needs a real
  multi-hour comparison against normal usage, not just a code review.
- **Caregiver push notification** — needs a decision: Firebase Cloud Messaging (needs a Firebase
  account/project) vs. building on the existing Supabase backend already used for vitals sync.
- **Ring-side motion corroboration** — exploratory idea to trigger the SDK's raw-data capture mode for a
  few seconds when the phone detects a fall-shaped impact, to get genuine ring motion data instead of
  relying on the phone alone. Untried — unknown real sample rate/reliability.
- **Validating the risk score against real events** — the actual test of whether the prediction hypothesis
  holds. Needs real-world wear time and real (or near-miss) fall reports to check against the logged
  scores. This is a waiting-and-analyzing step, not something to build.
