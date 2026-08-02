import '../../models/fall_prediction/physiological_data.dart';
import '../../models/fall_prediction/behavioral_data.dart';
import '../../models/fall_prediction/motion_data.dart';
import '../../models/fall_prediction/womens_health_data.dart';
import '../../models/fall_prediction/context_factors.dart';
import '../../models/fall_prediction/prediction_result.dart';
import 'adaptive_weight_engine.dart';
import 'reasoning_engine.dart';

class FallPredictionEngine {
  // Layer Base Weights
  static const double baseAlpha = 0.20; // Physiological
  static const double baseBeta = 0.20;  // Recovery
  static const double baseGamma = 0.40; // Motion
  static const double baseDelta = 0.20; // Women's Health

  // Physiological Weights
  static const double hrWeight = 0.20;
  static const double hrvWeight = 0.25;
  static const double bpWeight = 0.20;
  static const double spo2Weight = 0.20;
  static const double tempWeight = 0.15;

  // Recovery Weights
  static const double sleepDurWeight = 0.30;
  static const double sleepQualWeight = 0.25;
  static const double activityWeight = 0.20;
  static const double workoutWeight = 0.15;
  static const double stressWeight = 0.10;

  PredictionResult calculateRisk({
    required PhysiologicalData pData,
    required BehavioralData rData,
    required MotionData mData,
    required WomensHealthData wData,
    required ContextFactors context,
  }) {
    // 1. Calculate P (Physiological Stability)
    double pScore = (pData.heartRate * hrWeight) +
        (pData.hrv * hrvWeight) +
        (pData.bloodPressure * bpWeight) +
        (pData.spo2 * spo2Weight) +
        (pData.skinTemperature * tempWeight);

    // 2. Calculate R (Behavioral Recovery) 
    double rScore = (rData.sleepDuration * sleepDurWeight) +
        (rData.sleepQuality * sleepQualWeight) +
        (rData.dailyActivity * activityWeight) +
        (rData.workoutLoad * workoutWeight) +
        (rData.stress * stressWeight);

    // 3. Calculate M (Motion Intelligence)
    double mScore = ((100 - mData.impact) + mData.orientation + mData.recoveryAttempts + (100 - mData.fallHistory)) / 4;

    // 4. Calculate W Context adjustments
    double wScore = 100;
    if (wData.isApplicable && wData.isPMS) {
       wScore = 80;
    }

    // 5. Adaptive Weight Engine
    Map<String, double> initialWeights = {
      'physiological': baseAlpha,
      'recovery': baseBeta,
      'motion': baseGamma,
      'womens_health': wData.isApplicable ? baseDelta : 0.0,
    };

    if (!wData.isApplicable) {
       double remaining = baseAlpha + baseBeta + baseGamma; 
       initialWeights['physiological'] = baseAlpha + (baseDelta * (baseAlpha / remaining));
       initialWeights['recovery'] = baseBeta + (baseDelta * (baseBeta / remaining));
       initialWeights['motion'] = baseGamma + (baseDelta * (baseGamma / remaining));
    }

    Map<String, double> finalWeights = AdaptiveWeightEngine.calculateAdaptiveWeights(
      initialWeights,
      context,
    );

    // 6. Calculate HSI
    double hsi = (pScore * (finalWeights['physiological'] ?? 0)) +
        (rScore * (finalWeights['recovery'] ?? 0)) +
        (mScore * (finalWeights['motion'] ?? 0)) +
        (wScore * (finalWeights['womens_health'] ?? 0));

    // 7. Calculate FCS
    double fcs = (100 - hsi) * 0.8 + (mData.fallHistory * 0.2); 
    fcs = fcs.clamp(0.0, 100.0);

    // 8. Risk Classification
    RiskClassification classification;
    if (fcs <= 30) {
      classification = RiskClassification.low;
    } else if (fcs <= 60) {
      classification = RiskClassification.moderate;
    } else {
      classification = RiskClassification.high;
    }

    // 9. Generate XAI Reasoning Chain
    List<String> reasoningChain = ReasoningEngine.generateReasoningChain(hsi, pData, rData, mData);

    return PredictionResult(
      hsi: hsi,
      fcs: fcs,
      riskLevel: classification,
      reasoningChain: reasoningChain,
    );
  }
}
