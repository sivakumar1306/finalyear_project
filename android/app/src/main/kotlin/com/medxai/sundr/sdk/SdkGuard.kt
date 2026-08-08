package com.medxai.sundr.sdk

import android.util.Log
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

/**
 * Safe choke-point for vendor BLE SDK calls. Never throws to callers.
 * Opens a circuit after repeated failures so reconnect/measure storms back off.
 */
object SdkGuard {
    private const val TAG = "SdkGuard"
    private const val FAIL_THRESHOLD = 8
    private const val WINDOW_MS = 60_000L
    private const val OPEN_MS = 45_000L

    private val failCount = AtomicInteger(0)
    private val windowStartMs = AtomicLong(0L)
    private val openUntilMs = AtomicLong(0L)

    fun isOpen(): Boolean = System.currentTimeMillis() < openUntilMs.get()

    fun remainingOpenMs(): Long =
        (openUntilMs.get() - System.currentTimeMillis()).coerceAtLeast(0L)

    fun run(tag: String, block: () -> Unit) {
        run(tag, Unit, block)
    }

    fun <T> run(tag: String, default: T, block: () -> T): T {
        if (isOpen()) {
            Log.w(TAG, "circuit open — skip $tag (${remainingOpenMs()}ms left)")
            return default
        }
        return try {
            block()
        } catch (t: Throwable) {
            recordFailure(tag, t)
            default
        }
    }

    fun runCatching(tag: String, block: () -> Unit): Boolean {
        if (isOpen()) {
            Log.w(TAG, "circuit open — skip $tag")
            return false
        }
        return try {
            block()
            true
        } catch (t: Throwable) {
            recordFailure(tag, t)
            false
        }
    }

    fun recordSuccess() {
        // Slow decay so a healthy period clears the breaker.
        val c = failCount.get()
        if (c > 0) failCount.compareAndSet(c, c - 1)
    }

    fun forceOpen(reason: String) {
        openUntilMs.set(System.currentTimeMillis() + OPEN_MS)
        Log.e(TAG, "circuit forced open: $reason for ${OPEN_MS}ms")
    }

    fun reset() {
        failCount.set(0)
        windowStartMs.set(0L)
        openUntilMs.set(0L)
        Log.i(TAG, "circuit reset")
    }

    private fun recordFailure(tag: String, t: Throwable) {
        Log.e(TAG, "SDK call failed: $tag", t)
        CrashStore.record("sdk_guard:$tag", t)

        val now = System.currentTimeMillis()
        val start = windowStartMs.get()
        if (start == 0L || now - start > WINDOW_MS) {
            windowStartMs.set(now)
            failCount.set(1)
            return
        }
        val n = failCount.incrementAndGet()
        if (n >= FAIL_THRESHOLD) {
            openUntilMs.set(now + OPEN_MS)
            failCount.set(0)
            windowStartMs.set(0L)
            Log.e(TAG, "circuit OPEN after $n failures in window (last=$tag)")
            BleSdkLifecycle.requestSoftReset("circuit_open:$tag")
        }
    }
}
