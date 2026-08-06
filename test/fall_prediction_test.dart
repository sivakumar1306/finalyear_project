import 'package:flutter_test/flutter_test.dart';
import 'package:qring_flutter/models/fall_prediction/behavioral_data.dart';
import 'package:qring_flutter/models/fall_prediction/context_factors.dart';
import 'package:qring_flutter/models/fall_prediction/motion_data.dart';
import 'package:qring_flutter/models/fall_prediction/physiological_data.dart';
import 'package:qring_flutter/models/fall_prediction/prediction_result.dart';
import 'package:qring_flutter/models/fall_prediction/womens_health_data.dart';
import 'package:qring_flutter/services/fall_prediction/fall_prediction_engine.dart';
import 'package:qring_flutter/services/fall_prediction/reasoning_engine.dart';

PhysiologicalData _goodPhysio() => PhysiologicalData(
      heartRate: 90,
      hrv: 90,
      bloodPressure: 90,
      spo2: 95,
      skinTemperature: 90,
    );

BehavioralData _goodRecovery() => BehavioralData(
      sleepDuration: 90,
      sleepQuality: 90,
      dailyActivity: 80,
      workoutLoad: 70,
      stress: 10,
    );

MotionData _stableMotion() => MotionData(
      impact: 5,
      orientation: 95,
      recoveryAttempts: 90,
      fallHistory: 0,
      accelerationMagnitude: 1.0,
    );

WomensHealthData _whOff() => WomensHealthData(
      isApplicable: false,
      daysSinceLastPeriod: 0,
      cycleLength: 28,
      isPMS: false,
    );

void main() {
  group('FallPredictionEngine', () {
    final engine = FallPredictionEngine();

    test('healthy metrics classify as low risk', () {
      final result = engine.calculateRisk(
        pData: _goodPhysio(),
        rData: _goodRecovery(),
        mData: _stableMotion(),
        wData: _whOff(),
        context: ContextFactors(),
      );
      expect(result.riskLevel, RiskClassification.low);
      expect(result.fcs, lessThanOrEqualTo(30));
      expect(result.hsi, greaterThan(70));
      expect(result.reasoningChain, isNotEmpty);
    });

    test('poor motion + fall history raises risk', () {
      final result = engine.calculateRisk(
        pData: PhysiologicalData(
          heartRate: 40,
          hrv: 30,
          bloodPressure: 40,
          spo2: 70,
          skinTemperature: 40,
        ),
        rData: BehavioralData(
          sleepDuration: 30,
          sleepQuality: 25,
          dailyActivity: 20,
          workoutLoad: 10,
          stress: 90,
        ),
        mData: MotionData(
          impact: 90,
          orientation: 20,
          recoveryAttempts: 10,
          fallHistory: 80,
          accelerationMagnitude: 20,
        ),
        wData: _whOff(),
        context: ContextFactors(
          previousFallsFactor: 1.5,
          sleepDebtFactor: 1.3,
        ),
      );
      expect(result.riskLevel, isNot(RiskClassification.low));
      expect(result.fcs, greaterThan(30));
    });
  });

  group('ReasoningEngine', () {
    test('stable metrics produce keep-up message', () {
      final chain = ReasoningEngine.generateReasoningChain(
        90,
        _goodPhysio(),
        _goodRecovery(),
        _stableMotion(),
      );
      expect(chain.first, contains('HSI:'));
      expect(chain.any((s) => s.contains('stable') || s.contains('Keep up')), isTrue);
    });

    test('sleep debt surfaces in chain', () {
      final chain = ReasoningEngine.generateReasoningChain(
        50,
        _goodPhysio(),
        BehavioralData(
          sleepDuration: 20,
          sleepQuality: 15,
          dailyActivity: 80,
          workoutLoad: 70,
          stress: 10,
        ),
        _stableMotion(),
      );
      expect(chain.any((s) => s.toLowerCase().contains('sleep')), isTrue);
      expect(chain.any((s) => s.startsWith('Recommendation:')), isTrue);
    });
  });
}
