package com.medxai.sundr.sdk

import android.app.Application
import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.oudmon.ble.base.bluetooth.BleOperateManager
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Single serialized init/reset gate for BleOperateManager.
 * Application / Service / Plugin must use this instead of calling init() ad hoc.
 */
object BleSdkLifecycle {
    private const val TAG = "BleSdkLifecycle"
    private const val RESET_COOLDOWN_MS = 20_000L

    private val initialized = AtomicBoolean(false)
    private val resetting = AtomicBoolean(false)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var app: Application? = null
    private var lastResetMs = 0L

    fun ensureInitialized(context: Context) {
        val application = context.applicationContext as? Application ?: return
        app = application
        if (initialized.get()) return
        synchronized(this) {
            if (initialized.get()) return
            SdkGuard.run("BleSdkLifecycle.init") {
                BleOperateManager.getInstance(application)
                BleOperateManager.getInstance().init()
                BleOperateManager.getInstance().isBleLogEnabled =
                    (application.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
                initialized.set(true)
                SdkGuard.recordSuccess()
                Log.i(TAG, "BleOperateManager initialized")
            }
        }
    }

    fun isInitialized(): Boolean = initialized.get()

    fun isConnected(): Boolean =
        SdkGuard.run("BleSdkLifecycle.isConnected", false) {
            BleOperateManager.getInstance().isConnected
        }

    fun connectDirectly(address: String) {
        if (SdkGuard.isOpen()) return
        ensureInitialized(app ?: return)
        SdkGuard.run("BleSdkLifecycle.connectDirectly") {
            BleOperateManager.getInstance().connectDirectly(address)
            SdkGuard.recordSuccess()
        }
    }

    fun disconnect() {
        SdkGuard.run("BleSdkLifecycle.disconnect") {
            BleOperateManager.getInstance().disconnect()
        }
    }

    fun unBindDevice() {
        SdkGuard.run("BleSdkLifecycle.unBindDevice") {
            BleOperateManager.getInstance().unBindDevice()
        }
    }

    /**
     * Soft reset: disconnect, re-init manager. Rate-limited.
     * Safe to call from any thread.
     */
    fun requestSoftReset(reason: String) {
        val now = System.currentTimeMillis()
        if (now - lastResetMs < RESET_COOLDOWN_MS) {
            Log.w(TAG, "softReset skipped (cooldown): $reason")
            return
        }
        if (!resetting.compareAndSet(false, true)) {
            Log.w(TAG, "softReset already in progress: $reason")
            return
        }
        lastResetMs = now
        Log.w(TAG, "softReset requested: $reason")
        CrashStore.record(
            source = "sdk_reset",
            message = reason,
            errorType = "SoftReset"
        )
        mainHandler.post {
            try {
                doSoftReset(reason)
            } finally {
                resetting.set(false)
            }
        }
    }

    private fun doSoftReset(reason: String) {
        val application = app ?: return
        SdkGuard.run("BleSdkLifecycle.softReset.disconnect") {
            try {
                BleOperateManager.getInstance().disconnect()
            } catch (_: Exception) {
            }
        }
        initialized.set(false)
        SdkGuard.reset()
        SdkGuard.run("BleSdkLifecycle.softReset.reinit") {
            BleOperateManager.getInstance(application)
            BleOperateManager.getInstance().init()
            BleOperateManager.getInstance().isBleLogEnabled =
                (application.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
            initialized.set(true)
            Log.i(TAG, "softReset complete ($reason)")
        }
    }
}
