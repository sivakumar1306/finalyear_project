import '../../models/fall_prediction/layer_inputs.dart';
import '../../models/fall_prediction/engine_outputs.dart';
import '../../models/fall_prediction/context_factors.dart';
import '../../models/fall_prediction/prediction_result.dart';
import 'fall_risk_registry.dart';
import 'layer1_physiology.dart';
import 'layer4_womens_health.dart';
import 'adaptive_weight_engine.dart';
import 'layer2_recovery.dart';
import 'layer3_motion.dart';
import 'red_flag_override.dart';
import 'hsi_aggregation_service.dart';

class FallPredictionEngine {
  final RedFlagOverrideService redFlagService;
  final EscalationService escalationService;
  final CorroborationService corroborationService;

  FallPredictionEngine({
    required this.redFlagService,
    required this.escalationService,
    required this.corroborationService,
  });
  // Layer Base Weights
  static const double baseAlpha = 0.20; // Physiological
  static const double baseBeta = 0.20;  // Recovery
  static const double baseGamma = 0.40; // Motion
  static const double baseDelta = 0.20; // Women's Health

  // Physiological Weights (Layer 1)
  static const double hrWeight = 0.20;
  static const double hrvWeight = 0.25;
  static const double bpWeight = 0.20;
  static const double spo2Weight = 0.20;
  static const double tempWeight = 0.15;

  // Recovery Weights (Layer 2)
  static const double sleepDurWeight = 0.30;
  static const double sleepQualWeight = 0.25;
  static const double activityWeight = 0.20;
  static const double workoutWeight = 0.15;
  static const double stressWeight = 0.10;
  
  // Motion Weights (Layer 3) - these are placeholders as no specific weights were given for new fields,
  // we will divide evenly among the 7 fields or adapt existing logic.
  static const double accWeight = 1/7;
  static const double gyrWeight = 1/7;
  static const double gaitWeight = 1/7;
  static const double pswWeight = 1/7;
  static const double orthoWeight = 1/7;
  static const double plntWeight = 1/7;
  static const double fhWeight = 1/7;

  PhysiologicalScore _calculateLayer1(Layer1PhysiologyData data) {
    double score = ((data.hr ?? 100.0) * hrWeight) +
        ((data.hrv ?? 100.0) * hrvWeight) +
        ((data.bp ?? 100.0) * bpWeight) +
        ((data.spo2 ?? 100.0) * spo2Weight) +
        ((data.temp ?? 100.0) * tempWeight);
    return PhysiologicalScore(score.clamp(0.0, 100.0));
  }
  
  RecoveryScore _calculateLayer2(Layer2RecoveryData data, Map<String, double>? wPrime) {
    return Layer2Calculator.calculateRC(
      data: data,
      wPrime: wPrime ?? {},
    );
  }
  
  MotionStabilityScore _calculateLayer3(Layer3MotionData data) {
    // Note: If fall history is high, it lowers stability, etc.
    // Assuming normalized inputs where higher is better for stability, 
    // except fh (Fall history) which should be inverted if it represents risk.
    double score = ((data.acc ?? 100.0) * accWeight) +
        ((data.gyr ?? 100.0) * gyrWeight) +
        ((data.gait ?? 100.0) * gaitWeight) +
        ((data.psw ?? 100.0) * pswWeight) +
        ((data.ortho ?? 100.0) * orthoWeight) +
        ((data.plnt ?? 0.0) * plntWeight) +
        ((100 - (data.fh ?? 0.0)) * fhWeight);
    return MotionStabilityScore(score.clamp(0.0, 100.0));
  }
  
  WomensHealthScore _calculateLayer4(Layer4WomensHealthData data) {
    // Attempt to compute the new Layer 4 score
    final score = Layer4WomensHealthCalculator.calculateScore(data);
    
    // If it returns null due to privacy/edge-case gates, the HSI engine catches it 
    // and we return a neutral WomensHealthScore for now (the HSI weights logic handles 
    // renormalization via wData.isApplicable).
    if (score == null) {
      return WomensHealthScore(100.0, confidence: 1.0); // Neutral score
    }

    return score;
  }

