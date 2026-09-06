/// Pure hourly bucketing — replaces 10× sums/counts loops.
/// No Widget, no BuildContext.
abstract class HourlyAggregator {
  /// 24-slot hourly average for int values (HR, SpO2, Stress)
  static List<int> aggregateInt(
    List<Map<String, dynamic>> readings, {
    required String valueKey,
    String measuredAtKey = 'measuredAt',
    int slots = 24,
    int Function(int hour, int minute)? slotFor,
  }) {
    final result = List<int>.filled(slots, 0);
    final sums = List<int>.filled(slots, 0);
    final counts = List<int>.filled(slots, 0);
    for (final m in readings) {
      final v = (m[valueKey] as num?)?.toInt() ?? 0;
      final at = (m[measuredAtKey] as num?)?.toInt() ?? 0;
      if (v <= 0 || at <= 0) continue;
      final dt = DateTime.fromMillisecondsSinceEpoch(at);
      final slot = slotFor != null ? slotFor(dt.hour, dt.minute) : dt.hour;
      if (slot < 0 || slot >= slots) continue;
      sums[slot] += v;
      counts[slot] += 1;
    }
    for (int i = 0; i < slots; i++) {
      if (counts[i] > 0) result[i] = (sums[i] / counts[i]).round();
    }
    return result;
  }

  /// Double variant for temperature
  static List<double> aggregateDouble(
    List<Map<String, dynamic>> readings, {
    required String valueKey,
    String measuredAtKey = 'measuredAt',
    int slots = 24,
    int Function(int hour, int minute)? slotFor,
  }) {
    final result = List<double>.filled(slots, 0);
    final sums = List<double>.filled(slots, 0);
    final counts = List<int>.filled(slots, 0);
    for (final m in readings) {
      final v = (m[valueKey] as num?)?.toDouble() ?? 0;
      final at = (m[measuredAtKey] as num?)?.toInt() ?? 0;
      if (v <= 0 || at <= 0) continue;
      final dt = DateTime.fromMillisecondsSinceEpoch(at);
      final slot = slotFor != null ? slotFor(dt.hour, dt.minute) : dt.hour;
      if (slot < 0 || slot >= slots) continue;
      sums[slot] += v;
      counts[slot] += 1;
    }
    for (int i = 0; i < slots; i++) {
      if (counts[i] > 0) result[i] = sums[i] / counts[i];
    }
    return result;
  }

  static List<int> aggregateHrv(List<Map<String, dynamic>> readings) =>
      aggregateInt(readings, valueKey: 'valueMs', slots: 48, slotFor: (h, m) => (h * 60 + m) ~/ 30);

  static ({List<int> sbp, List<int> dbp}) aggregateBp(List<Map<String, dynamic>> readings) {
    final sbpRes = List<int>.filled(24, 0);
    final dbpRes = List<int>.filled(24, 0);
    final sbpSums = List<int>.filled(24, 0);
    final dbpSums = List<int>.filled(24, 0);
    final counts = List<int>.filled(24, 0);
    for (final m in readings) {
      final sbp = (m['systolic'] as num? ?? m['valueSbp'] as num? ?? 0).toInt();
      final dbp = (m['diastolic'] as num? ?? m['valueDbp'] as num? ?? 0).toInt();
      final at = (m['measuredAt'] as num?)?.toInt() ?? 0;
      if (sbp <= 0 || dbp <= 0 || at <= 0) continue;
      final h = DateTime.fromMillisecondsSinceEpoch(at).hour;
      sbpSums[h] += sbp;
      dbpSums[h] += dbp;
      counts[h] += 1;
    }
    for (int h = 0; h < 24; h++) {
      if (counts[h] > 0) {
        sbpRes[h] = (sbpSums[h] / counts[h]).round();
        dbpRes[h] = (dbpSums[h] / counts[h]).round();
      }
    }
    return (sbp: sbpRes, dbp: dbpRes);
  }

  /// 96 → 24 hourly for steps
  static List<double> toHourlyInt(List<int> slots96) {
    assert(slots96.length == 96);
    return List.generate(24, (h) => slots96.sublist(h * 4, h * 4 + 4).fold(0, (a, b) => a + b).toDouble());
  }

  static List<double> toHourlyDouble(List<double> slots96) {
    assert(slots96.length == 96);
    return List.generate(24, (h) => slots96.sublist(h * 4, h * 4 + 4).fold(0.0, (a, b) => a + b));
  }
}
