import 'package:flutter_test/flutter_test.dart';
import 'package:sundr/models/womens_health_models.dart';
import 'package:sundr/services/womens_health_prediction_service.dart';

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

    test('late luteal + low hrv shifts period earlier by 1 day', () {
      final lmp = DateTime(2026, 5, 1);
      final result = service.predictCycle(
        lastMenstrualPeriod: lmp,
        averageCycleLength: 28,
        metrics: metrics(temperature: 60, hrv: 40, heartRate: 60),
        hasHistory: true,
        now: fixedNow,
      );
      expect(result.estimatedPhase, MenstrualPhase.lateLuteal);
      expect(result.basePrediction, DateTime(2026, 5, 29));
      expect(result.finalPrediction, DateTime(2026, 5, 28));
    });

    test('high stress and poor sleep delay cycle by 2 days', () {
      final lmp = DateTime(2026, 5, 1);
      final result = service.predictCycle(
        lastMenstrualPeriod: lmp,
        averageCycleLength: 28,
        metrics: metrics(
          temperature: 50,
          hrv: 60,
          heartRate: 40,
          stress: 70,
          sleepQuality: 30,
        ),
        hasHistory: true,
        now: fixedNow,
      );
      expect(result.estimatedPhase, MenstrualPhase.follicular);
      expect(result.finalPrediction, DateTime(2026, 5, 31));
    });

    test('high activity delays cycle by 1 day', () {
      final lmp = DateTime(2026, 5, 1);
      final result = service.predictCycle(
        lastMenstrualPeriod: lmp,
        averageCycleLength: 28,
        metrics: metrics(
          temperature: 50,
          hrv: 60,
          heartRate: 40,
          activityLevel: 80,
        ),
        hasHistory: true,
        now: fixedNow,
      );
      expect(result.finalPrediction, DateTime(2026, 5, 30));
    });
  });

  group('vitals-only path remaining days', () {
    test('follicular uses 14 remaining days from now', () {
      final result = service.predictCycle(
        lastMenstrualPeriod: null,
        averageCycleLength: 28,
        metrics: metrics(temperature: 50, hrv: 60, heartRate: 40),
        hasHistory: false,
        now: fixedNow,
      );
      expect(result.phaseRemainingDays, 14);
      expect(result.finalPrediction, fixedNow.add(const Duration(days: 14)));
    });

    test('menstrual uses 2 remaining days', () {
      final result = service.predictCycle(
        lastMenstrualPeriod: null,
        averageCycleLength: 28,
        metrics: metrics(activityLevel: 20),
        hasHistory: false,
        now: fixedNow,
      );
      expect(result.phaseRemainingDays, 2);
      expect(result.finalPrediction, fixedNow.add(const Duration(days: 2)));
    });
  });

  group('confidence', () {
    test('history path scores higher than vitals-only', () {
      final withHistory = service.predictCycle(
        lastMenstrualPeriod: DateTime(2026, 5, 1),
        averageCycleLength: 28,
        metrics: metrics(temperature: 50, hrv: 60, heartRate: 40),
        hasHistory: true,
        now: fixedNow,
      );
      final vitalsOnly = service.predictCycle(
        lastMenstrualPeriod: null,
        averageCycleLength: 28,
        metrics: metrics(temperature: 50, hrv: 60, heartRate: 40),
        hasHistory: false,
        now: fixedNow,
      );
      expect(withHistory.confidenceScore, greaterThan(vitalsOnly.confidenceScore));
      expect(withHistory.confidenceLevel, isNotEmpty);
    });
  });
}
