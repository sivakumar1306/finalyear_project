package com.sundr.myapp.analysis

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.SystemClock
import com.google.gson.Gson
import com.sundr.myapp.data.FallEventEntity
import com.sundr.myapp.data.ReadingRepository
import kotlinx.coroutines.launch
import org.greenrobot.eventbus.EventBus
import org.greenrobot.eventbus.Subscribe
import org.greenrobot.eventbus.ThreadMode
import com.sundr.myapp.events.RiskTierChangeEvent
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Phase 2 of the fall-risk feature: phone-accelerometer three-phase fall signature
 * (free-fall -> impact -> post-impact stillness), corroborated against a concurrent vitals
 * spike before being logged. Started/stopped from BleConnectionService — piggybacks on the
 * foreground service that's already fighting OEM battery killers rather than starting a
 * second one, which the source doc (FS-FD-001) correctly flags as the costliest mistake.
 *
 * Ring accelerometer is not available continuously on this SDK (see the FS-FD-001
 * counter-proposal) — this is phone-only. A candidate event is logged, not alerted, same
 * silent-first approach as FallRiskAnalyzer: the false-positive rate needs measuring on real
 * data before anything user-facing ships.
 */
object FallMotionDetector : SensorEventListener {

    private const val WINDOW_SECONDS = 2.0f
    private const val SAMPLE_RATE_HZ = 50f
    private const val ANALYSIS_INTERVAL_MS = 200L
    private const val COOLDOWN_MS = 8_000L
    // Battery: a stuck HIGH tier must not keep 50Hz accel+gyro on forever.
    // Auto-stop after 10 min; the next fresh HIGH event re-arms (duty cycles).
    private const val SENSOR_AUTO_OFF_MS = 10 * 60 * 1000L

    private const val GRAVITY = 9.81f

    // All thresholds below are in g-units (multiples of GRAVITY) — magnitudes are converted
    // to g before comparison. A prior version compared these directly against raw m/s²
    // deviations, making the effective impact threshold ~0.3g instead of 3.0g — trivially
    // tripped by ordinary walking. Fixed here.
    private const val FREE_FALL_G = 0.4f
    private const val IMPACT_G = 3.0f
    private const val STILLNESS_DEVIATION_G = 0.35f
    private const val STILLNESS_SAMPLE_RATIO = 0.35f
    private const val GYRO_SPIKE_RAD_S = 4.0f
    private const val MIN_CONFIDENCE = 0.55f

    // Phase I must hold for at least this many contiguous samples (~80ms @ 50Hz) — a single
    // low sample is noise, not a genuine free-fall. Phase II (impact) must follow within this
    // many samples after Phase I ends (~500ms), matching the doc's timing spec.
    private val FREE_FALL_MIN_SAMPLES = (0.08f * SAMPLE_RATE_HZ).toInt().coerceAtLeast(2)
    private val IMPACT_WINDOW_SAMPLES = (0.5f * SAMPLE_RATE_HZ).toInt()

    // Vitals-spike corroboration window either side of the motion event.
    private const val CORROBORATION_WINDOW_MS = 30_000L

    private val gson = Gson()
    private val capacity = max(16, (WINDOW_SECONDS * SAMPLE_RATE_HZ).toInt())
    private var accelX = FloatArray(capacity)
    private var accelY = FloatArray(capacity)
    private var accelZ = FloatArray(capacity)
    private var gyroX = FloatArray(capacity)
    private var gyroY = FloatArray(capacity)
    private var gyroZ = FloatArray(capacity)
    private var writeIndex = 0
    private var filled = 0

    private var lastGyro = floatArrayOf(0f, 0f, 0f)
    private var hasGyro = false
    private var lastAnalysisMs = 0L
    private var lastEventMs = 0L
    private var active = false
    private var sensorsActive = false

    private var sensorManager: SensorManager? = null
    private var repository: ReadingRepository? = null
    private var appContext: Context? = null
    private var sensorsStartedAtMs = 0L

