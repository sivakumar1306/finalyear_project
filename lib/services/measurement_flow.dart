/// Manual measurement flow engine — pure validation + message mapping.
/// Widgets keep `setState`/`SnackBar`/`Navigator`; all thresholds/messages here.
/// Replaces 6×40-line `_startMeasurement` copies.
abstract class MeasurementFlow {
  static const int hrMin = 30;
  static const int hrMax = 220;

  static bool isValidHr(int v) => v >= hrMin && v <= hrMax;

  static String errorMessage(Object e) {
    final s = e.toString();
    if (s.contains('BUSY')) {
      return 'Another measurement is in progress — wait and retry.';
    }
    if (s.contains('TIMEOUT')) {
      return 'Measurement timed out — keep ring on finger.';
    }
    return 'Measurement failed: $e';
  }

  static String emptyMessage(String vital, String raw) =>
      '$vital measurement returned no data — keep ring snug and retry. Raw: $raw';

  /// Extract int value trying multiple keys (ring firmware varies: value/spo2/bloodOxygen etc).
  static int extractInt(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = (m[k] as num?)?.toInt() ?? 0;
      if (v > 0) return v;
    }
    return 0;
  }
}
