import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vital_monitoring/services/fall_prediction/layer3_motion.dart';

void main() {
  Map<String, dynamic> nativeRow({
    required int detectedAtMs,
    double confidence = 0.8,
    String? metadataJson,
    bool simulated = false,
  }) {
    return {
      'id': 1,
      'confidence': confidence,
      'corroborated': true,
      'corroborationSource': 'hr_spike',
      'metadataJson': metadataJson ??
          (simulated
              ? jsonEncode({'simulated': true})
              : jsonEncode(
                  {'peakG': 3.4, 'peakGyro': 4.2, 'stillnessRatio': 0.6})),
      'detectedAt': detectedAtMs,
      'eventType': 'DETECTED',
    };
  }

  group('parseNativeFallEvents', () {
    test('maps confidence to severity and timestamp', () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final rows = [
        nativeRow(detectedAtMs: nowMs, confidence: 0.82),
      ];
      final events = Layer3MotionService.parseNativeFallEvents(
        rows,
        since: DateTime.now().subtract(const Duration(days: 365)),
      );
      expect(events, hasLength(1));
      expect(events.first.severity, closeTo(82.0, 1e-9));
      expect(
        events.first.timestamp.millisecondsSinceEpoch,
        equals(nowMs),
      );
    });

    test('excludes simulated dev rows', () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final rows = [
        nativeRow(detectedAtMs: nowMs, simulated: true),
      ];
      final events = Layer3MotionService.parseNativeFallEvents(
        rows,
        since: DateTime.now().subtract(const Duration(days: 365)),
      );
      expect(events, isEmpty);
    });

    test('excludes rows older than since and sorts newest first', () {
      final now = DateTime.now();
      final rows = [
        nativeRow(
          detectedAtMs:
              now.subtract(const Duration(days: 400)).millisecondsSinceEpoch,
        ),
        nativeRow(
          detectedAtMs:
              now.subtract(const Duration(days: 10)).millisecondsSinceEpoch,
          confidence: 0.6,
        ),
        nativeRow(
          detectedAtMs:
              now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
          confidence: 0.9,
        ),
      ];
      final events = Layer3MotionService.parseNativeFallEvents(
        rows,
        since: now.subtract(const Duration(days: 365)),
      );
      expect(events, hasLength(2));
      expect(events.first.severity, closeTo(90.0, 1e-9));
      expect(events.last.severity, closeTo(60.0, 1e-9));
    });

    test('skips malformed rows without throwing', () {
      final events = Layer3MotionService.parseNativeFallEvents(
        [
          {'confidence': 0.9},
          {'detectedAt': 'not-a-number'},
        ],
        since: DateTime.now().subtract(const Duration(days: 365)),
      );
      expect(events, isEmpty);
    });
  });

  group('stepsBaseline', () {
    final today = DateTime(2026, 10, 27);
    Map<DateTime, int> history(int days, int Function(int back) steps) => {
          for (var back = 1; back <= days; back++)
            DateTime(2026, 10, 27 - back): steps(back),
        };

    test('last full day against the median of the 28 days before it', () {
      final daily = history(29, (back) => back == 1 ? 3000 : 8000 + (back.isEven ? 400 : -400));
      final b = Layer3MotionService.stepsBaseline(daily, today: today);
      expect(b.steps, 3000);
      expect(b.median, 8000);
      // MAD 400 -> 1.4826 * 400 = 593
      expect(b.spread, closeTo(593.04, 0.01));
    });

    test('baseline needs 7 earlier days; the reading is kept', () {
      final daily = history(5, (_) => 6000);
      final b = Layer3MotionService.stepsBaseline(daily, today: today);
      expect(b.steps, 6000);
      expect(b.median, isNull);
      expect(b.spread, isNull);
    });

    test('spread never below 500 steps', () {
      final daily = history(20, (_) => 7000);
      expect(Layer3MotionService.stepsBaseline(daily, today: today).spread, 500.0);
    });

    test('ignores today and skips back to the last day with steps', () {
      final daily = {DateTime(2026, 10, 27): 900, DateTime(2026, 10, 24): 5000};
      expect(Layer3MotionService.stepsBaseline(daily, today: today).steps, 5000);
    });
  });

  group('motion sub-scores', () {
    final svc = Layer3MotionService(null);

    test('steps: dead zone, then linear to 0 at 3 SD below the median', () {
      expect(svc.calculateSteps(8000, 8000, 1000), 100.0);
      expect(svc.calculateSteps(7500, 8000, 1000), 100.0); // z = 0.5
      expect(svc.calculateSteps(6500, 8000, 1000), closeTo(60.0, 1e-9)); // z = 1.5
      expect(svc.calculateSteps(4000, 8000, 1000), 0.0);
      expect(svc.calculateSteps(12000, 8000, 1000), 100.0); // more steps is not risk
    });

    test('near-falls: 100, 50, 0', () {
      expect(svc.calculateNearFalls(0), 100.0);
      expect(svc.calculateNearFalls(1), 50.0);
      expect(svc.calculateNearFalls(3), 0.0);
    });
  });
}