    // Read-only monitoring snapshot for the Flutter Layer 3 motion model.
    // In-memory only (lost on process restart — the Room fall_event table is
    // the durable source); exposed via BlePlugin.getMotionSnapshot so Dart can
    // distinguish "monitored, quiet" from "never monitored".
    @Volatile private var windowsAnalyzed = 0L
    @Volatile private var maxMagnitudeGSeen = 0f
    @Volatile private var monitoringSinceMs = 0L
    @Volatile private var lastPeakG: Float? = null
    @Volatile private var lastPeakGyro: Float? = null
    @Volatile private var lastStillnessRatio: Float? = null
    @Volatile private var lastDetectionAtMs = 0L

    /** Point-in-time monitoring state; safe to call from any thread. */
    fun snapshot(): Map<String, Any?> = mapOf(
        "sensorsActive" to sensorsActive,
        "windowsAnalyzed" to windowsAnalyzed,
        "maxMagnitudeG" to maxMagnitudeGSeen,
        "monitoringSinceMs" to monitoringSinceMs,
        "lastPeakG" to lastPeakG,
        "lastPeakGyro" to lastPeakGyro,
        "lastStillnessRatio" to lastStillnessRatio,
        "lastDetectionAtMs" to lastDetectionAtMs,
        "nowMs" to System.currentTimeMillis(),
    )

    fun start(context: Context) {
        if (active) return
        val appCtx = context.applicationContext
        appContext = appCtx
        sensorManager = appCtx.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        repository = ReadingRepository.getInstance(appCtx)
        active = true
        EventBus.getDefault().register(this)
    }

    fun stop() {
        if (!active) return
        active = false
        EventBus.getDefault().unregister(this)
        stopSensors()
        sensorManager = null
        repository = null
        appContext = null
    }

    @Subscribe(threadMode = ThreadMode.MAIN)
    fun onRiskTierChange(event: RiskTierChangeEvent) {
        if (!active) return
        if (event.tier == "HIGH" || event.tier == "CRITICAL" || event.tier == "OVERRIDE") {
            startSensors()
        } else {
            stopSensors()
        }
    }

    private fun startSensors() {
        if (sensorsActive) return
        val sm = sensorManager ?: return
        val accelerometer = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: return
        val gyroscope = sm.getDefaultSensor(Sensor.TYPE_GYROSCOPE)

        sensorsActive = true
        sensorsStartedAtMs = SystemClock.elapsedRealtime()
        monitoringSinceMs = System.currentTimeMillis()
        windowsAnalyzed = 0L
        maxMagnitudeGSeen = 0f
        // Use 50Hz (20,000us) sampling with 5s (5,000,000us) batching latency to allow the CPU to sleep
        val samplingPeriodUs = 20_000
        val maxReportLatencyUs = 5_000_000
        sm.registerListener(this, accelerometer, samplingPeriodUs, maxReportLatencyUs)
        gyroscope?.let { sm.registerListener(this, it, samplingPeriodUs, maxReportLatencyUs) }
    }

