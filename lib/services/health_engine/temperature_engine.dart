import 'dart:convert';

class TempReading {
  final DateTime time;
  final double valueC;
  const TempReading({required this.time, required this.valueC});
}

class TemperatureEngine {
  static List<TempReading> parseTempReadings(String jsonStr, DateTime selectedDate) {
    final readings = <TempReading>[];
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is List && decoded.isNotEmpty) {
        for (final item in decoded) {
          final m = item as Map<String, dynamic>;
          final ts = (m['mTime'] as num?)?.toInt() ?? (m['a'] as num?)?.toInt();
          var val = (m['mValue'] as num?)?.toDouble() ?? (m['b'] as num?)?.toDouble();
          if (ts == null || val == null || val <= 0) continue;
          if (val > 100) val /= 10;
          readings.add(TempReading(time: DateTime.fromMillisecondsSinceEpoch(ts * 1000).toLocal(), valueC: val));
        }
      } else if (decoded is Map<String, dynamic>) {
        final rawVals = (decoded['mValues'] as List<dynamic>?) ?? (decoded['d'] as List<dynamic>?);
        final spanSec = (decoded['mTimeSpan'] as num?)?.toInt() ?? (decoded['b'] as num?)?.toInt() ?? 5;
        if (rawVals != null) {
          final base = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
          for (int i = 0; i < rawVals.length; i++) {
            var v = (rawVals[i] as num).toDouble();
            if (v <= 0) continue;
            if (v > 100) v /= 10;
            readings.add(TempReading(time: base.add(Duration(seconds: i * spanSec)), valueC: v));
          }
        }
      }
    } catch (_) {}
    return readings;
  }
}
