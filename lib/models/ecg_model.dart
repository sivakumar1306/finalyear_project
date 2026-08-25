class EcgSample {
  final DateTime measuredAt;
  final int avgHeartRate;
  final List<int> dataList; // raw ECG points (decimated)
  final int type; // 0 single, 1 continuous

  const EcgSample({
    required this.measuredAt,
    required this.avgHeartRate,
    required this.dataList,
    this.type = 0,
  });

  factory EcgSample.fromMap(Map<String, dynamic> m) => EcgSample(
        measuredAt:
            DateTime.tryParse(m['measured_at'] as String? ?? '') ?? DateTime.now(),
        avgHeartRate: (m['avg_heart'] as num? ?? 0).toInt(),
        dataList: (m['data_list'] as List? ?? [])
            .map((e) => (e as num).toInt())
            .toList(),
        type: (m['type'] as num? ?? 0).toInt(),
      );

  Map<String, dynamic> toMap(String userId) => {
        'user_id': userId,
        'measured_at': measuredAt.toUtc().toIso8601String(),
        'avg_heart': avgHeartRate,
        'data_list': dataList,
        'type': type,
      };
}
