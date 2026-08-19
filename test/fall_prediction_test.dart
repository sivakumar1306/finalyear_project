import 'package:flutter_test/flutter_test.dart';
import 'package:sundr/models/fall_prediction/context_factors.dart';
import 'package:sundr/models/fall_prediction/layer_inputs.dart';
import 'package:sundr/services/fall_prediction/fall_prediction_engine.dart';
import 'package:sundr/services/fall_prediction/layer1_physiology.dart';

import 'package:sundr/services/fall_prediction/red_flag_override.dart';

class MockRedFlagOverrideService extends RedFlagOverrideService {
  @override
  Future<bool> checkCriticalThresholds({
    required Layer1PhysiologyData physiology,
    required Layer3MotionData motion,
    required EscalationService escalationService,
    required CorroborationService corroborationService,
  }) async {
    return false;
  }
}

class MockEscalationService implements EscalationService {
  @override
  void triggerAlert({required EscalationLadder ladder, required String reason}) {}
}

class MockCorroborationService implements CorroborationService {
  @override
  Future<bool> verifyDualSource(CorroborationSource source) async => true;
}

void main() {
  group('FallPredictionEngine V2', () {
    late FallPredictionEngine engine;

    setUp(() {
      engine = FallPredictionEngine(
        redFlagService: MockRedFlagOverrideService(),
        escalationService: MockEscalationService(),
        corroborationService: MockCorroborationService(),
      );
    });

    test('healthy metrics calculate successfully', () async {
      final pData = Layer1PhysiologyData(
        hr: 65, hrv: 45, bp: 120, spo2: 98, temp: 36.5, sys: 120, dia: 80,
        baselines: const Layer1Baselines(
          rolling14DayMedianHR: 65, rolling28DayMeanHRV: 45, rolling28DayStdDevHRV: 8, baselineAdjustedTemp: 36.5,
        )
      );
      final rData = Layer2RecoveryData(
        slp: 80, slq: 80, act: const ActivityRecovery(80), wkl: 20, str: 10,
        baselines: const Layer2Baselines(baselineSlp: 80, baselineSlq: 80, baselineAct: 80, baselineWkl: 20, baselineStr: 10)
      );
      final mData = Layer3MotionData(
        acc: 1.0, gyr: 10, gait: 10, psw: 10, ortho: 5, plnt: 10, fh: 0, actExp: const ActivityExposure(100),
        baselines: const Layer3Baselines(baselineAcc: 1.0, baselineGyr: 10, baselineGait: 10, baselinePsw: 10, baselineOrtho: 5, baselinePlnt: 10)
      );
      final wData = Layer4WomensHealthData(
        isApplicable: false, hasConsentedToWomensHealth: false, cycleState: CycleState.optedOut, daysSinceLastPeriod: 0, cycleLength: 28, isPMS: false,
      );

      final result = await engine.calculateFRSv2(
        pData: pData, rData: rData, mData: mData, wData: wData, bpSource: BpSource.none, context: ContextFactors(), trailingFalls: [],
      );

      expect(result, isNotNull);
      expect(result!.frs24, isNotNull);
    });
  });
}