    private fun stopSensors() {
        if (!sensorsActive) return
        sensorsActive = false
        sensorsStartedAtMs = 0L
        sensorManager?.unregisterListener(this)
        writeIndex = 0
        filled = 0
        hasGyro = false
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    override fun onSensorChanged(event: SensorEvent) {
        try {
            when (event.sensor.type) {
                Sensor.TYPE_GYROSCOPE -> {
                    if (event.values.size < 3) return
                    lastGyro = floatArrayOf(event.values[0], event.values[1], event.values[2])
                    hasGyro = true
                }
                Sensor.TYPE_ACCELEROMETER -> appendSample(event.values, event.timestamp)
            }
        } catch (_: Exception) {
            // Sensor callbacks must never crash the process.
        }
    }

    private fun appendSample(accel: FloatArray, timestampNanos: Long) {
        if (accel.size < 3 || capacity <= 0) return
        // Battery: stuck-HIGH auto-off — stop even without a tier-drop event.
        if (sensorsActive && sensorsStartedAtMs > 0 &&
            SystemClock.elapsedRealtime() - sensorsStartedAtMs >= SENSOR_AUTO_OFF_MS
        ) {
            stopSensors()
            return
        }
        val idx = writeIndex
        if (idx !in 0 until capacity) return
        accelX[idx] = accel[0]
        accelY[idx] = accel[1]
        accelZ[idx] = accel[2]
        if (hasGyro) {
            gyroX[idx] = lastGyro[0]; gyroY[idx] = lastGyro[1]; gyroZ[idx] = lastGyro[2]
        } else {
            gyroX[idx] = 0f; gyroY[idx] = 0f; gyroZ[idx] = 0f
        }
        writeIndex = (writeIndex + 1) % capacity
        filled = minOf(filled + 1, capacity)

        // timestampNanos is in nanoseconds since boot; convert to milliseconds
        val now = timestampNanos / 1_000_000L
        if (filled < capacity) return
        if (now - lastAnalysisMs < ANALYSIS_INTERVAL_MS) return
        lastAnalysisMs = now
        try {
            analyzeWindow(now)
        } catch (_: Exception) {
        }
    }

    private fun analyzeWindow(nowMs: Long) {
        if (nowMs - lastEventMs < COOLDOWN_MS) return
        val repo = repository ?: return

        val n = capacity
        // Magnitudes are converted to g-units immediately so every threshold below compares
        // like with like — see the constants' kdoc for why this matters.
        val magnitudesG = FloatArray(n) { i ->
            val src = (writeIndex + i) % n
            sqrt(accelX[src] * accelX[src] + accelY[src] * accelY[src] + accelZ[src] * accelZ[src]) / GRAVITY
        }
        windowsAnalyzed++
        for (i in 0 until n) {
            if (magnitudesG[i] > maxMagnitudeGSeen) maxMagnitudeGSeen = magnitudesG[i]
        }
        val gyroMagnitudes = FloatArray(n) { i ->
            val src = (writeIndex + i) % n
            sqrt(gyroX[src] * gyroX[src] + gyroY[src] * gyroY[src] + gyroZ[src] * gyroZ[src])
        }

        // Phase I — longest contiguous run of near-weightlessness. A single low sample is
        // sensor noise; walking/running rarely produce a sustained dip, which is exactly the
        // point of requiring one.
        var runStart = -1
        var runLen = 0
        var bestStart = -1
        var bestLen = 0
        for (i in 0 until n) {
            if (magnitudesG[i] < FREE_FALL_G) {
                if (runStart == -1) runStart = i
                runLen++
                if (runLen > bestLen) {
                    bestLen = runLen
                    bestStart = runStart
                }
            } else {
                runStart = -1
                runLen = 0
            }
        }
        if (bestLen < FREE_FALL_MIN_SAMPLES) return // no genuine free-fall phase this window

        // Phase II — impact peak must follow shortly after the free-fall run ends.
        val freeFallEnd = bestStart + bestLen
        val impactSearchEnd = (freeFallEnd + IMPACT_WINDOW_SAMPLES).coerceAtMost(n)
        var peakIndex = -1
        var peakG = 0f
        for (i in freeFallEnd until impactSearchEnd) {
            if (magnitudesG[i] > peakG) {
                peakG = magnitudesG[i]
                peakIndex = i
            }
        }
        if (peakIndex == -1 || peakG < IMPACT_G) return // no impact within the timing window

        val peakGyro = gyroMagnitudes[peakIndex]
        val gyroSpike = peakGyro >= GYRO_SPIKE_RAD_S

        // Phase III — post-impact stillness is mandatory, not optional. This is the single
        // biggest differentiator from running/jumping, which never truly go still afterward.
        val postStart = (peakIndex + 1).coerceAtMost(n - 1)
        val postCount = n - postStart
        var stillCount = 0
        for (i in postStart until n) {
            if (abs(magnitudesG[i] - 1f) <= STILLNESS_DEVIATION_G) stillCount++
        }
        val stillnessRatio = if (postCount > 0) stillCount.toFloat() / postCount else 0f
        if (stillnessRatio < STILLNESS_SAMPLE_RATIO) return

        val confidence = (
            (bestLen.toFloat() / (FREE_FALL_MIN_SAMPLES * 2)).coerceIn(0f, 1f) * 0.30f +
                (peakG / (IMPACT_G * 1.5f)).coerceIn(0f, 1f) * 0.35f +
                (if (gyroSpike) (peakGyro / (GYRO_SPIKE_RAD_S * 1.5f)).coerceIn(0f, 1f) else 0.3f) * 0.10f +
                stillnessRatio.coerceIn(0f, 1f) * 0.25f
            ).coerceIn(0f, 1f)

        if (confidence < MIN_CONFIDENCE) return

        lastEventMs = nowMs
        val detectedAtMs = System.currentTimeMillis()
        lastPeakG = peakG
        lastPeakGyro = peakGyro
        lastStillnessRatio = stillnessRatio
        lastDetectionAtMs = detectedAtMs

        repo.ioScope.launch {
            val (corroborated, source) = checkVitalsCorroboration(detectedAtMs, repo)
            repo.insertFallEvent(
                FallEventEntity(
                    confidence = confidence,
                    corroborated = corroborated,
                    corroborationSource = source,
                    metadataJson = gson.toJson(
                        mapOf(
                            "peakG" to peakG,
                            "peakGyro" to peakGyro,
                            "stillnessRatio" to stillnessRatio,
                        )
                    ),
                    detectedAt = detectedAtMs,
                )
            )
            // Only ever notify on a corroborated event — a lone phone-motion spike must
            // never surface as a fall alert on its own.
            if (corroborated) {
                appContext?.let {
                    // Android 16 promoted live update — the algorithm itself pins the
                    // emergency to the lock screen / status-bar chip for the duration.
                    // EmergencySmsSender ticks the countdown on it every second.
                    val skipStandard = SafetyLiveUpdate.showFall(
                        it,
                        (confidence * 100).toInt(),
                        EmergencySmsSender.COUNTDOWN_SECONDS,
                        EmergencyAutoCaller.isEnabled(it),
                    )
                    if (!skipStandard) {
                        FallAlertNotifier.notifyFall(it, confidence, source)
                    }
                    // Auto-SMS to all emergency contacts after a cancelable countdown.
                    EmergencySmsSender.schedule(it, reason = "fall")
                    // Immediate phone call to primary emergency contact — only if the
                    // settings toggle is on (fall *detection* only, not prediction).
                    EmergencyAutoCaller.placeIfEnabled(it)
                }
            }
        }
    }

    // Second independent signal required before treating a phone-motion spike as a
    // confirmed fall — sitting down hard or dropping the phone alone must not qualify.
    private suspend fun checkVitalsCorroboration(atMs: Long, repo: ReadingRepository): Pair<Boolean, String> {
        val since = atMs - CORROBORATION_WINDOW_MS

        val recentStress = repo.stressBetween(since, atMs, 50)
        if (recentStress.isNotEmpty()) {
            val latest = recentStress.last().value
            val baseline = recentStress.dropLast(1).map { it.value }
            val avg = if (baseline.isNotEmpty()) baseline.average() else latest.toDouble()
            if (latest >= 75 || latest - avg >= 25) return true to "stress_spike"
        }

        val recentHr = repo.heartRateBetween(since, atMs, 50)
        if (recentHr.isNotEmpty()) {
            val latest = recentHr.last().valueBpm
            val baseline = recentHr.dropLast(1).map { it.valueBpm }
            val avg = if (baseline.isNotEmpty()) baseline.average() else latest.toDouble()
            if (latest - avg >= 25 || latest >= 130) return true to "hr_spike"
        }

        val latestSpo2 = repo.latestSpo2()
        if (latestSpo2 != null && latestSpo2.valuePct < 92) return true to "spo2_drop"

        return false to "none"
    }
}
