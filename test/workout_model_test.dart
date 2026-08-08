import 'package:flutter_test/flutter_test.dart';
import 'package:qring_flutter/models/workout_model.dart';

void main() {
  group('WorkoutCategory', () {
    test('every category has a non-empty label', () {
      for (final c in WorkoutCategory.values) {
        expect(c.label, isNotEmpty);
      }
    });

    test('running tracks steps and distance', () {
      expect(
        WorkoutCategory.running.metrics,
        containsAll([
          WorkoutMetric.heartRate,
          WorkoutMetric.steps,
          WorkoutMetric.distance,
          WorkoutMetric.calories,
        ]),
      );
    });

    test('swimming does not track steps', () {
      expect(
        WorkoutCategory.swimming.metrics.contains(WorkoutMetric.steps),
        isFalse,
      );
      expect(
        WorkoutCategory.swimming.metrics,
        containsAll([WorkoutMetric.heartRate, WorkoutMetric.calories]),
      );
    });

    test('sports lists are non-empty', () {
      for (final c in WorkoutCategory.values) {
        expect(c.sports, isNotEmpty, reason: c.name);
      }
    });

    test('labels are unique', () {
      final labels = WorkoutCategory.values.map((c) => c.label).toSet();
      expect(labels.length, WorkoutCategory.values.length);
    });
  });
}
