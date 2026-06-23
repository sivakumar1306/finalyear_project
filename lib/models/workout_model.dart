enum WorkoutType { running }

extension WorkoutTypeX on WorkoutType {
  String get label => switch (this) {
    WorkoutType.running => 'Running',
  };
}

class WorkoutSession {
  final String id;
  final WorkoutType type;
  final DateTime startTime;
  final DateTime endTime;
  final int durationSeconds;
  final int steps;
  final int calories;
  final double distanceM;
  final int avgHr;
  final int avgSpo2;
  final int avgBpSbp;
  final int avgBpDbp;

  const WorkoutSession({
    required this.id,
    required this.type,
    required this.startTime,
    required this.endTime,
    required this.durationSeconds,
    required this.steps,
    required this.calories,
    required this.distanceM,
    required this.avgHr,
    required this.avgSpo2,
    required this.avgBpSbp,
    required this.avgBpDbp,
  });
}
