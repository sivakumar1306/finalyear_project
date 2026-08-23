package com.sundr.myapp.data

// Shared physiologically-plausible ranges used to reject junk sensor values before
// they reach Room, Supabase, or any analyzer.
//
// Why this exists: StartHeartRateRsp multiplexes several BLE frame types into one class,
// and the ring streams unstable intermediate frames during manual measurements. Without
// a range gate, warm-up spikes / crossed-frame bytes get persisted as real readings
// (observed: implausibly high bpm values in daily averages).
object VitalRanges {
    // Broad enough for real measurements (sleep ~35, hard exercise ~200), narrow enough
    // to drop sentinel bytes (0xFF = 255), SpO2-carrying frames (~95-100 misread as bpm),
    // and warm-up garbage.
    const val HR_MIN_BPM = 30
    const val HR_MAX_BPM = 220

    fun isValidBpm(bpm: Int): Boolean = bpm in HR_MIN_BPM..HR_MAX_BPM
}