  PredictionResult calculateRisk({
    required Layer1PhysiologyData pData,
    required Layer2RecoveryData rData,
    required Layer3MotionData mData,
    required Layer4WomensHealthData wData,
    required ContextFactors context,
  }) {
    // 1. Calculate P (Physiological Stability)
    final pScore = _calculateLayer1(pData);

    // 2. Calculate R (Behavioral Recovery) 
    final rScore = _calculateLayer2(rData, null);

    // 3. Calculate M (Motion Intelligence)
    final mScore = _calculateLayer3(mData);

    // 4. Calculate W Context adjustments
    final wScore = _calculateLayer4(wData);

    // 5. Base HSI (Health Stability Index computed with fixed baseline weights)
    double hsiBaseVal = (pScore.value * baseAlpha) +
        (rScore.value * baseBeta) +
        (mScore.value * baseGamma) +
        (wScore.value * baseDelta);
        
    HsiBase hsiBase = HsiBase(hsiBaseVal.clamp(0.0, 100.0));

    // 6. Adaptive Weight Engine
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

    // 7. Calculate HSI_adj
    double hsiAdjVal = (pScore.value * (finalWeights['physiological'] ?? 0)) +
        (rScore.value * (finalWeights['recovery'] ?? 0)) +
        (mScore.value * (finalWeights['motion'] ?? 0)) +
        (wScore.value * (finalWeights['womens_health'] ?? 0));
        
    HsiAdj hsiAdj = HsiAdj(hsiAdjVal.clamp(0.0, 100.0));

    // 8. Calculate FRS (Inverted Formula)
    double fhRateNormalized = ((mData.fh ?? 0.0) * 10.0).clamp(0.0, 100.0); // Placeholder
    
    // FRS-24 Weights
    double lambda1_24 = 0.20; // MO
    double lambda2_24 = 0.30; // RC
    double lambda3_24 = 0.40; // P
    double lambda4_24 = 0.10; // FH

    double frs24Val = (lambda1_24 * (100.0 - mScore.value)) +
                      (lambda2_24 * (100.0 - rScore.value)) +
                      (lambda3_24 * (100.0 - pScore.value)) +
                      (lambda4_24 * fhRateNormalized);
    Frs24 frs24 = Frs24(frs24Val.clamp(0.0, 100.0));

    // FRS-30 Weights
    double lambda1_30 = 0.40; // MO
    double lambda2_30 = 0.10; // RC
    double lambda3_30 = 0.10; // P
    double lambda4_30 = 0.40; // FH

    double frs30Val = (lambda1_30 * (100.0 - mScore.value)) +
                      (lambda2_30 * (100.0 - rScore.value)) +
                      (lambda3_30 * (100.0 - pScore.value)) +
                      (lambda4_30 * fhRateNormalized);
    Frs30 frs30 = Frs30(frs30Val.clamp(0.0, 100.0));

    // 9. Risk Classification
    RiskClassification classification;
    if (frs24.value <= 30) {
      classification = RiskClassification.low;
    } else if (frs24.value <= 60) {
      classification = RiskClassification.moderate;
    } else {
      classification = RiskClassification.high;
    }

    // 10. Generate XAI Reasoning Chain
    // (Note: reasoning_engine.dart is obsolete, ExplainabilityPayload is used below)
    
    // 11. Prediction Horizon and Coverage
    PredictionHorizon tau = PredictionHorizon(const Duration(days: 7)); // Example horizon
    CoverageScore q = CoverageScore(100.0); // Assuming 100% data coverage for now

    return PredictionResult(
      hsiBase: hsiBase,
      hsi: hsiAdj,
      frs24: frs24,
      frs30: frs30,
      riskLevel: classification,
      tau: tau,
      q: q,
    );
  }

  // Removed hardcoded v2 Pipeline Dependencies - baselines are now sourced from pData

