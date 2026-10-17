import 'package:flutter_test/flutter_test.dart';
import 'package:vital_monitoring/models/fall_prediction/context_factors.dart';
import 'package:vital_monitoring/models/fall_prediction/layer_inputs.dart';
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

final _engine = FallPredictionEngine(
  redFlagService: _NoRedFlag(),
  escalationService: _NoEscalation(),
  corroborationService: _NoCorroboration(),
);

Layer4WomensHealthData _noWh() => Layer4WomensHealthData(
      isApplicable: false,
      hasConsentedToWomensHealth: false,
      cycleState: CycleState.optedOut,
      daysSinceLastPeriod: 0,
      cycleLength: 28,
      isPMS: false,
    );

void main() {
  test('measure points add up to each layer score and layers add up to FRS-24', () async {
    final result = await _engine.calculateFRSv2(
      pData: Layer1PhysiologyData(
        hr: 84, hrv: 30, bp: null, spo2: 93, temp: 37.2, sys: 135, dia: 88,
        baselines: const Layer1Baselines(
          rolling14DayMedianHR: 66, rolling28DayMeanHRV: 45,
          rolling28DayStdDevHRV: 8, baselineAdjustedTemp: 36.4,
        ),
      ),
      rData: Layer2RecoveryData(
        slp: 60, slq: 40, act: const ActivityRecovery(35), wkl: 35, str: 50,
      ),
      mData: Layer3MotionData(
        acc: 2.3, gyr: 40, gait: 0.3, psw: null, ortho: null, plnt: null,
        fh: 1, actExp: const ActivityExposure(35),
      ),
      wData: _noWh(),
      bpSource: BpSource.none,
      context: ContextFactors(),
      trailingFalls: [
        FallEvent(timestamp: DateTime.now().subtract(const Duration(days: 20)), severity: 80),
      ],
    );

    final breakdown = result!.breakdown!;
    expect(breakdown.layers.map((l) => l.key), ['p', 'rc', 'mo']);

    for (final layer in breakdown.layers) {
      final sum = layer.measures.fold<double>(0, (s, m) => s + m.points);
      expect(sum, closeTo(layer.score, 1e-6), reason: layer.label);
      final shares = layer.measures.fold<double>(0, (s, m) => s + m.share);
      expect(shares, closeTo(1.0, 1e-9), reason: layer.label);
    }
    expect(breakdown.layers[0].score, closeTo(result.pScore.value, 1e-9));
    expect(breakdown.layers[1].score, closeTo(result.rcScore.value, 1e-9));
    expect(breakdown.layers[2].score, closeTo(result.moScore.value, 1e-9));

    final frsSum = breakdown.layers.fold<double>(0, (s, l) => s + l.frsPoints) +
        breakdown.fallHistory.frsPoints;
    expect(frsSum.clamp(0.0, 100.0), closeTo(result.frs24.value, 1e-9));
    expect(breakdown.fallHistory.falls, 1);
    expect(breakdown.fallHistory.weightedFalls, greaterThan(0.8));
  });

  test('unmeasured inputs get no share and a normal temperature scores high', () async {
    final result = await _engine.calculateFRSv2(
      pData: Layer1PhysiologyData(
        hr: 66, hrv: null, bp: null, spo2: null, temp: 36.5,
        baselines: const Layer1Baselines(
          rolling14DayMedianHR: 66, rolling28DayMeanHRV: 45,
          rolling28DayStdDevHRV: 8, baselineAdjustedTemp: 36.4,
        ),
      ),
      rData: Layer2RecoveryData(slp: null, slq: null, act: null, wkl: null, str: null),
      mData: Layer3MotionData(
        acc: null, gyr: null, gait: null, psw: null, ortho: null, plnt: null,
        fh: 0, actExp: const ActivityExposure(100),
      ),
      wData: _noWh(),
      bpSource: BpSource.none,
      context: ContextFactors(),
      trailingFalls: const [],
    );

    final physiology = result!.breakdown!.layers.first;
    final temp = physiology.measures.firstWhere((m) => m.key == 'temp');
    final hrv = physiology.measures.firstWhere((m) => m.key == 'hrv');
    expect(temp.subScore, greaterThan(90));
    expect(hrv.measured, isFalse);
    expect(hrv.share, 0);
    expect(result.breakdown!.layers[1].hasData, isFalse);
    expect(result.breakdown!.layers[1].score, 100);
  });
}
