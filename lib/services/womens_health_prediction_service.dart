import '../models/womens_health_models.dart';

class WomenHealthPredictionService {
  /// Predicts the cycle, ovulation, and fertile window based on the base inputs and wearable sensor metrics.
  /// This local rule-based engine can be swapped to consume JSON from a remote backend.
  PredictionResult predictCycle({
    required DateTime lastMenstrualPeriod,
    required int averageCycleLength,
    required HealthMetrics metrics,
  }) {
    // Step 1: Base Cycle Prediction
    // NP = LMP + CL
    final DateTime basePrediction = lastMenstrualPeriod.add(Duration(days: averageCycleLength));

    // Step 2 & 3: Metric Adjustment Score (MAS)
    // MAS = 0.25T + 0.20HRV + 0.20RHR + 0.15S + 0.10SL + 0.10A
    double mas = (0.25 * metrics.temperature) +
        (0.20 * metrics.hrv) +
        (0.20 * metrics.heartRate) +
        (0.15 * metrics.stress) +
        (0.10 * metrics.sleepQuality) +
        (0.10 * metrics.activityLevel);

    // Ensure clamped between 0 and 100
    mas = mas.clamp(0.0, 100.0);

    // Step 4: Prediction Adjustment
    // Evaluate the metrics and apply a Duration adjustment (between -3 to +3 days) to the Base Prediction
    int adjustmentDays = 0;

    // We assume 50 as a midpoint for normal range.
    // T > 60 (temperature increases), HRV < 40 (HRV is reduced)
    if (metrics.temperature > 60 && metrics.hrv < 40) {
      adjustmentDays = -1;
    }
    // Stress > 60 (stress is high), Sleep < 40 (sleep is poor)
    else if (metrics.stress > 60 && metrics.sleepQuality < 40) {
      adjustmentDays = 2;
    }
    // ActivityLevel > 70 (physical activity is intense over multiple days)
    else if (metrics.activityLevel > 70) {
      adjustmentDays = 1;
    }
    // Otherwise, 0 days if metrics are stable.

    // Calculate final prediction
    final DateTime finalPrediction = basePrediction.add(Duration(days: adjustmentDays));

    // Step 5: Ovulation Prediction
    // OD = FinalPrediction - 14
    final DateTime ovulationDate = finalPrediction.subtract(const Duration(days: 14));

    // Step 6: Fertile Window Estimation
    // FW = (OD - 5) to (OD + 1)
    final DateTime fertileWindowStart = ovulationDate.subtract(const Duration(days: 5));
    final DateTime fertileWindowEnd = ovulationDate.add(const Duration(days: 1));

    // Step 7: Cycle Confidence Score (CCS)
    // CCS = 0.30T + 0.25HRV + 0.20Sleep + 0.15Stress + 0.10Activity
    double ccs = (0.30 * metrics.temperature) +
        (0.25 * metrics.hrv) +
        (0.20 * metrics.sleepQuality) +
        (0.15 * metrics.stress) +
        (0.10 * metrics.activityLevel);

    ccs = ccs.clamp(0.0, 100.0);

    // Determine confidence level
    String confidenceLevel;
    if (ccs >= 80) {
      confidenceLevel = 'High';
    } else if (ccs >= 60) {
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
    );
  }
}
