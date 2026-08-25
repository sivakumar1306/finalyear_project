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
        timestamp: DateTime.tryParse(m['timestamp'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(
                (m['timestamp'] as num? ?? 0).toInt() * 1000),
        minSugar: (m['min_sugar'] as num? ?? 0).toInt(),
        maxSugar: (m['max_sugar'] as num? ?? 0).toInt(),
        hour: (m['hour'] as num? ?? 0).toInt(),
      );

  Map<String, dynamic> toMap(String userId) => {
        'user_id': userId,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'min_sugar': minSugar,
        'max_sugar': maxSugar,
        'hour': hour,
      };
}
