import 'package:flutter_test/flutter_test.dart';
import 'package:qring_flutter/services/local_vitals_service.dart';

void main() {
  group('LocalVitalsService date helpers', () {
    test('dateStr zero-pads month and day', () {
      expect(LocalVitalsService.dateStr(DateTime(2026, 1, 5)), '2026-01-05');
      expect(LocalVitalsService.dateStr(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('dayStartMs is local midnight', () {
      final d = DateTime(2026, 8, 6, 15, 30);
      final ms = LocalVitalsService.dayStartMs(d);
      final start = DateTime.fromMillisecondsSinceEpoch(ms);
      expect(start.year, 2026);
      expect(start.month, 8);
      expect(start.day, 6);
      expect(start.hour, 0);
      expect(start.minute, 0);
      expect(start.second, 0);
    });

    test('dayEndMs is end of local day', () {
      final d = DateTime(2026, 8, 6, 10);
      final ms = LocalVitalsService.dayEndMs(d);
      final end = DateTime.fromMillisecondsSinceEpoch(ms);
      expect(end.year, 2026);
      expect(end.month, 8);
      expect(end.day, 6);
      expect(end.hour, 23);
      expect(end.minute, 59);
      expect(end.second, 59);
    });

    test('dayStartMs < dayEndMs for same calendar day', () {
      final d = DateTime(2026, 3, 15);
      expect(
        LocalVitalsService.dayStartMs(d),
        lessThan(LocalVitalsService.dayEndMs(d)),
      );
    });
  });

  group('LocalVitalsService.hasData', () {
    final svc = LocalVitalsService();

    test('true when count > 0', () {
      expect(svc.hasData({'count': 3, 'avg': 0, 'steps': 0}), isTrue);
    });

    test('true when steps > 0', () {
      expect(svc.hasData({'count': 0, 'avg': 0, 'steps': 100}), isTrue);
    });

    test('true when avg > 0', () {
      expect(svc.hasData({'count': 0, 'avg': 72.5, 'steps': 0}), isTrue);
    });

    test('false when empty summary', () {
      expect(svc.hasData({}), isFalse);
      expect(svc.hasData({'count': 0, 'avg': 0, 'steps': 0}), isFalse);
    });
  });
}
