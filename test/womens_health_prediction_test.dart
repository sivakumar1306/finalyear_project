import 'package:flutter_test/flutter_test.dart';
import 'package:qring_flutter/models/womens_health_models.dart';
import 'package:qring_flutter/services/womens_health_prediction_service.dart';

void main() {
  final service = WomenHealthPredictionService();
  final fixedNow = DateTime(2026, 6, 1);

  HealthMetrics metrics({
    double temperature = 50,
    double hrv = 50,
    double heartRate = 50,
    double sleepQuality = 50,
    double stress = 50,
    double activityLevel = 50,
  }) =>
      HealthMetrics(
        temperature: temperature,
        hrv: hrv,
        heartRate: heartRate,
        sleepQuality: sleepQuality,
        stress: stress,
        activityLevel: activityLevel,
      );

  group('phase estimation (normalized 0-100 scale)', () {
    test('late luteal when temp high, hrv low, rhr elevated', () {
      final result = service.predictCycle(
        lastMenstrualPeriod: null,
        averageCycleLength: 28,
        metrics: metrics(temperature: 60, hrv: 40, heartRate: 60),
        hasHistory: false,
        now: fixedNow,
      );
      expect(result.estimatedPhase, MenstrualPhase.lateLuteal);
      expect(result.isVitalsOnlyPath, isTrue);
    });

    test('follicular when hrv high and rhr low', () {
      final result = service.predictCycle(
        lastMenstrualPeriod: null,
        averageCycleLength: 28,
        metrics: metrics(temperature: 50, hrv: 60, heartRate: 40),
        hasHistory: false,
        now: fixedNow,
      );
      expect(result.estimatedPhase, MenstrualPhase.follicular);
    });

    test('ovulation when temp rising and rhr elevated', () {
      final result = service.predictCycle(
        lastMenstrualPeriod: null,
        averageCycleLength: 28,
        metrics: metrics(temperature: 55, hrv: 50, heartRate: 60),
        hasHistory: false,
        now: fixedNow,
      );
      expect(result.estimatedPhase, MenstrualPhase.ovulation);
    });

    test('menstrual when activity low and other rules miss', () {
      final result = service.predictCycle(
        lastMenstrualPeriod: null,
        averageCycleLength: 28,
        metrics: metrics(
          temperature: 50,
          hrv: 50,
          heartRate: 50,
          activityLevel: 20,
        ),
        hasHistory: false,
        now: fixedNow,
      );
      expect(result.estimatedPhase, MenstrualPhase.menstrual);
    });
  });

  group('calendar path', () {
    test('base prediction is LMP + cycle length', () {
      final lmp = DateTime(2026, 5, 1);
      final result = service.predictCycle(
        lastMenstrualPeriod: lmp,
        averageCycleLength: 28,
        metrics: metrics(temperature: 50, hrv: 60, heartRate: 40),
        hasHistory: true,
        now: fixedNow,
      );
      expect(result.isVitalsOnlyPath, isFalse);
      expect(result.basePrediction, DateTime(2026, 5, 29));
      expect(
        result.ovulationDate,
        result.finalPrediction.subtract(const Duration(days: 14)),
      );
      expect(
        result.fertileWindowStart,
        result.ovulationDate.subtract(const Duration(days: 5)),
      );
      expect(
        result.fertileWindowEnd,
        result.ovulationDate.add(const Duration(days: 1)),
      );
    });
  });
}
