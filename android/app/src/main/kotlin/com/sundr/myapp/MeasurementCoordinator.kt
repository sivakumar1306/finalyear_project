package com.sundr.myapp

import android.util.Log
import java.util.concurrent.atomic.AtomicLong
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

    // Passive ring reads (getToday*/get*/lists) share the vendor SDK with active
    // measurements, which own a single response slot — a read issued while a
    // measurement is in flight can collide inside the SDK (observed as a fatal
    // NPE in BleOperateManager internals). Reads therefore take the same slot
    // under owner "read". Stale-expiring: a lost SDK callback must never wedge
    // sync forever, so an unreleased read lock older than READ_LOCK_TIMEOUT_MS
    // (longer than any read's native timeout) can be reclaimed.
    private const val READ_OWNER = "read"
    private const val READ_LOCK_TIMEOUT_MS = 45_000L
    private val readAcquiredAt = AtomicLong(0L)

    fun tryAcquireRead(): Boolean {
        if (busyOwner.compareAndSet(null, READ_OWNER)) {
            readAcquiredAt.set(System.currentTimeMillis())
            return true
        }
        if (busyOwner.get() == READ_OWNER &&
            System.currentTimeMillis() - readAcquiredAt.get() > READ_LOCK_TIMEOUT_MS &&
            busyOwner.compareAndSet(READ_OWNER, null)
        ) {
            Log.w("MeasurementCoordinator", "read lock expired without release — reclaiming")
            if (busyOwner.compareAndSet(null, READ_OWNER)) {
                readAcquiredAt.set(System.currentTimeMillis())
                return true
            }
        }
        return false
    }

    fun releaseRead() {
        busyOwner.compareAndSet(READ_OWNER, null)
    }
}