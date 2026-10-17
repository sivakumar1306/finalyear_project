import 'dart:math' show exp, ln2, max;

import '../../models/fall_prediction/layer_inputs.dart';
import '../../models/fall_prediction/engine_outputs.dart';
import '../../models/fall_prediction/context_factors.dart';
import '../../models/fall_prediction/prediction_result.dart';
import '../../models/fall_prediction/score_breakdown.dart';
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
      // No ambient sensor, and baselineAdjustedTemp is a raw skin-temperature
      // median — subtracting a fixed 22 °C made every reading score 0.
      ambientTemp: 0.0,
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
      ambientTemp: 0.0,
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

    double frsMoImpact = lambda1_24 * (100.0 - moScore.value);
    double frsRcImpact = lambda2_24 * (100.0 - rcScore.value);
    double frsPImpact = lambda3_24 * (100.0 - pScore.value);
    double frsFhImpact = lambda4_24 * fhRateNormalized;

    double frs24Val = frsMoImpact + frsRcImpact + frsPImpact + frsFhImpact;
    Frs24 frs24 = Frs24(frs24Val.clamp(0.0, 100.0));

    Map<String, double> frsImpacts = {
      'Motion Instability': frsMoImpact,
      'Recovery Deficit': frsRcImpact,
      'Physiological Strain': frsPImpact,
      'Recent Fall History': frsFhImpact,
    };
    var sortedFrsImpacts = frsImpacts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    List<String> frsContributors = sortedFrsImpacts.where((e) => e.value > 2).take(2).map((e) => e.key).toList();
    if (frsContributors.isEmpty) frsContributors.add('Low Risk Factors');

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

    if (pData.hrv == null) coverageDetails.add('Wear your ring more often to track Heart Rate Variability (HRV).');
    if (rData.slq == null) coverageDetails.add('Wear your ring to bed to track your sleep quality.');
    if (fhRate.isBelowAmbulationFloor) {
      coverageDetails.add('Low walking activity. We need more movement data to accurately predict fall risk.');
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

    String recommendationAction = 'Let\'s get your devices connected so we can give you better insights!';
    if (topContributors.any((c) => c.contains('Recovery'))) {
      recommendationAction = 'Prioritize sleep recovery today; avoid high-exertion activity until Recovery Score returns above personal baseline.';
    } else if (topContributors.any((c) => c.contains('Motion'))) {
      recommendationAction = 'Avoid stairs and high-strain activity.';
    }

    double hsiBaselineVal = (baselineScores['p']! * baseAlpha) + (baselineScores['rc']! * baseBeta) + (baselineScores['mo']! * baseGamma) + (baselineScores['wh']! * baseDelta);

    Map<String, int> frsBreakdown = {};
    for (var entry in sortedFrsImpacts) {
      if (entry.value > 0.5) {
        frsBreakdown[entry.key] = entry.value.round();
      }
    }

    ExplainabilityPayload explainability = ExplainabilityPayload(
      hsiBase: hsiBaseVal.round(),
      hsiBaseline: hsiBaselineVal.round(),
      hsiAdj: hsiAdjVal.round(),
      attributionDeltas: attributionDeltas,
      frs24Score: frs24Val.round(),
      frs24Band: frs24.value.riskBand,
      topContributors: topContributors,
      frsContributors: frsContributors,
      coverageScoreQ: q.q,
      coverageDetails: coverageDetails,
      recommendationAction: recommendationAction,
      frsBreakdown: frsBreakdown,
    );

    // Prediction Horizon (Tau)
    // FRS-24 inherently has a 24-hour horizon; FRS-30 inherently has a 30-day horizon.
    // The predictionHorizon on the result is fixed to the 24-hour actionable alert.
    PredictionHorizon tau = PredictionHorizon(const Duration(days: 1));

    final breakdown = _buildBreakdown(
      pData: pData,
      rData: rData,
      mData: mData,
      wData: wData,
      bpSource: bpSource,
      hospitalBaseline: hospitalBaseline,
      currentSys: currentSys,
      currentDia: currentDia,
      pWeights: pWeights,
      rWeights: rWeights,
      mWeights: mWeights,
      pScore: pScore.value,
      rcScore: rcScore.value,
      moScore: moScore.value,
      whScore: whScore,
      trailingFalls: trailingFalls,
      ambulationHours: actExp.value,
      fhRate: fhRate,
      fhNormalized: fhRateNormalized,
      lambdaMo: lambda1_24,
      lambdaRc: lambda2_24,
      lambdaP: lambda3_24,
      lambdaFh: lambda4_24,
      frs24: frs24.value,
      frs30: frs30.value,
      coverage: q.q,
      coverageDetails: coverageDetails,
      hsi: hsiAdjVal,
      hsiWeights: dynamicWeights,
    );

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
      breakdown: breakdown,
    );
  }

  /// Shares of a layer score: each measured input's base weight renormalised
  /// over the measured inputs only (mirrors the layer calculators).
  static Map<String, double> _shares(Map<String, double> weights, Set<String> measured) {
    final total = measured.fold<double>(0.0, (sum, k) => sum + (weights[k] ?? 0.0));
    return {
      for (final k in weights.keys)
        k: (measured.contains(k) && total > 0) ? (weights[k] ?? 0.0) / total : 0.0,
    };
  }

  static String _n(double v, [int digits = 0]) => v.toStringAsFixed(digits);

  ScoreBreakdown _buildBreakdown({
    required Layer1PhysiologyData pData,
    required Layer2RecoveryData rData,
    required Layer3MotionData mData,
    required Layer4WomensHealthData wData,
    required BpSource bpSource,
    required BpBaseline hospitalBaseline,
    required double? currentSys,
    required double? currentDia,
    required AdaptiveWeights pWeights,
    required Map<String, double> rWeights,
    required Map<String, double> mWeights,
    required double pScore,
    required double rcScore,
    required double moScore,
    required WomensHealthScore? whScore,
    required List<FallEvent> trailingFalls,
    required double ambulationHours,
    required FallHistoryRate fhRate,
    required double fhNormalized,
    required double lambdaMo,
    required double lambdaRc,
    required double lambdaP,
    required double lambdaFh,
    required double frs24,
    required double frs30,
    required double coverage,
    required List<String> coverageDetails,
    required double hsi,
    required Map<String, double> hsiWeights,
  }) {
    // ── Layer 1: Physiology ──────────────────────────────────────────────
    final b = pData.baselines;
    final medianHr = b?.rolling14DayMedianHR ?? 65.0;
    final meanHrv = b?.rolling28DayMeanHRV ?? 45.0;
    final sdHrv = b?.rolling28DayStdDevHRV ?? 8.0;
    final baseTemp = b?.baselineAdjustedTemp ?? 36.5;
    final hasBp = currentSys != null && currentDia != null;
    final pW = {
      'hr': pWeights.hr,
      'hrv': pWeights.hrv,
      'spo2': pWeights.spO2,
      'temp': pWeights.temp,
      'bp': pWeights.bp,
    };
    final pShares = _shares(pW, {
      if (pData.hr != null) 'hr',
      if (pData.hrv != null) 'hrv',
      if (pData.spo2 != null) 'spo2',
      if (pData.temp != null) 'temp',
      if (hasBp) 'bp',
    });
    double? bpSub;
    if (hasBp) {
      final bp = normalizeBP(currentSys, currentDia, bpSource, hospitalBaseline: hospitalBaseline);
      bpSub = (bp.sysScore + bp.diaScore) / 2.0;
    }
    final useBpBaseline = bpSource == BpSource.hospitalBaseline;
    final physiology = LayerDetail(
      key: 'p',
      label: 'Physiology',
      description: 'How far today\'s vitals are from your personal baselines.',
      score: pScore,
      lambda: lambdaP,
      measures: [
        MeasureDetail(
          key: 'hr',
          label: 'Heart rate',
          reading: pData.hr != null ? '${_n(pData.hr!)} bpm' : null,
          reference: '14-day median ${_n(medianHr)} bpm',
          subScore: pData.hr != null ? normalizeHR(pData.hr!, medianHr) : null,
          baseWeight: pW['hr']!,
          share: pShares['hr']!,
          method: '100 at your median, falls to 0 at ±30% away from it.',
        ),
        MeasureDetail(
          key: 'hrv',
          label: 'Heart rate variability',
          reading: pData.hrv != null ? '${_n(pData.hrv!)} ms' : null,
          reference: '28-day mean ${_n(meanHrv)} ± ${_n(sdHrv)} ms',
          subScore: pData.hrv != null ? normalizeHRV(pData.hrv!, meanHrv, sdHrv) : null,
          baseWeight: pW['hrv']!,
          share: pShares['hrv']!,
          method: '100 at or above your mean; drops to 20 at 1.5 SD below it.',
        ),
        MeasureDetail(
          key: 'spo2',
          label: 'Blood oxygen',
          reading: pData.spo2 != null ? '${_n(pData.spo2!)} %' : null,
          reference: 'Healthy ≥ 95 %',
          subScore: pData.spo2 != null ? normalizeSpO2(pData.spo2!) : null,
          baseWeight: pW['spo2']!,
          share: pShares['spo2']!,
          method: '100 at 95 % or more, falls steeply to 0 at 90 %.',
        ),
        MeasureDetail(
          key: 'temp',
          label: 'Skin temperature',
          reading: pData.temp != null ? '${_n(pData.temp!, 1)} °C' : null,
          reference: 'Baseline ${_n(baseTemp, 1)} °C',
          subScore: pData.temp != null ? normalizeTemp(pData.temp!, 0.0, baseTemp) : null,
          baseWeight: pW['temp']!,
          share: pShares['temp']!,
          method: '100 at your baseline, 0 at ±1.5 °C away from it.',
        ),
        MeasureDetail(
          key: 'bp',
          label: 'Blood pressure',
          reading: hasBp ? '${_n(currentSys)}/${_n(currentDia)} mmHg' : null,
          reference: useBpBaseline
              ? 'Baseline ${_n(hospitalBaseline.sys)}/${_n(hospitalBaseline.dia)} mmHg'
              : 'Reference 120/80 mmHg',
          subScore: bpSub,
          baseWeight: pW['bp']!,
          share: pShares['bp']!,
          method: 'Average of systolic and diastolic: 100 at reference, 0 at ±33 %.',
        ),
      ],
    );

    // ── Layer 2: Recovery ────────────────────────────────────────────────
    final rW = {
      'slp': rWeights['slp'] ?? 0.30,
      'slq': rWeights['slq'] ?? 0.25,
      'act': rWeights['act'] ?? 0.20,
      'wkl': rWeights['wkl'] ?? 0.15,
      'str': rWeights['str'] ?? 0.10,
    };
    final rShares = _shares(rW, {
      if (rData.slp != null) 'slp',
      if (rData.slq != null) 'slq',
      if (rData.act != null) 'act',
      if (rData.wkl != null) 'wkl',
      if (rData.str != null) 'str',
    });
    final recovery = LayerDetail(
      key: 'rc',
      label: 'Recovery',
      description: 'Whether sleep, activity and stress let your body recover.',
      score: rcScore,
      lambda: lambdaRc,
      measures: [
        MeasureDetail(
          key: 'slp',
          label: 'Sleep duration',
          reading: rData.slp != null ? '≈ ${_n(rData.slp! * 8 / 100, 1)} h slept' : null,
          reference: 'Goal 8 h',
          subScore: rData.slp != null ? Layer2Calculator.normalizeSLP(rData.slp!) : null,
          baseWeight: rW['slp']!,
          share: rShares['slp']!,
          method: 'Hours slept ÷ 8 h, capped at 100.',
        ),
        MeasureDetail(
          key: 'slq',
          label: 'Sleep quality',
          reading: rData.slq != null ? '≈ ${_n(rData.slq! * 20 / 100)} % deep sleep' : null,
          reference: 'Target 20 % deep sleep',
          subScore: rData.slq != null ? Layer2Calculator.normalizeSLQ(rData.slq!) : null,
          baseWeight: rW['slq']!,
          share: rShares['slq']!,
          method: 'Deep-sleep share ÷ 20 %, capped at 100.',
        ),
        MeasureDetail(
          key: 'act',
          label: 'Daily activity',
          reading: rData.act != null ? '≈ ${_n(rData.act!.value * 100)} steps' : null,
          reference: 'Goal 10,000 steps',
          subScore: rData.act != null ? Layer2Calculator.normalizeACT(rData.act!) : null,
          baseWeight: rW['act']!,
          share: rShares['act']!,
          method: 'Steps ÷ 10,000, capped at 100.',
        ),
        MeasureDetail(
          key: 'wkl',
          label: 'Exertion load',
          reading: rData.wkl != null ? 'Load ${_n(rData.wkl!)} / 100' : null,
          reference: 'Lower load = more recovery',
          subScore: rData.wkl != null ? Layer2Calculator.normalizeWKL(rData.wkl!) : null,
          baseWeight: rW['wkl']!,
          share: rShares['wkl']!,
          method: 'Inverted: 100 − load.',
        ),
        MeasureDetail(
          key: 'str',
          label: 'Stress',
          reading: rData.str != null ? 'Stress ${_n(rData.str!)} / 100' : null,
          reference: 'Estimated from HRV (60 ms = no stress)',
          subScore: rData.str != null ? Layer2Calculator.normalizeSTR(rData.str!) : null,
          baseWeight: rW['str']!,
          share: rShares['str']!,
          method: 'Inverted: 100 − stress.',
        ),
      ],
    );

    // ── Layer 3: Motion ──────────────────────────────────────────────────
    final layer3 = Layer3MotionService(null);
    final hasMi = mData.acc != null;
    final hasMg = mData.gait != null && mData.gyr != null;
    final hasMb = mData.psw != null && mData.ortho != null && mData.gyr != null;
    final hasMp = mData.plnt != null;
    final mW = {
      'MI': mWeights['MI'] ?? 0.25,
      'MG': mWeights['MG'] ?? 0.25,
      'MB': mWeights['MB'] ?? 0.25,
      'MP': mWeights['MP'] ?? 0.25,
    };
    final mShares = _shares(mW, {
      if (hasMi) 'MI',
      if (hasMg) 'MG',
      if (hasMb) 'MB',
      if (hasMp) 'MP',
    });
    final motion = LayerDetail(
      key: 'mo',
      label: 'Motion',
      description: 'Impacts, walking pattern and balance from the ring and phone sensors.',
      score: moScore,
      lambda: lambdaMo,
      measures: [
        MeasureDetail(
          key: 'MI',
          label: 'Impact',
          reading: hasMi ? '${_n(mData.acc!, 2)} g peak' : null,
          reference: 'Stumble threshold 2.5 g',
          subScore: hasMi ? layer3.calculateMI(mData.acc!) : null,
          baseWeight: mW['MI']!,
          share: mShares['MI']!,
          method: 'S-curve: ~100 well below 2.5 g, 50 at 2.5 g, ~0 above 3 g.',
        ),
        MeasureDetail(
          key: 'MG',
          label: 'Walking pattern',
          reading: hasMg ? 'Variability ${_n(mData.gait!, 2)}' : (mData.gait != null ? 'Variability ${_n(mData.gait!, 2)}' : null),
          reference: hasMg ? 'Rotation ${_n(mData.gyr!, 1)} °/s' : 'Needs step pattern + rotation peak',
          subScore: hasMg ? layer3.calculateMG(mData.gait!, mData.gyr!) : null,
          baseWeight: mW['MG']!,
          share: mShares['MG']!,
          method: '100 − variability × 100, minus 0.2 × rotation speed.',
        ),
        MeasureDetail(
          key: 'MB',
          label: 'Balance',
          reading: hasMb ? 'Sway ${_n(mData.psw!, 1)}, posture drop ${_n(mData.ortho!)}' : null,
          reference: 'Needs a sway test and posture-change data',
          subScore: hasMb ? layer3.calculateMB(mData.psw!, mData.ortho!, mData.gyr!) : null,
          baseWeight: mW['MB']!,
          share: mShares['MB']!,
          method: 'Half postural sway, half drop after standing up.',
        ),
        MeasureDetail(
          key: 'MP',
          label: 'Foot pressure',
          reading: hasMp ? 'CoP deviation ${_n(mData.plnt!, 1)}' : null,
          reference: 'Needs a smart insole',
          subScore: hasMp ? layer3.calculateMP(mData.plnt!) : null,
          baseWeight: mW['MP']!,
          share: mShares['MP']!,
          method: '100 − 15 × centre-of-pressure deviation.',
        ),
      ],
    );

    // ── Fall history ─────────────────────────────────────────────────────
    final now = DateTime.now();
    var weighted = 0.0;
    for (final fall in trailingFalls) {
      var daysAgo = now.difference(fall.timestamp).inDays.toDouble();
      if (daysAgo < 0) daysAgo = 0;
      weighted += exp(-ln2 * (daysAgo / 90.0));
    }
    final history = FallHistoryDetail(
      falls: trailingFalls.length,
      weightedFalls: weighted,
      ambulationHours: max(ambulationHours, 168.0),
      belowAmbulationFloor: fhRate.isBelowAmbulationFloor,
      rate: fhRate.rate,
      normalized: fhNormalized,
      lambda: lambdaFh,
    );

    return ScoreBreakdown(
      layers: [physiology, recovery, motion],
      fallHistory: history,
      womensHealth: WomensHealthDetail(
        applicable: wData.isApplicable && whScore != null,
        score: whScore?.value,
        daysSinceLastPeriod: wData.isApplicable ? wData.daysSinceLastPeriod : null,
        isPMS: wData.isPMS,
        confidence: whScore?.confidence,
      ),
      frs24: frs24,
      frs30: frs30,
      coverage: coverage,
      coverageDetails: coverageDetails,
      hsi: hsi,
      hsiWeights: hsiWeights,
    );
  }
}
