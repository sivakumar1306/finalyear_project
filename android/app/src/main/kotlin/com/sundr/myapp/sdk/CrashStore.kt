package com.sundr.myapp.sdk

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.util.concurrent.atomic.AtomicReference

/**
 * Persists the last native crash / SDK failure so Flutter can report it after relaunch.
 */
object CrashStore {
    private const val TAG = "CrashStore"
    private const val FILE_NAME = "crash_last.json"

    private val appContext = AtomicReference<Context?>(null)

    fun init(context: Context) {
        appContext.set(context.applicationContext)
    }

    fun record(source: String, throwable: Throwable) {
        record(
            source = source,
            message = throwable.message ?: throwable.javaClass.name,
            stack = throwable.stackTraceToString(),
            errorType = throwable.javaClass.name
        )
    }

    fun record(
        source: String,
        message: String,
        stack: String? = null,
        errorType: String = "Throwable"
    ) {
        val ctx = appContext.get() ?: return
        try {
            val json = JSONObject()
                .put("source", source)
                .put("error_type", errorType)
                .put("message", message.take(2000))
                .put("stack_trace", stack?.take(8000))
                .put("timestamp_ms", System.currentTimeMillis())
            file(ctx).writeText(json.toString())
        } catch (e: Exception) {
            Log.w(TAG, "failed to write crash store", e)
        }
    }

    /** Returns last crash as a map, or null. Does not delete. */
    fun peek(): Map<String, Any?>? {
        val ctx = appContext.get() ?: return null
        return try {
            val f = file(ctx)
            if (!f.exists()) return null
            val o = JSONObject(f.readText())
            mapOf(
                "source" to o.optString("source"),
                "error_type" to o.optString("error_type"),
                "message" to o.optString("message"),
                "stack_trace" to o.optString("stack_trace"),
                "timestamp_ms" to o.optLong("timestamp_ms")
            )
        } catch (e: Exception) {
            Log.w(TAG, "failed to read crash store", e)
            null
        }
    }

    fun clear() {
        val ctx = appContext.get() ?: return
        try {
            file(ctx).delete()
        } catch (_: Exception) {
        }
    }

    private fun file(ctx: Context): File = File(ctx.filesDir, FILE_NAME)
}
