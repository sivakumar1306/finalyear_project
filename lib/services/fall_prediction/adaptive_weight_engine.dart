import '../../models/fall_prediction/context_factors.dart';

class AdaptiveWeightEngine {
  // 2. Implement the Universal Renormalization Utility
  static Map<String, double> renormalizeWeights(
    Map<String, double> baseWeights,
    Map<String, double> contextMultipliers,
  ) {
    double denominator = 0.0;
    Map<String, double> rawWeights = {};

    baseWeights.forEach((key, w) {
      double c = contextMultipliers[key] ?? 1.0;
      double raw = w * c;
      rawWeights[key] = raw;
      denominator += raw;
    });

    if (denominator == 0.0) {
      return baseWeights; // Fallback
    }

    Map<String, double> normalized = {};
    double sum = 0.0;
    rawWeights.forEach((key, raw) {
      double wPrime = raw / denominator;
      normalized[key] = wPrime;
      sum += wPrime;
    });

    assert((sum - 1.0).abs() < 0.0001, 'Renormalized weights must sum to 1.0');
    return normalized;
  }

  // 3. Define the Weight Providers
  static Map<String, double> getPhysiologyWeights(ContextFactors context) {
    Map<String, double> baseWeights = {
      'hr': 0.20,
      'hrv': 0.25,
      'bp': 0.20,
      'spo2': 0.20,
      'temp': 0.15,
    };
    Map<String, double> multipliers = {
      'hr': context.age,
      'hrv': context.age,
      'bp': context.age,
      'spo2': 1.0,
      'temp': 1.0,
    };
    return renormalizeWeights(baseWeights, multipliers);
  }

  static Map<String, double> getRecoveryWeights(ContextFactors context) {
    Map<String, double> baseWeights = {
      'slp': 0.30,
      'slq': 0.25,
      'act': 0.20,
      'wkl': 0.15,
      'str': 0.10,
    };
    Map<String, double> multipliers = {
      'slp': context.sleepDebt,
      'slq': context.sleepDebt,
      'act': 1.0,
      'wkl': 1.0,
      'str': context.stressTrend,
    };
    return renormalizeWeights(baseWeights, multipliers);
  }

  /// Motion layer: daily steps 0.5, near-falls 0.5 (report, Table 3.3).
  static Map<String, double> getMotionWeights(ContextFactors context) {
    return renormalizeWeights(
      {'steps': 0.5, 'nearFalls': 0.5},
      {'steps': 1.0, 'nearFalls': 1.0},
    );
  }

  static Map<String, double> getHsiGlobalWeights(ContextFactors context, {bool includeWomensHealth = true}) {
    Map<String, double> baseWeights = {
      'physiological': 0.35,
      'recovery': 0.30,
      'motion': 0.20,
      'womens_health': includeWomensHealth ? 0.15 : 0.0,
    };
    Map<String, double> multipliers = {
      'physiological': context.age,
      'recovery': context.sleepDebt * context.stressTrend,
      'motion': 1.0,
      'womens_health': includeWomensHealth ? context.womensHealthPhase : 0.0,
    };
    return renormalizeWeights(baseWeights, multipliers);
  }

  // Legacy fallback for V1 pipeline
  static Map<String, double> calculateAdaptiveWeights(
    Map<String, double> baseWeights,
    ContextFactors context,
  ) {
    return getHsiGlobalWeights(context, includeWomensHealth: (baseWeights['womens_health'] ?? 0) > 0);
  }

  static Map<String, double> calculateAdaptiveWeightsV2(
    Map<String, double> baseWeights,
    ContextFactors context,
  ) {
    return getHsiGlobalWeights(context, includeWomensHealth: (baseWeights['womens_health'] ?? 0) > 0);
  }
}
