import '../../models/fall_prediction/engine_outputs.dart';

class HsiAggregationService {
  double computeHsiBase({
    required double p,
    required double rc,
    required double mo,
    double? wh,
    required Map<String, double> fixedBaseWeights,
  }) {
    double alpha = fixedBaseWeights['p'] ?? 0.0;
    double beta = fixedBaseWeights['rc'] ?? 0.0;
    double gamma = fixedBaseWeights['mo'] ?? 0.0;
    double delta = fixedBaseWeights['wh'] ?? 0.0;

    if (wh == null) {
      delta = 0.0;
      double remaining = alpha + beta + gamma;
      if (remaining > 0.0) {
        alpha = alpha / remaining;
        beta = beta / remaining;
        gamma = gamma / remaining;
      }
    }

    double hsiBase = (p * alpha) + (rc * beta) + (mo * gamma) + ((wh ?? 0.0) * delta);
    
    assert(hsiBase >= 0.0 && hsiBase <= 100.0, 'HSI_base must be bounded between 0.0 and 100.0, got $hsiBase');
    return hsiBase.clamp(0.0, 100.0);
  }

  double computeHsiAdj({
    required double p,
    required double rc,
    required double mo,
    double? wh,
    required Map<String, double> dynamicWeights,
  }) {
    double alpha = dynamicWeights['p'] ?? 0.0;
    double beta = dynamicWeights['rc'] ?? 0.0;
    double gamma = dynamicWeights['mo'] ?? 0.0;
    double delta = dynamicWeights['wh'] ?? 0.0;

    double hsiAdj = (p * alpha) + (rc * beta) + (mo * gamma) + ((wh ?? 0.0) * delta);
    
    assert(hsiAdj >= 0.0 && hsiAdj <= 100.0, 'HSI_adj must be bounded between 0.0 and 100.0, got $hsiAdj');
    return hsiAdj.clamp(0.0, 100.0);
  }

  AttributionDeltas computeExplainabilityDeltas({
    required Map<String, double> baselineScores,
    required Map<String, double> currentScores,
    required Map<String, double> baseWeights,
    required Map<String, double> currentWeights,
  }) {
    double hsiBaseline = 0.0;
    double hsiAdj = 0.0;
    double hsiContextOnly = 0.0;
    
    final components = ['p', 'rc', 'mo', 'wh'];
    
    for (var comp in components) {
      double scoreBase = baselineScores[comp] ?? 0.0;
      double scoreCurr = currentScores[comp] ?? 0.0;
      double wBase = baseWeights[comp] ?? 0.0;
      double wCurr = currentWeights[comp] ?? 0.0;
      
      hsiBaseline += scoreBase * wBase;
      hsiAdj += scoreCurr * wCurr;
      hsiContextOnly += scoreBase * wCurr;
    }
    
    int contextShiftDelta = (hsiBaseline - hsiContextOnly).round();
    int physiologicalDelta = (hsiContextOnly - hsiAdj).round();
    
    return AttributionDeltas(
      contextShiftDelta: contextShiftDelta,
      physiologicalDelta: physiologicalDelta,
    );
  }
}
