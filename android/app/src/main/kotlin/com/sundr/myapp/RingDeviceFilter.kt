package com.sundr.myapp

/**
 * Keep in sync with lib/utils/ring_names.dart.
 * A bare "R" prefix also matches headphones, so only multi-character ring
 * prefixes are accepted, and known audio-product names are rejected.
 */
object RingDeviceFilter {
    private val prefixes = listOf(
        "R02", "R03", "R05", "R06", "R08", "R09", "R10", "R11", "R12",
        "R20", "R21", "R3L", "Q_", "O_", "QC", "T80", "T90", "T91", "T93",
        "T95", "TW68", "S9", "C60", "C66", "C67", "C68", "C80", "C86",
        "C88", "C96", "WXB_W4", "WA", "SUNDR",
    )

    private val audioFragments = listOf(
        "bud", "headphone", "headset", "airpod", "earpod", "earbud", "tws",
        "freebud", "qcy", "realme", "redmi", "oneplus", "galaxy", "sony",
        "jbl", "boat", "soundcore", "nothing", "wh-", "wf-", "beats", "bose",
        "sennheiser", "anker", "rockerz", "pixel bud",
    )

    fun isRingName(name: String?): Boolean {
        val trimmed = name?.trim().orEmpty()
        if (trimmed.isEmpty()) return false
        val lower = trimmed.lowercase()
        if (audioFragments.any { lower.contains(it) }) return false
        val upper = trimmed.uppercase()
        return prefixes.any { upper.startsWith(it) }
    }
}
