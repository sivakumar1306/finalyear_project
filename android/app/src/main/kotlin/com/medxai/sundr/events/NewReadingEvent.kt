package com.medxai.qring_flutter.events

import com.medxai.qring_flutter.data.Vital

// Posted on the app-wide greenrobot EventBus (org.greenrobot:eventbus, already a Gradle
// dependency but unused before this) after a reading has been persisted to Room. Consumers
// (e.g. a future fall-detection analyzer) can always safely re-query the DB for readingId,
// since persistence always happens before this event is published.
data class NewReadingEvent(
    val vital: Vital,
    val readingId: Long,
    val cycleId: Long,
    val measuredAt: Long,
    val primaryValue: Double?
)
