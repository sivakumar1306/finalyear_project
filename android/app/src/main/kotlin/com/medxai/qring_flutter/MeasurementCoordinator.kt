package com.medxai.qring_flutter

import java.util.concurrent.atomic.AtomicReference

// Shared lock between MeasurementLoopManager, WorkoutService, and manual ("Measure Now")
// measurements from BlePlugin so none of them ever hold the single BLE connection's
// manual-mode measurement slot at the same time.
object MeasurementCoordinator {
    @Volatile
    var isWorkoutActive: Boolean = false

    // Set by BlePlugin right before it starts trying to acquire the slot for a manual
    // measurement, cleared once it either acquires the slot or gives up (BUSY).
    // MeasurementLoopManager polls this so it can abort its current vital and yield the
    // ring to the manual measurement instead of running to its own timeout.
    @Volatile
    var manualRequestPending: Boolean = false

    private val busyOwner = AtomicReference<String?>(null)

    fun tryAcquire(owner: String): Boolean = busyOwner.compareAndSet(null, owner)

    fun release(owner: String) {
        busyOwner.compareAndSet(owner, null)
    }

    // Lets MeasurementLoopManager check whether someone other than itself already holds the
    // slot (e.g. manual measurement) before starting a brand-new cycle.
    fun currentOwner(): String? = busyOwner.get()
}