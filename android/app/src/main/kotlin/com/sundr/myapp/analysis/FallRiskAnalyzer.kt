package com.sundr.myapp.analysis

import android.content.Context
import com.google.gson.Gson
import com.sundr.myapp.data.FallEventEntity
import com.sundr.myapp.data.FallRiskLogEntity
import com.sundr.myapp.data.ReadingRepository
import com.sundr.myapp.events.NewReadingEvent
import com.sundr.myapp.events.RiskTierChangeEvent
import kotlinx.coroutines.launch
import org.greenrobot.eventbus.EventBus
import org.greenrobot.eventbus.Subscribe
import org.greenrobot.eventbus.ThreadMode

/**
 * Phase 1 of the fall-risk feature (FS-FD-001 counter-proposal): computes a 0-100 risk score
 * from real vitals on every [NewReadingEvent] and logs it via [FallRiskLogEntity]. HIGH/
 * CRITICAL/OVERRIDE scores also fire the live predictive alert ([FallPredictionNotifier]),
 * subject to [ALERT_COOLDOWN_MS] so a sustained elevated score doesn't re-notify on every
 * single reading.
 *
 * Deliberately scoped as a syncope/cardiovascular pre-fall signal, not a general fall
 * predictor: mechanical trip-and-fall has no physiological prodrome, so no vitals-only engine
 * can catch it. Only signals confirmed to actually work on our SDK are used.
 */
object FallRiskAnalyzer {
    private const val BASELINE_WINDOW_MS = 5 * 60_000L
    private const val CRITICAL_SPO2 = 88
    // Minimum gap between live predictive alerts — an elevated score can persist across many
    // readings in a row, and re-notifying on every one of them would be noise, not signal.
    private const val ALERT_COOLDOWN_MS = 15 * 60_000L

    private val gson = Gson()
    private var repository: ReadingRepository? = null
    private var appContext: Context? = null
    private var initialized = false
    private var lastAlertAt = 0L
    @Volatile private var _lastTier: String = "LOW"

    /** Most recently computed risk tier. Used by MeasurementLoopManager for adaptive cooldown. */
    fun currentTier(): String = _lastTier

    fun init(context: Context) {
        if (initialized) return
        initialized = true
        appContext = context.applicationContext
        repository = ReadingRepository.getInstance(context)
        EventBus.getDefault().register(this)
    }

    fun resetCooldown() {
        lastAlertAt = 0L
    }

    @Subscribe(threadMode = ThreadMode.BACKGROUND)
    fun onNewReading(event: NewReadingEvent) {
        val repo = repository ?: return
        repo.ioScope.launch {
            try {
                val result = computeScore(event, repo)
                repo.insertFallRiskLog(
                    FallRiskLogEntity(
                        score = result.score,
                        tier = result.tier,
                        triggerVital = event.vital.name,
                        componentsJson = gson.toJson(result.components),
                        computedAt = event.measuredAt,
                    )
                )
                EventBus.getDefault().post(RiskTierChangeEvent(result.tier))
                _lastTier = result.tier
                maybeAlert(result, event.measuredAt, event.simulated)
            } catch (_: Exception) {
                // Must never affect the rest of the vitals pipeline.
            }
        }
    }

    private fun maybeAlert(result: ScoreResult, measuredAt: Long, simulated: Boolean) {
        if (result.tier != "HIGH" && result.tier != "CRITICAL" && result.tier != "OVERRIDE") return
        if (measuredAt - lastAlertAt < ALERT_COOLDOWN_MS) return
        val context = appContext ?: return
        val repo = repository ?: return
        lastAlertAt = measuredAt
        val msg = (result.components["primaryMessage"] as? String) ?: "A fall-related alert is active."
        FallPredictionNotifier.notifyPrediction(context, msg, simulated = simulated)
        // Simulations must never reach the real emergency pipeline.
        if (!simulated) {
            EmergencySmsSender.schedule(context, reason = "prediction")
        }

        // Persist so it survives banner dismissal and shows up in Fall History.
        repo.ioScope.launch {
            try {
                repo.insertFallEvent(
                    FallEventEntity(
                        confidence = result.score / 100f,
                        corroborated = false,
                        corroborationSource = "prediction",
                        metadataJson = gson.toJson(result.components),
                        detectedAt = measuredAt,
                        eventType = "PREDICTED",
                    )
                )
            } catch (_: Exception) {
                // Must never affect the alert/SMS flow above.
            }
        }
    }

