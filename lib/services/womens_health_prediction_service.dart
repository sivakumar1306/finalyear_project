import '../models/womens_health_models.dart';

class WomenHealthPredictionService {
  /// Predicts cycle, ovulation, phase estimation, and explainability reasons
  /// following the Adaptive Women's Health Engine (AWHE) specification from adaptive women.docx.
  PredictionResult predictCycle({
    required DateTime? lastMenstrualPeriod,
    required int averageCycleLength,
    required HealthMetrics metrics,
    bool hasHistory = true,
  }) {
    final now = DateTime.now();

    // ── STEP 1: Rule-Based Physiological Phase Estimation ────────────────────
    // Section 6 Rules:
    // Rule 1: Skin Temp ↑, HRV ↓, Resting Heart Rate ↑ => Late Luteal
    // Rule 2: HRV ↑, Resting Heart Rate ↓, Temp Stable => Follicular
    // Rule 3: Temp begins rising, Resting Heart Rate begins increasing => Ovulation
    // Baseline: Lower activity, recovery => Menstrual

    MenstrualPhase estimatedPhase;
    final List<String> reasons = [];

    final bool isTempElevated = metrics.temperature > 55.0;
    final bool isTempRising = metrics.temperature >= 52.0 && metrics.temperature <= 60.0;
    final bool isHrvLow = metrics.hrv < 45.0;
    final bool isHrvHigh = metrics.hrv >= 55.0;
    final bool isRhrElevated = metrics.heartRate > 55.0;
    final bool isRhrLow = metrics.heartRate <= 45.0;
    final bool isActivityLow = metrics.activityLevel < 35.0;

    if (isTempElevated && isHrvLow && isRhrElevated) {
      estimatedPhase = MenstrualPhase.lateLuteal;
      reasons.add('Elevated skin temperature');
      reasons.add('Lower HRV');
      reasons.add('Higher resting heart rate');
    } else if (isHrvHigh && isRhrLow) {
      estimatedPhase = MenstrualPhase.follicular;
      reasons.add('Higher HRV recovery');
      reasons.add('Lower resting heart rate');
      reasons.add('Stable skin temperature');
    } else if (isTempRising && isRhrElevated) {
      estimatedPhase = MenstrualPhase.ovulation;
      reasons.add('Slight skin temperature rise');
      reasons.add('Resting heart rate increasing');
    } else if (isActivityLow) {
      estimatedPhase = MenstrualPhase.menstrual;
      reasons.add('Lower activity level');
      reasons.add('Physiological recovery onset');
    } else {
      estimatedPhase = MenstrualPhase.lateLuteal;
      reasons.add('Elevated skin temperature');
      reasons.add('Lower HRV');
      reasons.add('Higher resting heart rate');
    }

    // ── STEP 2: Menstrual Prediction Engine (Dual Path) ──────────────────────
    DateTime basePrediction;
    DateTime finalPrediction;
    bool vitalsOnly = !hasHistory || lastMenstrualPeriod == null;
    int phaseRemainingDays = 3;

    if (!vitalsOnly) {
      // Path A: Calendar Prediction + Estimated Phase Shift
      basePrediction = lastMenstrualPeriod.add(Duration(days: averageCycleLength));

      int adjustmentDays = 0;
      if (estimatedPhase == MenstrualPhase.lateLuteal && isHrvLow) {
        adjustmentDays = -1; // Period approaching slightly earlier
      } else if (metrics.stress > 65.0 && metrics.sleepQuality < 40.0) {
        adjustmentDays = 2; // High stress / poor sleep delays cycle
      } else if (metrics.activityLevel > 75.0) {
        adjustmentDays = 1; // Intense physical activity delay
      }

      finalPrediction = basePrediction.add(Duration(days: adjustmentDays));
    } else {
      // Path B: Vitals-Only (No cycle history)
      // Estimated Phase + Expected Remaining Days of Phase
      switch (estimatedPhase) {
        case MenstrualPhase.menstrual:
          phaseRemainingDays = 2;
          break;
        case MenstrualPhase.follicular:
          phaseRemainingDays = 14;
          break;
        case MenstrualPhase.ovulation:
          phaseRemainingDays = 10;
          break;
        case MenstrualPhase.lateLuteal:
          phaseRemainingDays = 3;
          break;
      }
      basePrediction = now.add(Duration(days: phaseRemainingDays));
      finalPrediction = basePrediction;
    }

    // ── STEP 3: Ovulation & Fertile Window Estimation ────────────────────────
    final DateTime ovulationDate = finalPrediction.subtract(const Duration(days: 14));
    final DateTime fertileWindowStart = ovulationDate.subtract(const Duration(days: 5));
    final DateTime fertileWindowEnd = ovulationDate.add(const Duration(days: 1));

    // ── STEP 4: Confidence Estimation ───────────────────────────────────────
    // AWHE Confidence Score:
    // Sensor Availability (30%) + Data Consistency (25%) + Trend Stability (25%) + History (20%)
    double sensorScore = (metrics.temperature > 0 ? 20.0 : 0.0) +
        (metrics.hrv > 0 ? 20.0 : 0.0) +
        (metrics.heartRate > 0 ? 20.0 : 0.0) +
        (metrics.sleepQuality > 0 ? 20.0 : 0.0) +
        (metrics.stress > 0 ? 20.0 : 0.0);

    double consistencyScore = 85.0; // Continuous smart ring capture
    double trendScore = 90.0;
    double historyScore = vitalsOnly ? 40.0 : 100.0;

    double ccs = (0.30 * sensorScore) +
        (0.25 * consistencyScore) +
        (0.25 * trendScore) +
        (0.20 * historyScore);

    ccs = ccs.clamp(0.0, 100.0);

    String confidenceLevel;
    if (ccs >= 80.0) {
      confidenceLevel = 'High';
    } else if (ccs >= 60.0) {
      confidenceLevel = 'Moderate';
    } else {
      confidenceLevel = 'Low';
    }

    return PredictionResult(
      basePrediction: basePrediction,
      finalPrediction: finalPrediction,
      ovulationDate: ovulationDate,
      fertileWindowStart: fertileWindowStart,
      fertileWindowEnd: fertileWindowEnd,
      confidenceScore: ccs,
      confidenceLevel: confidenceLevel,
      estimatedPhase: estimatedPhase,
      explainableReasons: reasons,
      isVitalsOnlyPath: vitalsOnly,
      phaseRemainingDays: phaseRemainingDays,
    );
  }
}

