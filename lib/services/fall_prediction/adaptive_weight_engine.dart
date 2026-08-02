import '../../models/fall_prediction/context_factors.dart';

class AdaptiveWeightEngine {
  static Map<String, double> calculateAdaptiveWeights(
    Map<String, double> baseWeights,
    ContextFactors context,
  ) {
    Map<String, double> adaptiveWeights = {};
    
    // Calculate raw adaptive weights
    double totalWeight = 0;
    baseWeights.forEach((key, weight) {
      double factor = 1.0;
      
      switch (key) {
        case 'physiological':
          factor = context.ageFactor;
          break;
        case 'recovery':
          factor = context.sleepDebtFactor * context.stressTrendFactor;
          break;
        case 'motion':
          factor = context.previousFallsFactor;
          break;
        case 'womens_health':
          factor = context.cyclePhaseFactor;
          break;
      }
      
      double adaptiveWeight = weight * factor;
      adaptiveWeights[key] = adaptiveWeight;
      totalWeight += adaptiveWeight;
    });
    
    // Normalize weights to ensure sum is 1
    if (totalWeight > 0) {
      adaptiveWeights.forEach((key, weight) {
        adaptiveWeights[key] = weight / totalWeight;
      });
    }
    
    return adaptiveWeights;
  }
}
