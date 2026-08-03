package com.medxai.sundr.data

enum class Vital(val defaultEnabled: Boolean) {
    HEART_RATE(true),
    SPO2(true),
    // Re-enabled: manual "Measure Now" for stress confirmed working reliably, and the
    // settle-delay fix in MeasurementLoopManager (POST_STOP_SETTLE_MS) means even a
    // timed-out stress measurement can no longer leave the ring stuck mid-measurement.
    STRESS(true),
    BLOOD_PRESSURE(true),
    STEPS(true),
    // Re-enabled (2026-07-09): the earlier "never produced a valid reading" conclusion was
    // wrong — it was a code bug (the manual "Measure Now" timeout was only 60s, and a real
    // reading confirmed via logcat takes ~60.5s on-device). Now uses its own longer timeout
    // in MeasurementLoopManager (HRV_MEASURE_TIMEOUT_MS) so the loop doesn't repeat the
    // same mistake.
    HRV(true),
    // Re-enabled (2026-07-31): the loop's temperature entry previously had no implementation,
    // and the manual path used a file-pull (startObtainTemperatureOnce) that only downloads
    // already-recorded readings. Now both use the SDK's live manualTemperature() API — raw
    // value is °C × 10 — via MeasurementLoopManager.measureTemperature(), so the continuous
    // round-robin can gather temperature readings like every other vital.
    TEMPERATURE(true);

    companion object {
        fun fromKey(key: String): Vital? = entries.find { it.name.equals(key, ignoreCase = true) }
    }
}
