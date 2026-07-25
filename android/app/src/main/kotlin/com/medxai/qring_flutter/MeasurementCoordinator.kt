package com.medxai.qring_flutter

import java.util.concurrent.atomic.AtomicReference

// Shared lock between MeasurementLoopManager and WorkoutService so they never both hold
// the single BLE connection's manual-mode measurement slot at the same time.
object MeasurementCoordinator {
    @Volatile
    var isWorkoutActive: Boolean = false

    @Volatile
    var manualRequestPending: Boolean = false

    private val busyOwner = AtomicReference<String?>(null)

    fun tryAcquire(owner: String): Boolean = busyOwner.compareAndSet(null, owner)

    fun release(owner: String) {
        busyOwner.compareAndSet(owner, null)
    }
}
