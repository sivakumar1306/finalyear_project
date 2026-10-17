import 'package:flutter_test/flutter_test.dart';
import 'package:vital_monitoring/services/goal_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('GoalTargets', () {
    test('copyWith overrides selected fields', () {
      const base = GoalTargets(
        steps: 10000,
        calories: 1000,
        distanceKm: 5,
        sleepStartMin: 21 * 60,
        sleepEndMin: 5 * 60,
      );
      final next = base.copyWith(steps: 8000, distanceKm: 6.5);
      expect(next.steps, 8000);
      expect(next.calories, 1000);
      expect(next.distanceKm, 6.5);
      expect(next.sleepStartMin, base.sleepStartMin);
    });

    test('sleepLabel formats 12h times', () {
      const targets = GoalTargets(
        steps: 10000,
        calories: 1000,
        distanceKm: 5,
        sleepStartMin: 21 * 60,
        sleepEndMin: 5 * 60,
      );
      expect(targets.sleepLabel, '9:00pm - 5:00am');
    });

    test('sleepLabel handles midnight and noon', () {
      const midnight = GoalTargets(
        steps: 1,
        calories: 1,
        distanceKm: 1,
        sleepStartMin: 0,
        sleepEndMin: 12 * 60,
      );
      expect(midnight.sleepLabel, '12:00am - 12:00pm');
    });
  });

  group('GoalPrefs persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('load returns defaults when empty', () async {
      final t = await GoalPrefs.load();
      expect(t.steps, GoalPrefs.defaultSteps);
      expect(t.calories, GoalPrefs.defaultCalories);
      expect(t.distanceKm, GoalPrefs.defaultDistanceKm);
      expect(t.sleepStartMin, GoalPrefs.defaultSleepStartMin);
      expect(t.sleepEndMin, GoalPrefs.defaultSleepEndMin);
    });

    test('save then load round-trip', () async {
      const targets = GoalTargets(
        steps: 7500,
        calories: 1200,
        distanceKm: 8.25,
        sleepStartMin: 22 * 60 + 30,
        sleepEndMin: 6 * 60 + 15,
      );
      await GoalPrefs.save(targets);
      final loaded = await GoalPrefs.load();
      expect(loaded.steps, 7500);
      expect(loaded.calories, 1200);
      expect(loaded.distanceKm, 8.25);
      expect(loaded.sleepStartMin, 22 * 60 + 30);
      expect(loaded.sleepEndMin, 6 * 60 + 15);
    });
  });
}
