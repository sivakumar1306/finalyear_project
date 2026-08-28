class BreathMethod {
  final String id;
  final String name;
  final String category;
  final int inhaleMs;
  final int holdAfterInhaleMs;
  final int exhaleMs;
  final int holdAfterExhaleMs;
  final String description;

  const BreathMethod({
    required this.id,
    required this.name,
    required this.category,
    required this.inhaleMs,
    required this.holdAfterInhaleMs,
    required this.exhaleMs,
    required this.holdAfterExhaleMs,
    this.description = '',
  });

  int get cycleMs =>
      inhaleMs + holdAfterInhaleMs + exhaleMs + holdAfterExhaleMs;

  static const List<BreathMethod> catalog = [
    BreathMethod(
      id: 'balance_equal',
      name: 'Equal Breathing',
      category: 'Balance',
      inhaleMs: 4000,
      holdAfterInhaleMs: 0,
      exhaleMs: 4000,
      holdAfterExhaleMs: 0,
      description: '4s in · 4s out — calm focus.',
    ),
    BreathMethod(
      id: 'box_4_4_4_4',
      name: 'Box Breathing',
      category: 'Focus',
      inhaleMs: 4000,
      holdAfterInhaleMs: 4000,
      exhaleMs: 4000,
      holdAfterExhaleMs: 4000,
      description: '4-4-4-4 — Navy SEAL box.',
    ),
    BreathMethod(
      id: 'bellows',
      name: 'Bellows',
      category: 'Energy',
      inhaleMs: 1000,
      holdAfterInhaleMs: 0,
      exhaleMs: 1000,
      holdAfterExhaleMs: 0,
      description: '1s rapid — energize.',
    ),
    BreathMethod(
      id: 'taichi',
      name: 'Tai Chi',
      category: 'Recovery',
      inhaleMs: 4000,
      holdAfterInhaleMs: 1000,
      exhaleMs: 6000,
      holdAfterExhaleMs: 1000,
      description: '4-1-6-1 — recovery.',
    ),
  ];

  static BreathMethod byId(String id) =>
      catalog.firstWhere((m) => m.id == id, orElse: () => catalog.first);
}

class BreathSession {
  final String methodId;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationS;
  final int? avgHr;
  final int? subjectiveFeeling; // 1-5

  const BreathSession({
    required this.methodId,
    required this.startedAt,
    required this.endedAt,
    required this.durationS,
    this.avgHr,
    this.subjectiveFeeling,
  });

  factory BreathSession.fromMap(Map<String, dynamic> m) => BreathSession(
        methodId: m['method_id'] as String? ?? 'balance_equal',
        startedAt: DateTime.tryParse(m['started_at'] as String? ?? '') ??
            DateTime.now(),
        endedAt: DateTime.tryParse(m['ended_at'] as String? ?? '') ??
            DateTime.now(),
        durationS: (m['duration_s'] as num? ?? 0).toInt(),
        avgHr: (m['average_hr'] as num?)?.toInt(),
        subjectiveFeeling: (m['subjective_feeling'] as num?)?.toInt(),
      );

  Map<String, dynamic> toMap(String userId) => {
        'user_id': userId,
        'method_id': methodId,
        'started_at': startedAt.toUtc().toIso8601String(),
        'ended_at': endedAt.toUtc().toIso8601String(),
        'duration_s': durationS,
        if (avgHr != null) 'average_hr': avgHr,
        if (subjectiveFeeling != null) 'subjective_feeling': subjectiveFeeling,
      };
}
