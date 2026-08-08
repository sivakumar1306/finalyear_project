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
  static const double baseAlpha = 0.35; // Physiological
  static const double baseBeta = 0.30;  // Recovery
  static const double baseGamma = 0.20; // Motion
  static const double baseDelta = 0.15; // Women's Health

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
    
    BpBaseline? hospitalBaseline;
    if (pData.baselines?.baselineSys != null && pData.baselines?.baselineDia != null) {
      hospitalBaseline = BpBaseline(sys: pData.baselines!.baselineSys!, dia: pData.baselines!.baselineDia!);
    } else {
      hospitalBaseline = const BpBaseline(sys: 115.0, dia: 75.0); // Fallback
    }

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
    double tempTrend = 0.0;
    double hrvTrend = 0.0;
    double slpTrend = 0.0;

    if (pData.temp != null && pData.baselines != null) {
      tempTrend = pData.temp! - pData.baselines!.baselineAdjustedTemp;
    }
    if (pData.hrv != null && pData.baselines != null && pData.baselines!.rolling28DayMeanHRV > 0) {
      hrvTrend = (pData.hrv! - pData.baselines!.rolling28DayMeanHRV) / pData.baselines!.rolling28DayMeanHRV;
    }
    if (rData.slp != null && rData.baselines != null && rData.baselines!.baselineSlp > 0) {
      slpTrend = (rData.slp! - rData.baselines!.baselineSlp) / rData.baselines!.baselineSlp;
    }

    final whScore = Layer4WomensHealthCalculator.calculateScore(
      wData, 
      tempTrend: tempTrend,
      hrvTrend: hrvTrend,
      slpTrend: slpTrend,
    );
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
      currentSys: hospitalBaseline.sys, // Standard healthy BP
      currentDia: hospitalBaseline.dia,
      bpSource: BpSource.hospitalBaseline,
      hospitalBaseline: hospitalBaseline,
      weights: pWeights,
    );

    // Compute true recovery baseline
    double rcBaseline = 90.0;
    if (rData.baselines != null) {
      final baseRData = Layer2RecoveryData(
        slp: rData.baselines!.baselineSlp,
        slq: rData.baselines!.baselineSlq,
        act: ActivityRecovery(rData.baselines!.baselineAct),
        wkl: rData.baselines!.baselineWkl,
        str: rData.baselines!.baselineStr,
      );
      rcBaseline = Layer2Calculator.calculateRC(data: baseRData, wPrime: rWeights).value;
    }

    // Compute true motion baseline
    double moBaseline = 90.0;
    if (mData.baselines != null) {
      final baseMData = Layer3MotionData(
        acc: mData.baselines!.baselineAcc,
        gyr: mData.baselines!.baselineGyr,
        gait: mData.baselines!.baselineGait,
        psw: mData.baselines!.baselinePsw,
        ortho: mData.baselines!.baselineOrtho,
        plnt: mData.baselines!.baselinePlnt,
        fh: 0.0, // Baseline assumes 0 fall history
        actExp: const ActivityExposure(100.0), // Standard exposure
      );
      moBaseline = layer3Svc.calculateMO(baseMData, wPrime: mWeights).value;
    }

    // Provide personal baseline scores for the UI insight payload
    final baselineScores = {
      'p': baselinePResult.pScore.value,
      'rc': rcBaseline,
      'mo': moBaseline,
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
    // Fall History Normalization: anchor the "100" ceiling to 1 fall per 100 ambulation-hours (0.01 falls/hour)
    double fhRateNormalized = (fhRate.rate * 10000.0).clamp(0.0, 100.0); 

    // FRS-24 Weights (Actionable Alert Horizon)
    double lambda1_24 = 0.35; // MO
    double lambda2_24 = 0.15; // RC
    double lambda3_24 = 0.20; // P
    double lambda4_24 = 0.30; // FH

    double frs24Val = (lambda1_24 * (100.0 - moScore.value)) +
                      (lambda2_24 * (100.0 - rcScore.value)) +
                      (lambda3_24 * (100.0 - pScore.value)) +
                      (lambda4_24 * fhRateNormalized);
    Frs24 frs24 = Frs24(frs24Val.clamp(0.0, 100.0));

    // FRS-30 Weights (Trend-Risk Profile)
    // Uses rolling baseline scores to represent the 30-day longitudinal trend/slope
    double lambda1_30 = 0.35; // MO
    double lambda2_30 = 0.15; // RC
    double lambda3_30 = 0.20; // P
    double lambda4_30 = 0.30; // FH

    // Explicit slope penalty: if current score is worse than baseline, risk increases.
    // The penalty is half of the deviation, modeling a negative longitudinal trajectory.
    double moSlopePenalty = (baselineScores['mo']! > moScore.value) ? (baselineScores['mo']! - moScore.value) * 0.5 : 0.0;
    double rcSlopePenalty = (baselineScores['rc']! > rcScore.value) ? (baselineScores['rc']! - rcScore.value) * 0.5 : 0.0;
    double pSlopePenalty = (baselineScores['p']! > pScore.value) ? (baselineScores['p']! - pScore.value) * 0.5 : 0.0;

    double frs30Val = (lambda1_30 * (100.0 - baselineScores['mo']! + moSlopePenalty)) +
                      (lambda2_30 * (100.0 - baselineScores['rc']! + rcSlopePenalty)) +
                      (lambda3_30 * (100.0 - baselineScores['p']! + pSlopePenalty)) +
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

    double moNumerator = 0.0;
    double moDenominator = 1.25; // Sum of base motion sub-weights (0.25 + 0.35 + 0.40 + 0.25)
    
    if (mData.acc != null) {
      moNumerator += 0.25; // w_MI
    }
    if (mData.gait != null && mData.gyr != null) {
      moNumerator += 0.35; // w_MG
    } else if (mData.gait != null || mData.gyr != null) {
      moNumerator += 0.175; // partial w_MG
    }
    
    if (mData.psw != null && mData.ortho != null && mData.gyr != null) {
      moNumerator += 0.40; // w_MB
    } else {
      if (mData.psw != null) moNumerator += 0.133;
      if (mData.ortho != null) moNumerator += 0.133;
      if (mData.gyr != null && mData.gait == null) moNumerator += 0.133; // partial w_MB
    }
    
    if (mData.plnt != null) moNumerator += 0.25; // w_MP
    
    qNumerator += (moNumerator / moDenominator) * baseGamma;
    qDenominator += baseGamma;

    // Fall History is evaluated against its FRS weight (lambda4_24), independent of Motion
    if (mData.fh != null) {
      if (!fhRate.isBelowAmbulationFloor) {
        qNumerator += lambda4_24;
      }
      qDenominator += lambda4_24;
    }

    if (wData.isApplicable) {
      if (whScore != null) qNumerator += baseDelta;
      qDenominator += baseDelta;
    }

    double qVal = (qDenominator > 0) ? (qNumerator / qDenominator) * 100.0 : 100.0;
    qVal = (qVal - layer1Result.bpStalenessPenalty).clamp(0.0, 100.0);
    CoverageScore q = CoverageScore(qVal);

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
    if (fhRate.isBelowAmbulationFloor) {
      coverageDetails.add('Sedentary user (Ambulation < 168h/yr). Fall Risk prediction confidence reduced.');
    }
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
    // FRS-24 inherently has a 24-hour horizon; FRS-30 inherently has a 30-day horizon.
    // The predictionHorizon on the result is fixed to the 24-hour actionable alert.
    PredictionHorizon tau = PredictionHorizon(const Duration(days: 1));

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