    private suspend fun computeScore(event: NewReadingEvent, repo: ReadingRepository): ScoreResult {
        val now = event.measuredAt
        val since = now - BASELINE_WINDOW_MS
        val components = mutableMapOf<String, Any>()

        var maxSignal = 0f
        var primaryMessage = "A fall-related alert is active."

        fun updateMax(signal: Float, msg: String) {
            if (signal > maxSignal) {
                maxSignal = signal
                primaryMessage = msg
            }
        }

        // SpO2 critical override — the one signal the source doc's design got unambiguously
        // right: severe hypoxia is an emergency regardless of fall context.
        val latestSpo2 = repo.latestSpo2()
        if (latestSpo2 != null && latestSpo2.valuePct < CRITICAL_SPO2) {
            components["spo2"] = latestSpo2.valuePct
            components["override"] = "spo2_critical"
            components["primaryMessage"] = "Your blood oxygen dropped critically to ${latestSpo2.valuePct}%."
            return ScoreResult(100, "OVERRIDE", components)
        }

        val signals = mutableListOf<Float>()

        // HR anomaly while sedentary. We don't have phone-accel context in this backend-only
        // phase, so flat step count over the window stands in for "not exercising".
        val recentSteps = repo.stepsBetween(since, now, 50)
        val sedentary = recentSteps.size < 2 ||
            (recentSteps.maxOf { it.steps } - recentSteps.minOf { it.steps }) < 20
        val recentHr = repo.heartRateBetween(since, now, 200)
        var hr: Int? = null
        if (event.vital == com.sundr.myapp.data.Vital.HEART_RATE && event.primaryValue != null) {
            hr = event.primaryValue.toInt()
        } else if (recentHr.isNotEmpty()) {
            hr = recentHr.last().valueBpm
        }

        if (hr != null) {
            components["hr"] = hr
            components["sedentary"] = sedentary
            val sig = when {
                sedentary && (hr > 120 || hr < 45) -> 1f
                sedentary && (hr > 100 || hr < 50) -> 0.5f
                else -> 0f
            }
            signals += sig
            if (sig > 0f) {
                val action = if (hr > 100) "rose to $hr BPM" else "dropped to $hr BPM"
                updateMax(sig, "Your heart rate $action while you seemed to be in-active for the last 10 minutes.")
            }
        }

        // SpO2 below the soft threshold (critical band already handled above).
        if (latestSpo2 != null) {
            components["spo2"] = latestSpo2.valuePct
            val sig = if (latestSpo2.valuePct < 92) {
                normalise((92 - latestSpo2.valuePct).toFloat(), 0f, 8f)
            } else 0f
            signals += sig
            if (sig > 0f) {
                updateMax(sig, "Your blood oxygen dropped to ${latestSpo2.valuePct}% (below baseline).")
            }
        }

        // Hypertensive extreme or unusually wide pulse pressure.
        val latestBp = repo.latestBloodPressure()
        if (latestBp != null) {
            components["sbp"] = latestBp.systolic
            components["dbp"] = latestBp.diastolic
            val pulsePressure = latestBp.systolic - latestBp.diastolic
            val sig = if (latestBp.systolic >= 160 || pulsePressure >= 80) 1f else 0f
            signals += sig
            if (sig > 0f) {
                updateMax(sig, "Your blood pressure spiked unusually high (${latestBp.systolic}/${latestBp.diastolic}).")
            }
        }

        // Stress spike vs. its own rolling baseline.
        val recentStress = repo.stressBetween(since, now, 200)
        if (recentStress.isNotEmpty()) {
            val latest = recentStress.last().value
            val baseline = recentStress.dropLast(1).map { it.value }
            val avg = if (baseline.isNotEmpty()) baseline.average() else latest.toDouble()
            val jump = latest - avg
            components["stress"] = latest
            components["stressBaseline"] = avg
            val sig = if (latest >= 75 || jump >= 25) 1f else normalise(jump.toFloat(), 0f, 25f)
            signals += sig
            if (sig > 0f) {
                updateMax(sig, "Your stress level spiked abnormally high.")
            }
        }

        // HRV drop vs. rolling baseline.
        val recentHrv = repo.hrvBetween(since, now, 200)
        if (recentHrv.size >= 2) {
            val latest = recentHrv.last().valueMs
            val baseline = recentHrv.dropLast(1).map { it.valueMs }.average()
            components["hrv"] = latest
            components["hrvBaseline"] = baseline
            if (baseline > 0) {
                val dropRatio = (baseline - latest) / baseline
                val sig = if (dropRatio >= 0.15) normalise(dropRatio.toFloat(), 0.15f, 0.5f) else 0f
                signals += sig
                if (sig > 0f) {
                    val pct = (dropRatio * 100).toInt()
                    updateMax(sig, "Your heart rate variability dropped by $pct% from baseline.")
                }
            }
        }

        if (signals.isEmpty()) return ScoreResult(0, "LOW", components)

        components["primaryMessage"] = primaryMessage

        val score = (signals.average() * 100).toInt().coerceIn(0, 100)
        val tier = when {
            score >= 80 -> "CRITICAL"
            score >= 60 -> "HIGH"
            score >= 40 -> "MODERATE"
            else -> "LOW"
        }
        return ScoreResult(score, tier, components)
    }

    private fun normalise(value: Float, threshold: Float, max: Float): Float {
        if (value <= threshold) return 0f
        if (value >= max) return 1f
        return (value - threshold) / (max - threshold)
    }

    private data class ScoreResult(val score: Int, val tier: String, val components: Map<String, Any>)
}
