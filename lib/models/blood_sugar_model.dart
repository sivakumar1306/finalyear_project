class BloodSugarReading {
  final DateTime timestamp;
  final int minSugar;
  final int maxSugar;
  final int hour; // 0-23

  const BloodSugarReading({
    required this.timestamp,
    required this.minSugar,
    required this.maxSugar,
    required this.hour,
  });

  factory BloodSugarReading.fromMap(Map<String, dynamic> m) => BloodSugarReading(
        // DB column is measured_at (see 20260901000000_phase2_detailed_health.sql).
        timestamp:
            DateTime.tryParse(m['measured_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(
                (m['measured_at'] as num? ?? 0).toInt() * 1000),
        minSugar: (m['min_sugar'] as num? ?? 0).toInt(),
        maxSugar: (m['max_sugar'] as num? ?? 0).toInt(),
        hour: (m['hour'] as num? ?? 0).toInt(),
      );

  Map<String, dynamic> toMap(String userId) => {
        'user_id': userId,
        'measured_at': timestamp.toUtc().toIso8601String(),
        'min_sugar': minSugar,
        'max_sugar': maxSugar,
        'hour': hour,
      };
}
