import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sundr/services/fall_prediction/layer3_motion.dart';

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

  group('recentMotionPeak', () {
    test('returns newest peaks within 24h', () {
      final now = DateTime.now();
      final rows = [
        nativeRow(
          detectedAtMs:
              now.subtract(const Duration(hours: 20)).millisecondsSinceEpoch,
          metadataJson:
              jsonEncode({'peakG': 3.0, 'peakGyro': 4.0, 'stillnessRatio': 0.5}),
        ),
        nativeRow(
          detectedAtMs:
              now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
          metadataJson:
              jsonEncode({'peakG': 3.6, 'peakGyro': 5.0, 'stillnessRatio': 0.7}),
        ),
      ];
      final peak = Layer3MotionService.recentMotionPeak(rows);
      expect(peak, isNotNull);
      expect(peak!.acc, closeTo(3.6, 1e-9));
      expect(peak.gyr, closeTo(5.0, 1e-9));
    });

    test('null when peaks are stale, simulated-only, or peakless', () {
      final now = DateTime.now();
      expect(
        Layer3MotionService.recentMotionPeak([
          nativeRow(
            detectedAtMs:
                now.subtract(const Duration(hours: 30)).millisecondsSinceEpoch,
          ),
        ]),
        isNull,
      );
      expect(
        Layer3MotionService.recentMotionPeak([
          nativeRow(
            detectedAtMs: now.millisecondsSinceEpoch,
            simulated: true,
          ),
        ]),
        isNull,
      );
      expect(
        Layer3MotionService.recentMotionPeak([
          nativeRow(
            detectedAtMs: now.millisecondsSinceEpoch,
            metadataJson: jsonEncode({'foo': 1}),
          ),
        ]),
        isNull,
      );
      expect(Layer3MotionService.recentMotionPeak([]), isNull);
    });
  });

  group('gaitVariabilityFromStepSlots', () {
    final endOfDay = DateTime(2026, 9, 19, 23, 59);

    test('null when insufficient active slots', () {
      expect(
        Layer3MotionService.gaitVariabilityFromStepSlots([], now: endOfDay),
        isNull,
      );
      expect(
        Layer3MotionService.gaitVariabilityFromStepSlots(
          [100, 120, 90, 110, 95],
          now: endOfDay,
        ),
        isNull,
      );
    });

    test('zero for steady walking pattern', () {
      final slots = List<int>.filled(12, 100);
      expect(
        Layer3MotionService.gaitVariabilityFromStepSlots(slots, now: endOfDay),
        equals(0.0),
      );
    });

    test('positive but capped for erratic pattern', () {
      final slots = [5, 5, 800, 5, 5, 900, 5, 5, 5, 700, 5, 5];
      final gait = Layer3MotionService.gaitVariabilityFromStepSlots(
        slots,
        now: endOfDay,
      );
      expect(gait, isNotNull);
      expect(gait!, greaterThan(0.0));
      expect(gait, lessThanOrEqualTo(0.5));
    });

    test('ignores future slots beyond now', () {
      // Only 3 active slots before noon -> insufficient -> null, even though
      // the full day array holds many active slots later.
      final slots = List<int>.filled(96, 0);
      slots[10] = 100;
      slots[11] = 120;
      slots[12] = 90;
      for (var i = 60; i < 80; i++) {
        slots[i] = 200;
      }
      expect(
        Layer3MotionService.gaitVariabilityFromStepSlots(
          slots,
          now: DateTime(2026, 9, 19, 12, 0),
        ),
        isNull,
      );
    });
  });
}
