import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vital_monitoring/models/fall_prediction/context_factors.dart';
import 'package:vital_monitoring/models/fall_prediction/layer_inputs.dart';
import 'package:vital_monitoring/models/fall_prediction/prediction_result.dart';
import 'package:vital_monitoring/screens/fall_prediction/fall_score_details_screen.dart';
import 'package:vital_monitoring/services/fall_prediction/fall_prediction_engine.dart';
import 'package:vital_monitoring/services/fall_prediction/layer1_physiology.dart';
import 'package:vital_monitoring/services/fall_prediction/layer3_motion.dart';
import 'package:vital_monitoring/services/fall_prediction/red_flag_override.dart';

class _NoRedFlag extends RedFlagOverrideService {
  @override
  Future<bool> checkCriticalThresholds({
    required Layer1PhysiologyData physiology,
    required Layer3MotionData motion,
    required EscalationService escalationService,
    required CorroborationService corroborationService,
  }) async => false;
}

class _NoEscalation implements EscalationService {
  @override
  void triggerAlert({required EscalationLadder ladder, required String reason}) {}
}

class _NoCorroboration implements CorroborationService {
  @override
  Future<bool> verifyDualSource(CorroborationSource source) async => false;
}

Future<PredictionResult> _realResult({required bool womensHealth}) async {
  final engine = FallPredictionEngine(
    redFlagService: _NoRedFlag(),
    escalationService: _NoEscalation(),
    corroborationService: _NoCorroboration(),
  );
  final v2 = await engine.calculateFRSv2(
    pData: Layer1PhysiologyData(
      hr: 84, hrv: 30, bp: null, spo2: 93, temp: 37.2, sys: 135, dia: 88,
      baselines: const Layer1Baselines(
        rolling14DayMedianHR: 66, rolling28DayMeanHRV: 45,
        rolling28DayStdDevHRV: 8, baselineAdjustedTemp: 36.4,
      ),
    ),
    rData: Layer2RecoveryData(slp: 60, slq: 40, act: const ActivityRecovery(35), wkl: 35, str: 50),
    mData: Layer3MotionData(
      steps: 4000, stepsMedian: 8000, stepsSpread: 1000, nearFalls14d: 1,
      fh: 1, actExp: const ActivityExposure(35),
    ),
    wData: Layer4WomensHealthData(
      isApplicable: womensHealth,
      hasConsentedToWomensHealth: womensHealth,
      cycleState: womensHealth ? CycleState.active : CycleState.optedOut,
      daysSinceLastPeriod: 24,
      cycleLength: 28,
      isPMS: womensHealth,
    ),
    bpSource: BpSource.none,
    context: ContextFactors(),
    trailingFalls: [
      FallEvent(timestamp: DateTime.now().subtract(const Duration(days: 20)), severity: 80),
    ],
  );
  return PredictionResult(
    hsiBase: v2!.hsiBase,
    hsi: v2.hsiAdj,
    frs24: v2.frs24,
    frs30: v2.frs30,
    riskLevel: RiskClassification.moderate,
    tau: v2.predictionHorizon,
    q: v2.coverageScore,
    explainability: v2.explainability,
    breakdown: v2.breakdown,
  );
}

Future<void> _pump(WidgetTester tester, PredictionResult result) async {
  await tester.binding.setSurfaceSize(const Size(320, 20000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: Size(320, 20000), textScaler: TextScaler.linear(1.3)),
      child: MaterialApp(home: FallScoreDetailsView(result: result)),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('score details render every part without overflow', (tester) async {
    final result = await tester.runAsync(() => _realResult(womensHealth: true));
    await _pump(tester, result!);
    expect(tester.takeException(), isNull);
    for (final text in ['HOW THE SCORE ADDS UP', 'Physiology', 'Recovery', 'Motion', 'Fall history',
        'Heart rate', 'Sleep duration', 'Daily steps', 'Near-falls', 'Women\'s health', 'DATA COVERAGE']) {
      expect(find.text(text, findRichText: true), findsWidgets, reason: text);
    }
    expect(find.text('= ${result.frs24.value.round()}'), findsOneWidget);
  });

  testWidgets('without women\'s health data the card says it is not included', (tester) async {
    final result = await tester.runAsync(() => _realResult(womensHealth: false));
    await _pump(tester, result!);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Not included'), findsOneWidget);
  });
}
