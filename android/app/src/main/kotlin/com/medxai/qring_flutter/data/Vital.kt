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
    HRV(false),
    TEMPERATURE(false);

    companion object {
        fun fromKey(key: String): Vital? = entries.find { it.name.equals(key, ignoreCase = true) }
    }
}