  Future<FallRiskScoreV2Result?> calculateFRSv2({
    required Layer1PhysiologyData pData,
    required Layer2RecoveryData rData,
    required Layer3MotionData mData,
    required Layer4WomensHealthData wData,
    required BpSource bpSource,
    required ContextFactors context,
    required List<FallEvent> trailingFalls,
  }) async {
    // Step A: Evaluate Red-Flag Override (abort if true)
    bool isRedFlag = await redFlagService.checkCriticalThresholds(
      physiology: pData,
      motion: mData,
      escalationService: escalationService,
      corroborationService: corroborationService,
    );

    if (isRedFlag) {
      throw RedFlagEmergencyException('Critical health thresholds exceeded; FRS calculation aborted.');
    }

    // Step B: Build the ContextFactors payload from the user's profile and current trends
    // The `context` argument represents this payload. 
    bool hasSmartInsole = (mData.plnt != null);

    // Step C: Fetch global HSI weights and layer-specific weights from AdaptiveWeightEngine
    Map<String, double> pWeightsRaw = AdaptiveWeightEngine.getPhysiologyWeights(context);
    AdaptiveWeights pWeights = AdaptiveWeights(
      hr: pWeightsRaw['hr'] ?? 0.20,
      hrv: pWeightsRaw['hrv'] ?? 0.25,
      bp: pWeightsRaw['bp'] ?? 0.20,
      spO2: pWeightsRaw['spo2'] ?? 0.20,
      temp: pWeightsRaw['temp'] ?? 0.15,
    );
    Map<String, double> rWeights = AdaptiveWeightEngine.getRecoveryWeights(context);
    Map<String, double> mWeights = AdaptiveWeightEngine.getMotionWeights(context, hasSmartInsole: hasSmartInsole);
    Map<String, double> hsiWeights = AdaptiveWeightEngine.getHsiGlobalWeights(context, includeWomensHealth: wData.isApplicable);

    // Step D: Pass the layer-specific weights into Layer1Calculator, Layer2Calculator, and Layer3Calculator at the time of their execution.

    // --- Layer 1 Execution ---
    double rolling14DayMedianHR = pData.baselines?.rolling14DayMedianHR ?? 65.0;
    double rolling28DayMeanHRV = pData.baselines?.rolling28DayMeanHRV ?? 45.0;
    double rolling28DayStdDevHRV = pData.baselines?.rolling28DayStdDevHRV ?? 8.0;
    double baselineAdjustedTemp = pData.baselines?.baselineAdjustedTemp ?? 36.5;
    BpBaseline? hospitalBaseline = const BpBaseline(sys: 115.0, dia: 75.0); // Retain hospital mock for now

    double? currentSys = pData.sys ?? pData.bp;
    double? currentDia = pData.dia ?? (pData.bp != null && pData.bp! > 40 ? pData.bp! - 40 : pData.bp);

    Layer1Calculator layer1 = Layer1Calculator();
    Layer1Result layer1Result = layer1.calculateP(
      currentHR: pData.hr,
      rolling14DayMedianHR: rolling14DayMedianHR,
      currentHRV: pData.hrv,
      rolling28DayMeanHRV: rolling28DayMeanHRV,
      rolling28DayStdDevHRV: rolling28DayStdDevHRV,
      currentSpO2: pData.spo2,
      peripheralTemp: pData.temp,
      ambientTemp: 22.0, 
      baselineAdjustedTemp: baselineAdjustedTemp,
      currentSys: currentSys,
      currentDia: currentDia,
      bpSource: bpSource,
      hospitalBaseline: hospitalBaseline,
      weights: pWeights,
    );
    final PhysiologicalScore pScore = layer1Result.pScore;

    // --- Layer 2 Execution ---
    final rcScore = Layer2Calculator.calculateRC(data: rData, wPrime: rWeights);
    final actExp = rData.act != null ? ActivityDataTransformer.splitRawActivity(rData.act!.value).$2 : const ActivityExposure(100.0);

    // --- Layer 3 Execution ---
    final layer3Svc = Layer3MotionService(null);
    final moScore = layer3Svc.calculateMO(mData, wPrime: mWeights);
    final fhRate = layer3Svc.calculateFHRate(trailingFalls, actExp.value);

    // --- Layer 4 Execution ---
    final whScore = Layer4WomensHealthCalculator.calculateScore(wData);
    double whVal = whScore != null ? whScore.value : 100.0;

    // Step E: Use the global HSI weights (Alpha, Beta, Gamma, Delta) to calculate HSI_adj from the outputs of Layers 1-4.
    
    final hsiService = HsiAggregationService();
    
    // First calculate HsiBase (fixed baseline weights)
    final fixedBaseWeights = {
      'p': baseAlpha,
      'rc': baseBeta,
      'mo': baseGamma,
      'wh': baseDelta,
    };
    
    double hsiBaseVal = hsiService.computeHsiBase(
      p: pScore.value,
      rc: rcScore.value,
      mo: moScore.value,
      wh: (wData.isApplicable && whScore != null) ? whVal : null,
      fixedBaseWeights: fixedBaseWeights,
    );
    HsiBase hsiBase = HsiBase(hsiBaseVal);

    // Calculate HSI_adj using dynamic weights
    final dynamicWeights = {
      'p': hsiWeights['physiological'] ?? baseAlpha,
      'rc': hsiWeights['recovery'] ?? baseBeta,
      'mo': hsiWeights['motion'] ?? baseGamma,
      'wh': hsiWeights['womens_health'] ?? 0.0,
    };

    double hsiAdjVal = hsiService.computeHsiAdj(
      p: pScore.value,
      rc: rcScore.value,
      mo: moScore.value,
      wh: (wData.isApplicable && whScore != null) ? whVal : null,
      dynamicWeights: dynamicWeights,
    );
        
    HsiAdj hsiAdj = HsiAdj(hsiAdjVal);
    
    // Calculate Deltas (mocking baseline for now)
    final currentScores = {
      'p': pScore.value,
      'rc': rcScore.value,
      'mo': moScore.value,
      'wh': (wData.isApplicable && whScore != null) ? whVal : 0.0,
    };
    
    // Compute true physiological baseline from historical averages
    Layer1Result baselinePResult = layer1.calculateP(
      currentHR: rolling14DayMedianHR,
      rolling14DayMedianHR: rolling14DayMedianHR,
      currentHRV: rolling28DayMeanHRV,
      rolling28DayMeanHRV: rolling28DayMeanHRV,
      rolling28DayStdDevHRV: rolling28DayStdDevHRV,
      currentSpO2: 98.0, // Assumed healthy SpO2 baseline
      peripheralTemp: baselineAdjustedTemp,
      ambientTemp: 22.0,
      baselineAdjustedTemp: baselineAdjustedTemp,
      currentSys: hospitalBaseline?.sys ?? 120.0, // Standard healthy BP
      currentDia: hospitalBaseline?.dia ?? 80.0,
      bpSource: BpSource.hospitalBaseline,
      hospitalBaseline: hospitalBaseline,
      weights: pWeights,
    );

    // Provide personal baseline scores for the UI insight payload
    final baselineScores = {
      'p': baselinePResult.pScore.value,
      'rc': 90.0, // Standard healthy recovery baseline
      'mo': 90.0, // Standard healthy motion baseline
      'wh': (wData.isApplicable && whScore != null) ? 95.0 : 0.0,
    };
    final baseWeightsForExplainability = {
      'p': baseAlpha,
      'rc': baseBeta,
      'mo': baseGamma,
      'wh': baseDelta,
    };
    
    AttributionDeltas attributionDeltas = hsiService.computeExplainabilityDeltas(
      baselineScores: baselineScores,
      currentScores: currentScores,
      baseWeights: baseWeightsForExplainability,
      currentWeights: dynamicWeights,
    );

    // Final FRS (Inverted Formula)
    double fhRateNormalized = (fhRate.rate * 10.0).clamp(0.0, 100.0); // Normalizing the calculated FH rate

    // FRS-24 Weights (Actionable Alert Horizon)
    double lambda1_24 = 0.20; // MO
    double lambda2_24 = 0.30; // RC
    double lambda3_24 = 0.40; // P
    double lambda4_24 = 0.10; // FH

    double frs24Val = (lambda1_24 * (100.0 - moScore.value)) +
                      (lambda2_24 * (100.0 - rcScore.value)) +
                      (lambda3_24 * (100.0 - pScore.value)) +
                      (lambda4_24 * fhRateNormalized);
    Frs24 frs24 = Frs24(frs24Val.clamp(0.0, 100.0));

    // FRS-30 Weights (Trend-Risk Profile)
    double lambda1_30 = 0.40; // MO
    double lambda2_30 = 0.10; // RC
    double lambda3_30 = 0.10; // P
    double lambda4_30 = 0.40; // FH

    double frs30Val = (lambda1_30 * (100.0 - moScore.value)) +
                      (lambda2_30 * (100.0 - rcScore.value)) +
                      (lambda3_30 * (100.0 - pScore.value)) +
                      (lambda4_30 * fhRateNormalized);
    Frs30 frs30 = Frs30(frs30Val.clamp(0.0, 100.0));

    // Coverage Score (Q)
    double qNumerator = 0.0;
    double qDenominator = 0.0;

    if (pData.hr != null) qNumerator += hrWeight * baseAlpha;
    qDenominator += hrWeight * baseAlpha;
    if (pData.hrv != null) qNumerator += hrvWeight * baseAlpha;
    qDenominator += hrvWeight * baseAlpha;
    if (pData.sys != null && pData.dia != null) qNumerator += bpWeight * baseAlpha;
    qDenominator += bpWeight * baseAlpha;
    if (pData.spo2 != null) qNumerator += spo2Weight * baseAlpha;
    qDenominator += spo2Weight * baseAlpha;
    if (pData.temp != null) qNumerator += tempWeight * baseAlpha;
    qDenominator += tempWeight * baseAlpha;

    if (rData.slp != null) qNumerator += sleepDurWeight * baseBeta;
    qDenominator += sleepDurWeight * baseBeta;
    if (rData.slq != null) qNumerator += sleepQualWeight * baseBeta;
    qDenominator += sleepQualWeight * baseBeta;
    if (rData.act != null) qNumerator += activityWeight * baseBeta;
    qDenominator += activityWeight * baseBeta;
    if (rData.wkl != null) qNumerator += workoutWeight * baseBeta;
    qDenominator += workoutWeight * baseBeta;
    if (rData.str != null) qNumerator += stressWeight * baseBeta;
    qDenominator += stressWeight * baseBeta;

    if (mData.acc != null) qNumerator += accWeight * baseGamma;
    qDenominator += accWeight * baseGamma;
    if (mData.gyr != null) qNumerator += gyrWeight * baseGamma;
    qDenominator += gyrWeight * baseGamma;
    if (mData.gait != null) qNumerator += gaitWeight * baseGamma;
    qDenominator += gaitWeight * baseGamma;
    if (mData.psw != null) qNumerator += pswWeight * baseGamma;
    qDenominator += pswWeight * baseGamma;
    if (mData.ortho != null) qNumerator += orthoWeight * baseGamma;
    qDenominator += orthoWeight * baseGamma;
    if (mData.plnt != null) qNumerator += plntWeight * baseGamma;
    qDenominator += plntWeight * baseGamma;
    if (mData.fh != null) qNumerator += fhWeight * baseGamma;
    qDenominator += fhWeight * baseGamma;

    if (wData.isApplicable) {
      if (whScore != null) qNumerator += baseDelta;
      qDenominator += baseDelta;
    }

    double qVal = (qDenominator > 0) ? (qNumerator / qDenominator) * 100.0 : 100.0;
    qVal -= layer1Result.bpStalenessPenalty;
    CoverageScore q = CoverageScore(qVal.clamp(0.0, 100.0));

    // Coverage Details
    List<String> coverageDetails = [];
    if (layer1Result.bpStalenessPenalty > 0) {
      coverageDetails.add('BP sourced from last hospital visit (older than 14 days)');
    }
    if (!hasSmartInsole) {
      coverageDetails.add('Smart Insole disconnected, relying on phone motion only');
    }
    if (pData.hrv == null) coverageDetails.add('Missing data: HRV');
    if (rData.slq == null) coverageDetails.add('Missing data: Sleep Quality');
    if (coverageDetails.isEmpty) {
      coverageDetails.add('All inputs current and corroborated');
    }

    // Top Contributors
    Map<String, double> deviations = {
      'Physiology decline': baselineScores['p']! - currentScores['p']!,
      'Recovery decline': baselineScores['rc']! - currentScores['rc']!,
      'Motion Stability reduced': baselineScores['mo']! - currentScores['mo']!,
      'Women\'s Health factor': baselineScores['wh']! - currentScores['wh']!,
    };
    var sortedDeviations = deviations.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    List<String> topContributors = sortedDeviations.where((e) => e.value > 2).take(2).map((e) => e.key).toList();
    if (topContributors.isEmpty) topContributors.add('Stable metrics');

    String recommendationAction = 'Monitor vitals closely.';
    if (topContributors.any((c) => c.contains('Recovery'))) {
      recommendationAction = 'Prioritize sleep recovery today; avoid high-exertion activity until Recovery Score returns above personal baseline.';
    } else if (topContributors.any((c) => c.contains('Motion'))) {
      recommendationAction = 'Avoid stairs and high-strain activity.';
    }

    double hsiBaselineVal = (baselineScores['p']! * baseAlpha) + (baselineScores['rc']! * baseBeta) + (baselineScores['mo']! * baseGamma) + (baselineScores['wh']! * baseDelta);

    ExplainabilityPayload explainability = ExplainabilityPayload(
      hsiBase: hsiBaseVal.round(),
      hsiBaseline: hsiBaselineVal.round(),
      hsiAdj: hsiAdjVal.round(),
      attributionDeltas: attributionDeltas,
      frs24Score: frs24Val.round(),
      frs24Band: frs24.value.riskBand,
      topContributors: topContributors,
      coverageScoreQ: q.q,
      coverageDetails: coverageDetails,
      recommendationAction: recommendationAction,
    );

    // Prediction Horizon (Tau)
    PredictionHorizon tau = PredictionHorizon(const Duration(days: 7));

    return FallRiskScoreV2Result(
      hsiBase: hsiBase,
      hsiAdj: hsiAdj,
      frs24: frs24,
      frs30: frs30,
      pScore: pScore,
      rcScore: rcScore,
      moScore: moScore,
      whScore: whScore,
      fhRate: fhRate,
      predictionHorizon: tau,
      coverageScore: q,
      explainability: explainability,
    );
  }
}
