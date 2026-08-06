import 'engine_outputs.dart';
import '../../services/fall_prediction/fall_risk_registry.dart';
import '../../services/fall_prediction/layer3_motion.dart' show FallHistoryRate;

enum RiskClassification { low, moderate, high }

class PredictionResult {
  final HsiBase hsiBase;
  final HsiAdj hsi; 
  final Frs24 frs24; 
  final Frs30 frs30; 
  final RiskClassification riskLevel;
  final PredictionHorizon tau;
  final CoverageScore q;
  final ExplainabilityPayload? explainability;

  PredictionResult({
    required this.hsiBase,
    required this.hsi,
    required this.frs24,
    required this.frs30,
    required this.riskLevel,
    required this.tau,
    required this.q,
    this.explainability,
  });
}

class FallRiskScoreV2Result {
  final HsiBase hsiBase;
  final HsiAdj hsiAdj;
  final Frs24 frs24;
  final Frs30 frs30;
  final PhysiologicalScore pScore;
  final RecoveryScore rcScore;
  final MotionStabilityScore moScore;
  final WomensHealthScore? whScore;
  final FallHistoryRate fhRate;
  final PredictionHorizon predictionHorizon;
  final CoverageScore coverageScore;
  final ExplainabilityPayload? explainability;

  FallRiskScoreV2Result({
    required this.hsiBase,
    required this.hsiAdj,
    required this.frs24,
    required this.frs30,
    required this.pScore,
    required this.rcScore,
    required this.moScore,
    this.whScore,
    required this.fhRate,
    required this.predictionHorizon,
    required this.coverageScore,
    this.explainability,
  });
}
