import 'dart:math';
import 'fall_risk_registry.dart';

/// 1. Create Threshold & Mapping Configurations
class PhysiologyThresholds {
  // SpO2 cliff drop-off points
  static const double spO2CliffStart = 95.0;
  static const double spO2CliffEnd = 90.0;
  
  // HRV standard deviation threshold
  static const double hrvStdDevThreshold = 1.5;
  
  // Default BP population norms
  static const double defaultSysPopNorm = 120.0;
  static const double defaultDiaPopNorm = 80.0;
}

/// 3. Implement Blood Pressure Logic & Dependency Flags
enum BpSource {
  hospitalBaseline,
  homeCuff,
  none,
}

class BpBaseline {
  final double sys;
  final double dia;

  const BpBaseline({required this.sys, required this.dia});
}

class BpResult {
  final double sysScore;
  final double diaScore;
  final double stalenessPenalty; // Expose staleness metadata flag or penalty value

  const BpResult({required this.sysScore, required this.diaScore, required this.stalenessPenalty});
}

/// 2. Build Specific Normalization Functions (f_x)

/// Implement a U-shaped function around the baseline. Both bradycardia and 
/// tachycardia relative to the personal baseline must penalize the score.
double normalizeHR(double currentHR, double rolling14DayMedianHR) {
  if (rolling14DayMedianHR <= 0) return 50.0; // Fallback
  
  // Calculate relative deviation from baseline
  double deviationRatio = ((currentHR - rolling14DayMedianHR) / rolling14DayMedianHR).abs();
  
  // U-shape penalty: 0 deviation = 100 score. 
  // A 30% deviation drops score to 0.
  double score = 100.0 - (deviationRatio * (100.0 / 0.30)); 
  
  return score.clamp(0.0, 100.0);
}

/// Calculate deviation from the personal baseline. A drop of 1.5 standard deviations 
/// below the user's 28-day rolling distribution should represent a significant drop in the 0-100 score.
double normalizeHRV(double currentHRV, double rolling28DayMean, double rolling28DayStdDev) {
  if (rolling28DayStdDev <= 0) return 100.0; // Fallback if no valid std dev

  // Z-score for current HRV
  double zScore = (currentHRV - rolling28DayMean) / rolling28DayStdDev;
  
  if (zScore >= 0) {
    // Above or at mean is healthy, score 100
    return 100.0; 
  }
  
  // Map z-score drops to lower score. 
  // E.g., if zScore is -1.5 (threshold), it drops the score significantly.
  // A z-score of 0 is 100. A z-score of -1.5 could be 20. 
  // slope = 80 / 1.5 = 53.33
  double score = 100.0 + (zScore * (80.0 / PhysiologyThresholds.hrvStdDevThreshold));
  
  return score.clamp(0.0, 100.0);
}

/// Implement a cliff function. Returns 100 for 95-100%, applies a steep linear 
/// decay between 90-95%, and returns near-zero below 90%.
double normalizeSpO2(double spO2) {
  if (spO2 >= PhysiologyThresholds.spO2CliffStart) {
    return 100.0;
  } else if (spO2 <= PhysiologyThresholds.spO2CliffEnd) {
    return 0.0;
  } else {
    // Linear decay between 95 and 90
    double range = PhysiologyThresholds.spO2CliffStart - PhysiologyThresholds.spO2CliffEnd;
    double score = ((spO2 - PhysiologyThresholds.spO2CliffEnd) / range) * 100.0;
    return score.clamp(0.0, 100.0);
  }
}

/// Subtract ambient temp from peripheral temp first to handle seasonal/climate drift. 
/// Then, normalize the deviation from the user's baseline.
double normalizeTemp(double peripheralTemp, double ambientTemp, double baselineAdjustedTemp) {
  // Handle seasonal/climate drift
  double adjustedCurrentTemp = peripheralTemp - ambientTemp;
  
  double deviation = (adjustedCurrentTemp - baselineAdjustedTemp).abs();
  
  // 1.5 degrees deviation drops score to 0
  double score = 100.0 - (deviation * (100.0 / 1.5));
  
  return score.clamp(0.0, 100.0);
}

