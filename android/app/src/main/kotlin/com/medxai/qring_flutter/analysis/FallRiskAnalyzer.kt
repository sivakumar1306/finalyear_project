package com.medxai.qring_flutter.analysis

import android.content.Context
import com.google.gson.Gson
import com.medxai.qring_flutter.data.FallRiskLogEntity
import com.medxai.qring_flutter.data.ReadingRepository
import com.medxai.qring_flutter.events.NewReadingEvent
import kotlinx.coroutines.launch
import org.greenrobot.eventbus.EventBus
import org.greenrobot.eventbus.Subscribe
import org.greenrobot.eventbus.ThreadMode

/**
 * Phase 1 of the fall-risk feature (FS-FD-001 counter-proposal): computes a 0-100 risk score
 * from real vitals on every [NewReadingEvent] and logs it silently via [FallRiskLogEntity].
 * Nothing here alerts the user — the goal is to build up scored history so a real correlation
 * against fall/near-fall reports can validate the approach before any live alert ships.
 *
 * Deliberately scoped as a syncope/cardiovascular pre-fall signal, not a general fall
 * predictor: mechanical trip-and-fall has no physiological prodrome, so no vitals-only engine
 * can catch it. Only signals confirmed to actually work on our SDK are used — HRV is included
 * opportunistically since Vital.HRV is disabled by default and the table is usually empty.
 */
object FallRiskAnalyzer {
    private const val BASELINE_WINDOW_MS = 5 * 60_000L
    private const val CRITICAL_SPO2 = 88

    private val gson = Gson()
    private var repository: ReadingRepository? = null
    private var initialized = false

    fun init(context: Context) {
        if (initialized) return
        initialized = true
        repository = ReadingRepository.getInstance(context)
        EventBus.getDefault().register(this)
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
            } catch (_: Exception) {
                // Silent-logging feature — must never affect the rest of the vitals pipeline.
            }
        }
    }

    private suspend fun computeScore(event: NewReadingEvent, repo: ReadingRepository): ScoreResult {
        val now = event.measuredAt
        val since = now - BASELINE_WINDOW_MS
        val components = mutableMapOf<String, Any>()

        // SpO2 critical override — the one signal the source doc's design got unambiguously
        // right: severe hypoxia is an emergency regardless of fall context.
        val latestSpo2 = repo.latestSpo2()
        if (latestSpo2 != null && latestSpo2.valuePct < CRITICAL_SPO2) {
            components["spo2"] = latestSpo2.valuePct
            components["override"] = "spo2_critical"
            return ScoreResult(100, "OVERRIDE", components)
        }

        val signals = mutableListOf<Float>()

        // HR anomaly while sedentary. We don't have phone-accel context in this backend-only
        // phase, so flat step count over the window stands in for "not exercising".
        val recentSteps = repo.stepsBetween(since, now, 50)
        val sedentary = recentSteps.size < 2 ||
            (recentSteps.maxOf { it.steps } - recentSteps.minOf { it.steps }) < 20
        val recentHr = repo.heartRateBetween(since, now, 200)
        if (recentHr.isNotEmpty()) {
            val hr = recentHr.last().valueBpm
            components["hr"] = hr
            components["sedentary"] = sedentary
            signals += when {
                sedentary && (hr > 120 || hr < 45) -> 1f
                sedentary && (hr > 100 || hr < 50) -> 0.5f
                else -> 0f
            }
        }

        // SpO2 below the soft threshold (critical band already handled above).
        if (latestSpo2 != null) {
            components["spo2"] = latestSpo2.valuePct
            signals += if (latestSpo2.valuePct < 92) {
                normalise((92 - latestSpo2.valuePct).toFloat(), 0f, 8f)
            } else {
                0f
            }
        }

        // Hypertensive extreme or unusually wide pulse pressure.
        val latestBp = repo.latestBloodPressure()
        if (latestBp != null) {
            components["sbp"] = latestBp.systolic
            components["dbp"] = latestBp.diastolic
            val pulsePressure = latestBp.systolic - latestBp.diastolic
            signals += if (latestBp.systolic >= 160 || pulsePressure >= 80) 1f else 0f
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
            signals += if (latest >= 75 || jump >= 25) 1f else normalise(jump.toFloat(), 0f, 25f)
        }

        // HRV drop vs. rolling baseline — bonus signal only, since this table is usually
        // empty (Vital.HRV disabled by default; never produced a valid reading in testing).
        val recentHrv = repo.hrvBetween(since, now, 200)
        if (recentHrv.size >= 2) {
            val latest = recentHrv.last().valueMs
            val baseline = recentHrv.dropLast(1).map { it.valueMs }.average()
            components["hrv"] = latest
            components["hrvBaseline"] = baseline
            if (baseline > 0) {
                val dropRatio = (baseline - latest) / baseline
                signals += if (dropRatio >= 0.15) normalise(dropRatio.toFloat(), 0.15f, 0.5f) else 0f
            }
        }

        if (signals.isEmpty()) return ScoreResult(0, "LOW", components)

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
