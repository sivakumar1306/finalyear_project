import 'package:flutter_test/flutter_test.dart';
import 'package:vital_monitoring/models/health_data.dart';
import 'package:vital_monitoring/models/womens_health_models.dart';

void main() {
  group('HrSummary', () {
    test('fromMap parses fields', () {
      final s = HrSummary.fromMap({
        'date': '2026-08-01',
        'avg_hr': 72,
        'min_hr': 55,
        'max_hr': 110,
        'sample_count': 40,
      });
      expect(s.avg, 72);
      expect(s.min, 55);
      expect(s.max, 110);
      expect(s.sampleCount, 40);
      expect(s.date, DateTime(2026, 8, 1));
    });

    test('toMap includes user and date', () {
      final s = HrSummary(
        date: DateTime(2026, 3, 5),
        avg: 70,
        min: 50,
        max: 100,
        sampleCount: 10,
      );
      final m = s.toMap('user-1');
      expect(m['user_id'], 'user-1');
      expect(m['date'], '2026-03-05');
      expect(m['avg_hr'], 70);
    });
  });

  group('Spo2Summary / StepsSummary', () {
    test('Spo2Summary fromMap', () {
      final s = Spo2Summary.fromMap({
        'date': '2026-01-02',
        'avg_spo2': 97,
        'min_spo2': 94,
        'max_spo2': 99,
        'sample_count': 12,
      });
      expect(s.avg, 97);
      expect(s.min, 94);
    });

    test('StepsSummary fromMap', () {
      final s = StepsSummary.fromMap({
        'date': '2026-01-02',
        'steps': 8000,
        'calories': 300,
        'distance_m': 5200.5,
      });
      expect(s.steps, 8000);
      expect(s.calories, 300);
      expect(s.distanceM, 5200.5);
    });
  });

  group('BpReading / StressReading / TempReading', () {
    test('BpReading map round-trip fields', () {
      final at = DateTime.utc(2026, 6, 1, 12);
      final r = BpReading(
        systolic: 120,
        diastolic: 80,
        measuredAt: at,
        source: 'ring',
      );
      final m = r.toMap('u1');
      expect(m['systolic'], 120);
      expect(m['diastolic'], 80);
      expect(m['source'], 'ring');
      final back = BpReading.fromMap(m);
      expect(back.systolic, 120);
      expect(back.diastolic, 80);
    });

    test('StressReading label from value when missing', () {
      expect(StressReading.fromMap({'stress_value': 20}).label, 'Relaxed');
      expect(StressReading.fromMap({'stress_value': 50}).label, 'Normal');
      expect(StressReading.fromMap({'stress_value': 70}).label, 'Elevated');
      expect(StressReading.fromMap({'stress_value': 90}).label, 'High');
    });

    test('TempReading fromMap', () {
      final t = TempReading.fromMap({
        'value_c': 36.6,
        'measured_at': '2026-06-01T10:00:00.000Z',
        'source': 'auto',
      });
      expect(t.valueC, 36.6);
      expect(t.source, 'auto');
    });
  });

  group('HrvSummary', () {
    test('fromMap and toMap', () {
      final s = HrvSummary.fromMap({
        'date': '2026-04-01',
        'avg_hrv': 45,
        'min_hrv': 30,
        'max_hrv': 70,
        'sample_count': 8,
      });
      expect(s.avg, 45);
      final m = s.toMap('uid');
      expect(m['avg_hrv'], 45);
      expect(m['date'], '2026-04-01');
    });
  });

  group('womens HealthMetrics / PredictionResult json', () {
    test('HealthMetrics json round-trip', () {
      final m = HealthMetrics(
        temperature: 55,
        hrv: 48,
        heartRate: 52,
        sleepQuality: 70,
        stress: 40,
        activityLevel: 60,
      );
      final back = HealthMetrics.fromJson(m.toJson());
      expect(back.temperature, 55);
      expect(back.hrv, 48);
      expect(back.activityLevel, 60);
    });

    test('PredictionResult json round-trip', () {
      final r = PredictionResult(
        basePrediction: DateTime(2026, 7, 1),
        finalPrediction: DateTime(2026, 7, 2),
        ovulationDate: DateTime(2026, 6, 18),
        fertileWindowStart: DateTime(2026, 6, 13),
        fertileWindowEnd: DateTime(2026, 6, 19),
        confidenceScore: 82.5,
        confidenceLevel: 'High',
        estimatedPhase: MenstrualPhase.follicular,
        explainableReasons: const ['Higher HRV recovery'],
        isVitalsOnlyPath: true,
        phaseRemainingDays: 14,
      );
      final back = PredictionResult.fromJson(r.toJson());
      expect(back.estimatedPhase, MenstrualPhase.follicular);
      expect(back.confidenceScore, 82.5);
      expect(back.isVitalsOnlyPath, isTrue);
      expect(back.phaseRemainingDays, 14);
      expect(back.explainableReasons, ['Higher HRV recovery']);
    });

    test('MenstrualPhase display names', () {
      expect(MenstrualPhase.menstrual.displayName, contains('Menstrual'));
      expect(MenstrualPhase.ovulation.displayName, contains('Ovulation'));
    });
  });
}
