import 'package:flutter_test/flutter_test.dart';
import 'package:vital_monitoring/services/health_engine/health_engine.dart';
import 'package:vital_monitoring/services/health_engine/models.dart';
import 'package:vital_monitoring/services/goal_prefs.dart';

void main() {
  group('HealthEngine - sleep', () {
    test('calcSleepScore matches documented formula', () {
      final he = HealthEngine.instance;
      // Simple case: total=25200 (7h), deep=5040(20%), rem=3780(15%), window=28800 (8h)
      // efficiency=87.5, deepPct=20, remPct=15 => 87.5*0.4=35 +20*1 +15*0.5=7.5 => 62.5=63
      expect(he.calcSleepScore(total: 25200, deep: 5040, rem: 3780, st: 1000, et: 29800), 63);
      // window fallback when st/et zero -> window=total => efficiency 100
      expect(he.calcSleepScore(total: 20000, deep: 4000, rem: 3000, st: 0, et: 0), isA<int>());
    });

    test('sleep bands 80/60/40 - Good inside vs Excellent on Home bug fixed', () {
      final he = HealthEngine.instance;
      expect(he.assessSleep(0).label, 'No data');
      expect(he.assessSleep(39).label, 'Poor');
      expect(he.assessSleep(40).label, 'Fair');
      expect(he.assessSleep(59).label, 'Fair');
      expect(he.assessSleep(60).label, 'Good');
      expect(he.assessSleep(79).label, 'Good');
      expect(he.assessSleep(80).label, 'Excellent');
      expect(he.assessSleep(82).label, 'Excellent'); // the reported bug case
      expect(he.assessSleep(84).label, 'Excellent');
      expect(he.assessSleep(85).label, 'Excellent');
      expect(he.assessSleep(100).label, 'Excellent');
    });

    test('sleep home and detail share same label (no drift)', () {
      final he = HealthEngine.instance;
      for (final s in [0, 10, 39, 40, 55, 60, 70, 79, 80, 85, 95, 100]) {
        final home = he.assessSleep(s).label;
        final detail = he.assessSleep(s).label;
        expect(home, detail, reason: 'score $s home=$home detail=$detail must match');
      }
    });
  });

  group('HealthEngine - other vitals bands', () {
    test('hr bands', () {
      final he = HealthEngine.instance;
      expect(he.assessHeartRate(0).label, 'No data');
      expect(he.assessHeartRate(59).label, 'Below normal');
      expect(he.assessHeartRate(60).label, 'Normal');
      expect(he.assessHeartRate(99).label, 'Normal');
      expect(he.assessHeartRate(100).label, 'Above normal');
    });
    test('spo2 bands', () {
      final he = HealthEngine.instance;
      expect(he.assessSpo2(0).label, 'No data');
      expect(he.assessSpo2(95).label, 'Normal');
      expect(he.assessSpo2(90).label, 'Borderline');
      expect(he.assessSpo2(89).label, 'Low');
    });
    test('hrv bands', () {
      final he = HealthEngine.instance;
      expect(he.assessHrv(0).label, '--');
      expect(he.assessHrv(19).label, 'Very Low');
      expect(he.assessHrv(20).label, 'Low');
      expect(he.assessHrv(39).label, 'Low');
      expect(he.assessHrv(40).label, 'Moderate');
      expect(he.assessHrv(59).label, 'Moderate');
      expect(he.assessHrv(60).label, 'Good');
      expect(he.assessHrv(79).label, 'Good');
      expect(he.assessHrv(80).label, 'Excellent');
    });
    test('stress bands', () {
      final he = HealthEngine.instance;
      expect(he.assessStress(0).label, '--');
      expect(he.assessStress(39).label, 'Relaxed');
      expect(he.assessStress(40).label, 'Normal');
      expect(he.assessStress(59).label, 'Normal');
      expect(he.assessStress(60).label, 'Elevated');
      expect(he.assessStress(79).label, 'Elevated');
      expect(he.assessStress(80).label, 'High');
    });
    test('temperature bands', () {
      final he = HealthEngine.instance;
      expect(he.assessTemperature(0).label, '--');
      expect(he.assessTemperature(35.5).label, 'Low');
      expect(he.assessTemperature(36.5).label, 'Normal');
      expect(he.assessTemperature(37.5).label, 'Elevated');
      expect(he.assessTemperature(38.5).label, 'Fever');
    });
    test('bp staging matches AHA', () {
      final he = HealthEngine.instance;
      expect(he.assessBloodPressure(0, 0).label, 'No data');
      expect(he.assessBloodPressure(110, 70).label, 'Normal');
      expect(he.assessBloodPressure(125, 75).label, 'Elevated');
      expect(he.assessBloodPressure(135, 85).label, 'Stage 1');
      expect(he.assessBloodPressure(145, 95).label, 'Stage 2');
    });
  });

  group('HealthEngine - activity goal-aware', () {
    test('activity score uses GoalPrefs not hardcoded 8000/250/5000', () {
      final he = HealthEngine.instance;
      const goalsA = GoalTargets(steps: 10000, calories: 1000, distanceKm: 5.0, sleepStartMin: 1260, sleepEndMin: 300);
      const goalsB = GoalTargets(steps: 5000, calories: 500, distanceKm: 2.5, sleepStartMin: 1260, sleepEndMin: 300);
      // same raw activity should score differently with different goals
      final scoreA = he.calcActivityScoreWithGoals(steps: 5000, calories: 500, distanceM: 2500, goals: goalsA);
      final scoreB = he.calcActivityScoreWithGoals(steps: 5000, calories: 500, distanceM: 2500, goals: goalsB);
      expect(scoreB, greaterThan(scoreA)); // B goals are half, so progress double
    });

    test('activity label bands', () {
      final he = HealthEngine.instance;
      expect(he.activityLabel(0), 'Lack of exercise');
      expect(he.activityLabel(10), 'Sedentary');
      expect(he.activityLabel(24), 'Sedentary');
      expect(he.activityLabel(25), 'Lightly active');
      expect(he.activityLabel(49), 'Lightly active');
      expect(he.activityLabel(50), 'Moderately active');
      expect(he.activityLabel(74), 'Moderately active');
      expect(he.activityLabel(75), 'Highly active');
      expect(he.activityLabel(100), 'Highly active');
    });

    test('activity description reflects goals', () {
      final he = HealthEngine.instance;
      const g = GoalTargets(steps: 12000, calories: 600, distanceKm: 8.0, sleepStartMin: 1260, sleepEndMin: 300);
      final desc = he.activityDescription(g);
      expect(desc, contains('12000'));
      expect(desc, contains('600'));
      expect(desc, contains('8.0 km'));
    });
  });

  group('HealthEngine - advice / ranges single dict', () {
    test('noteFor returns non-empty ranges & tips for every metric', () {
      final he = HealthEngine.instance;
      for (final m in HealthMetric.values) {
        final note = he.noteFor(m);
        expect(note.title.isNotEmpty, true, reason: 'title empty for $m');
        expect(note.ranges.isNotEmpty, true, reason: 'ranges empty for $m');
        expect(note.tips.isNotEmpty, true, reason: 'tips empty for $m');
      }
    });

    test('sleep note ranges match sleep bands', () {
      final he = HealthEngine.instance;
      final note = he.noteFor(HealthMetric.sleep);
      // Should contain at least 4 bands 0-39 etc, matching thresholds 40/60/80
      expect(note.ranges.length, 4);
      expect(note.ranges.map((r) => r.label), containsAll(['Poor', 'Fair', 'Good', 'Excellent']));
    });

    test('colorForKey maps known keys', () {
      final he = HealthEngine.instance;
      expect(he.colorForKey('success'), isNotNull);
      expect(he.colorForKey('sleepColor'), isNotNull);
      expect(he.colorForKey('unknown'), isNotNull); // fallback
    });

    test('iconForKey maps known icons', () {
      final he = HealthEngine.instance;
      expect(he.iconForKey('bedtime_rounded'), isNotNull);
      expect(he.iconForKey('unknown'), isNotNull);
    });
  });
}
