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

    test('fcs clamps to 0-100', () {
      final result = engine.calculateRisk(
        pData: PhysiologicalData(
          heartRate: 0,
          hrv: 0,
          bloodPressure: 0,
          spo2: 0,
          skinTemperature: 0,
        ),
        rData: BehavioralData(
          sleepDuration: 0,
          sleepQuality: 0,
          dailyActivity: 0,
          workoutLoad: 0,
          stress: 100,
        ),
        mData: MotionData(
          impact: 100,
          orientation: 0,
          recoveryAttempts: 0,
          fallHistory: 100,
          accelerationMagnitude: 50,
        ),
        wData: _whOff(),
        context: ContextFactors(previousFallsFactor: 3.0),
      );
      expect(result.fcs, inInclusiveRange(0, 100));
      expect(result.hsi, inInclusiveRange(0, 100));
    });

    test('pms lowers womens health score when applicable', () {
      final base = engine.calculateRisk(
        pData: _goodPhysio(),
        rData: _goodRecovery(),
        mData: _stableMotion(),
        wData: WomensHealthData(
          isApplicable: true,
          daysSinceLastPeriod: 25,
          cycleLength: 28,
          isPMS: false,
        ),
        context: ContextFactors(),
      );
      final pms = engine.calculateRisk(
        pData: _goodPhysio(),
        rData: _goodRecovery(),
        mData: _stableMotion(),
        wData: WomensHealthData(
          isApplicable: true,
          daysSinceLastPeriod: 25,
          cycleLength: 28,
          isPMS: true,
        ),
        context: ContextFactors(),
      );
      expect(pms.hsi, lessThan(base.hsi));
      expect(pms.fcs, greaterThan(base.fcs));
    });

    test('high classification when fcs above 60', () {
      final result = engine.calculateRisk(
        pData: PhysiologicalData(
          heartRate: 10,
          hrv: 10,
          bloodPressure: 10,
          spo2: 10,
          skinTemperature: 10,
        ),
        rData: BehavioralData(
          sleepDuration: 10,
          sleepQuality: 10,
          dailyActivity: 10,
          workoutLoad: 10,
          stress: 95,
        ),
        mData: MotionData(
          impact: 95,
          orientation: 5,
          recoveryAttempts: 5,
          fallHistory: 90,
          accelerationMagnitude: 30,
        ),
        wData: _whOff(),
        context: ContextFactors(previousFallsFactor: 2.0),
      );
      expect(result.riskLevel, RiskClassification.high);
      expect(result.fcs, greaterThan(60));
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

    test('motion issues recommend avoiding stairs', () {
      final chain = ReasoningEngine.generateReasoningChain(
        40,
        _goodPhysio(),
        _goodRecovery(),
        MotionData(
          impact: 80,
          orientation: 20,
          recoveryAttempts: 50,
          fallHistory: 10,
          accelerationMagnitude: 15,
        ),
      );
      expect(chain.any((s) => s.toLowerCase().contains('motion')), isTrue);
      expect(
        chain.any((s) => s.contains('Avoid stairs')),
        isTrue,
      );
    });

    test('stress surfaces recommendation to monitor', () {
      final chain = ReasoningEngine.generateReasoningChain(
        55,
        PhysiologicalData(
          heartRate: 95,
          hrv: 95,
          bloodPressure: 95,
          spo2: 95,
          skinTemperature: 95,
        ),
        BehavioralData(
          sleepDuration: 90,
          sleepQuality: 90,
          dailyActivity: 80,
          workoutLoad: 70,
          stress: 90,
        ),
        _stableMotion(),
      );
      expect(chain.any((s) => s.toLowerCase().contains('stress')), isTrue);
    });
  });
}