/// Blood Pressure Logic
BpResult normalizeBP(double sys, double dia, BpSource source, {BpBaseline? hospitalBaseline, DateTime? lastMeasured}) {
  double targetSys;
  double targetDia;
  
  // If source == BpSource.hospitalBaseline, compare current BP to that baseline. 
  // Otherwise, fall back to general population norms.
  if (source == BpSource.hospitalBaseline && hospitalBaseline != null) {
    targetSys = hospitalBaseline.sys;
    targetDia = hospitalBaseline.dia;
  } else {
    targetSys = PhysiologyThresholds.defaultSysPopNorm;
    targetDia = PhysiologyThresholds.defaultDiaPopNorm;
  }
  
  double sysDeviation = (sys - targetSys).abs() / targetSys;
  double diaDeviation = (dia - targetDia).abs() / targetDia;
  
  double sysScore = (100.0 - (sysDeviation * 300.0)).clamp(0.0, 100.0);
  double diaScore = (100.0 - (diaDeviation * 300.0)).clamp(0.0, 100.0);
  
  // Expose a staleness metadata flag or penalty value based on lastMeasured
  double stalenessPenalty = 0.0;
  if (lastMeasured != null) {
    Duration age = DateTime.now().difference(lastMeasured);
    if (age.inDays > 14) {
      stalenessPenalty = min((age.inDays - 14) * 2.0, 50.0); // max 50 penalty for staleness
    }
  }
  
  return BpResult(sysScore: sysScore, diaScore: diaScore, stalenessPenalty: stalenessPenalty);
}

/// 4. Implement the Layer 1 Aggregation Formula (P)
class AdaptiveWeights {
  final double hr;
  final double hrv;
  final double bp;
  final double spO2;
  final double temp;

  const AdaptiveWeights({
    required this.hr,
    required this.hrv,
    required this.bp,
    required this.spO2,
    required this.temp,
  });
}

class Layer1Result {
  final PhysiologicalScore pScore;
  final double bpStalenessPenalty;

  const Layer1Result({
    required this.pScore,
    this.bpStalenessPenalty = 0.0,
  });
}

class Layer1Calculator {
  Layer1Result calculateP({
    required double? currentHR,
    required double rolling14DayMedianHR,
    required double? currentHRV,
    required double rolling28DayMeanHRV,
    required double rolling28DayStdDevHRV,
    required double? currentSpO2,
    required double? peripheralTemp,
    required double ambientTemp,
    required double baselineAdjustedTemp,
    required double? currentSys,
    required double? currentDia,
    required BpSource? bpSource,
    BpBaseline? hospitalBaseline,
    DateTime? lastMeasuredBp,
    required AdaptiveWeights weights,
  }) {
    double pRaw = 0.0;
    double totalWeight = 0.0;
    double bpStalenessPenalty = 0.0;

    if (currentHR != null) {
      double fHr = normalizeHR(currentHR, rolling14DayMedianHR);
      pRaw += weights.hr * fHr;
      totalWeight += weights.hr;
    }

    if (currentHRV != null) {
      double fHrv = normalizeHRV(currentHRV, rolling28DayMeanHRV, rolling28DayStdDevHRV);
      pRaw += weights.hrv * fHrv;
      totalWeight += weights.hrv;
    }

    if (currentSpO2 != null) {
      double fSpo2 = normalizeSpO2(currentSpO2);
      pRaw += weights.spO2 * fSpo2;
      totalWeight += weights.spO2;
    }

    if (peripheralTemp != null) {
      double fTemp = normalizeTemp(peripheralTemp, ambientTemp, baselineAdjustedTemp);
      pRaw += weights.temp * fTemp;
      totalWeight += weights.temp;
    }
    
    if (currentSys != null && currentDia != null) {
      BpResult bpResult = normalizeBP(
        currentSys, 
        currentDia, 
        bpSource ?? BpSource.none, 
        hospitalBaseline: hospitalBaseline, 
        lastMeasured: lastMeasuredBp,
      );
      pRaw += (weights.bp / 2.0) * bpResult.sysScore;
      pRaw += (weights.bp / 2.0) * bpResult.diaScore;
      totalWeight += weights.bp;
      bpStalenessPenalty = bpResult.stalenessPenalty;
    }

    // P = w'_HR * f_HR + w'_HRV * f_HRV + w'_BP * f_BP + w'_SpO2 * f_SpO2 + w'_TEMP * f_TEMP (Renormalized)
    double pFinal = totalWeight > 0 ? pRaw / totalWeight : 100.0; // Default to 100 if no data
    
    // Assert that the final calculated P is strictly bounded between 0 and 100
    assert(pFinal >= 0.0 && pFinal <= 100.0, 'Physiological Stability Score (P) must be between 0 and 100');

    return Layer1Result(
      pScore: PhysiologicalScore(pFinal),
      bpStalenessPenalty: bpStalenessPenalty,
    );
  }
}
