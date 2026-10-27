import '../../models/fall_prediction/layer_inputs.dart';
import 'fall_risk_registry.dart';

/// Recovery inputs from raw readings, as the app derives them: sleep score
/// = minutes / 480 × 100; sleep quality from the deep-sleep share (20 % =
/// 100, otherwise the sleep score); activity = steps / 10 000 × 100; stress
/// from HRV (60 ms = no stress). Returns the data and the activity exposure.
(Layer2RecoveryData, ActivityExposure?) recoveryFromReadings({
  double? sleepMinutes,
  double? deepSleepMinutes,
  int? steps,
  double? hrv,
}) {
  double? sleepDurScore;
  if (sleepMinutes != null) {
    sleepDurScore = (sleepMinutes / 480.0 * 100.0).clamp(0.0, 100.0);
  }
  double? sleepQualScore = sleepDurScore;
  if (deepSleepMinutes != null && sleepMinutes != null && sleepMinutes > 0) {
    final deepPct = deepSleepMinutes / sleepMinutes;
    sleepQualScore = (deepPct / 0.2 * 100.0).clamp(0.0, 100.0);
  }
  double? activityScore;
  if (steps != null) {
    activityScore = (steps / 10000.0 * 100.0).clamp(0.0, 100.0);
  }
  double? stressScore;
  if (hrv != null) {
    stressScore = (100.0 - (hrv / 60.0 * 100.0).clamp(0.0, 100.0)).clamp(0.0, 100.0);
  }
  ActivityRecovery? actRecovery;
  ActivityExposure? actExposure;
  if (activityScore != null) {
    final split = ActivityDataTransformer.splitRawActivity(activityScore);
    actRecovery = split.$1;
    actExposure = split.$2;
  }
  return (
    Layer2RecoveryData(
      slp: sleepDurScore,
      slq: sleepQualScore,
      act: actRecovery,
      wkl: activityScore,
      str: stressScore,
    ),
    actExposure,
  );
}

class ActivityDataTransformer {
  /// Splits the raw activity payload from the device into two distinct, strictly typed variables.
  static (ActivityRecovery, ActivityExposure) splitRawActivity(double rawActivity) {
    return (
      ActivityRecovery(rawActivity),
      ActivityExposure(rawActivity)
    );
  }
}

class Layer2Calculator {
  static double normalizeSLP(double slp) {
    return slp.clamp(0.0, 100.0);
  }

  static double normalizeSLQ(double slq) {
    return slq.clamp(0.0, 100.0);
  }

  static double normalizeACT(ActivityRecovery actRec) {
    return actRec.value.clamp(0.0, 100.0);
  }

  static double normalizeWKL(double wkl) {
    // Inverted normalization curve for Workout Load
    // High workout load -> low score (0), low load -> high score (100)
    return (100.0 - wkl).clamp(0.0, 100.0);
  }

  static double normalizeSTR(double str) {
    // Inverted normalization curve for Stress
    // High stress -> low score (0), low stress -> high score (100)
    return (100.0 - str).clamp(0.0, 100.0);
  }

  static RecoveryScore calculateRC({
    required Layer2RecoveryData data,
    required Map<String, double> wPrime,
  }) {
    double rcRaw = 0.0;
    double totalWeight = 0.0;

    double wSlp = wPrime['slp'] ?? 0.30;
    double wSlq = wPrime['slq'] ?? 0.25;
    double wAct = wPrime['act'] ?? 0.20;
    double wWkl = wPrime['wkl'] ?? 0.15;
    double wStr = wPrime['str'] ?? 0.10;

    if (data.slp != null) {
      rcRaw += wSlp * normalizeSLP(data.slp!);
      totalWeight += wSlp;
    }
    
    if (data.slq != null) {
      rcRaw += wSlq * normalizeSLQ(data.slq!);
      totalWeight += wSlq;
    }

    if (data.act != null) {
      rcRaw += wAct * normalizeACT(data.act!);
      totalWeight += wAct;
    }

    if (data.wkl != null) {
      rcRaw += wWkl * normalizeWKL(data.wkl!);
      totalWeight += wWkl;
    }

    if (data.str != null) {
      rcRaw += wStr * normalizeSTR(data.str!);
      totalWeight += wStr;
    }

    double rc = totalWeight > 0 ? (rcRaw / totalWeight) : 100.0;

    assert(rc >= 0.0 && rc <= 100.0, 'Recovery Score must be strictly bounded between 0 and 100');
    return RecoveryScore(rc.clamp(0.0, 100.0));
  }
}
