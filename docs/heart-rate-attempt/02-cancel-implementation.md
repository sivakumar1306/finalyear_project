# 02 — Cancel implementation (tap-toggle + disconnect cleanup)

Decisions: second tap cancels · navigating away keeps measuring · stop-before-start allowed.

## Native (`BlePlugin.kt`)

* Session tracking: `manualHrResult` / `manualHrDone` / `manualHrTimeout`
  registered on acquire, cleared on every terminal path via `clearSession()`.
  Late SDK callbacks check `done` first — no double-reply.
* `cancelHeartRate` channel: removes timeout, sends `manualModeHeart(null,true)`,
  releases `"manual"`, completes the original result with `CANCELLED`, replies
  `true` to the cancel caller (`false` when nothing active).
* `abortActiveManualHr("DISCONNECTED", …)`: same termination, called from both
  `disconnect()` and `onDeviceDisconnected()`; original result completes with
  `DISCONNECTED`.
* Reset-first start: best-effort `manualModeHeart(null,true)` + 300ms settle
  before `manualModeHeart(cb,false)` (inside the 8s acquire budget). Cancel
  during the window is honored (start skipped, no double-reply).

## Dart

* `BleService.cancelHeartRate()` → `invokeMethod<bool>('cancelHeartRate')`.
* `_startMeasurement`: tap while `_measuring` → cancel, `_measuring=false`,
  `Cancelled` snackbar. `CANCELLED` / `DISCONNECTED` added to
  `_measureErrorMessage` + `_isExpectedHrError` (local `debugPrint`, never
  `app_incidents`).
* `RealTimeCard`: tap stays enabled while measuring (spinner + `Tap to cancel`
  hint, existing glass tokens only). HR screen passes `enabled: connected`.
* `NotEnoughDataCard`: measure button stays enabled while measuring and reads
  `Cancel measurement`, so the empty-state screen can also cancel.

## Verify on device

* Tap → tap again: LED off, `Cancelled` snackbar, `logcat -s BlePlugin:D`
  shows no further frames; immediate re-tap succeeds (no `BUSY`).
* Disconnect mid-measure: `DISCONNECTED` snackbar prompt, `currentOwner()==null`,
  next tap after reconnect works.
* `measurement_attempt` shows no false `success` for cancelled sessions.
