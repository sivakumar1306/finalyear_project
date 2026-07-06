package com.medxai.qring_flutter.data

enum class Vital(val defaultEnabled: Boolean) {
    HEART_RATE(true),
    SPO2(true),
    // Temporarily disabled: consistently failed to get a valid reading in testing (0/2
    // completed cycles, ring worn) and may have contributed to a ring getting stuck
    // mid-measurement. Schema/hooks stay ready — flip via setVitalEnabled once root-caused.
    STRESS(false),
    BLOOD_PRESSURE(true),
    STEPS(true),
    HRV(false),
    TEMPERATURE(false);

    companion object {
        fun fromKey(key: String): Vital? = entries.find { it.name.equals(key, ignoreCase = true) }
    }
}
