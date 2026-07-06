package com.medxai.qring_flutter.data

enum class Vital(val defaultEnabled: Boolean) {
    HEART_RATE(true),
    SPO2(true),
    // Re-enabled: manual "Measure Now" for stress confirmed working reliably, and the
    // settle-delay fix in MeasurementLoopManager (POST_STOP_SETTLE_MS) means even a
    // timed-out stress measurement can no longer leave the ring stuck mid-measurement.
    STRESS(true),
    BLOOD_PRESSURE(true),
    STEPS(true),
    // Disabled again: even after fixing the getHrv()-vs-getValue() field bug, HRV still
    // never produced a valid reading in testing (confirmed via the manual "Measure Now"
    // button too, not just the loop) — points to a genuine SDK/ring-side limitation
    // rather than a code bug. Schema/hooks stay ready for whenever that's resolved.
    HRV(false),
    TEMPERATURE(false);

    companion object {
        fun fromKey(key: String): Vital? = entries.find { it.name.equals(key, ignoreCase = true) }
    }
}
