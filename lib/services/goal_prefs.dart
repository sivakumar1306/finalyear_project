import 'package:shared_preferences/shared_preferences.dart';

/// Centralised persistence for the user's daily goal targets:
/// steps, calories, distance and the sleep window.
///
/// No Supabase table backs this yet (checked: user_profiles, user_hr,
/// user_spo2, user_bp, user_stress, user_hrv, user_temp, user_workouts,
/// user_sleep, user_cycles, user_symptoms, user_steps — none store targets),
/// so this lives in SharedPreferences for now, mirroring HomeCardPrefs.
/// If/when a `user_goals` table is added, swap the bodies below for
/// SupabaseService calls without touching the screen.
class GoalPrefs {
  static const _stepsKey = 'goal_steps';
  static const _caloriesKey = 'goal_calories';
  static const _distanceKmKey = 'goal_distance_km';
  static const _sleepStartMinKey =
      'goal_sleep_start_min'; // minutes from midnight
  static const _sleepEndMinKey = 'goal_sleep_end_min';

  static const int defaultSteps = 10000;
  static const int defaultCalories = 1000;
  static const double defaultDistanceKm = 5.0;
  static const int defaultSleepStartMin = 21 * 60; // 9:00pm
  static const int defaultSleepEndMin = 5 * 60; // 5:00am

  static Future<GoalTargets> load() async {
    final prefs = await SharedPreferences.getInstance();
    return GoalTargets(
      steps: prefs.getInt(_stepsKey) ?? defaultSteps,
      calories: prefs.getInt(_caloriesKey) ?? defaultCalories,
      distanceKm: prefs.getDouble(_distanceKmKey) ?? defaultDistanceKm,
      sleepStartMin: prefs.getInt(_sleepStartMinKey) ?? defaultSleepStartMin,
      sleepEndMin: prefs.getInt(_sleepEndMinKey) ?? defaultSleepEndMin,
    );
  }

  static Future<void> save(GoalTargets targets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_stepsKey, targets.steps);
    await prefs.setInt(_caloriesKey, targets.calories);
    await prefs.setDouble(_distanceKmKey, targets.distanceKm);
    await prefs.setInt(_sleepStartMinKey, targets.sleepStartMin);
    await prefs.setInt(_sleepEndMinKey, targets.sleepEndMin);
  }
}

class GoalTargets {
  final int steps;
  final int calories;
  final double distanceKm;
  final int sleepStartMin;
  final int sleepEndMin;

  const GoalTargets({
    required this.steps,
    required this.calories,
    required this.distanceKm,
    required this.sleepStartMin,
    required this.sleepEndMin,
  });

  GoalTargets copyWith({
    int? steps,
    int? calories,
    double? distanceKm,
    int? sleepStartMin,
    int? sleepEndMin,
  }) {
    return GoalTargets(
      steps: steps ?? this.steps,
      calories: calories ?? this.calories,
      distanceKm: distanceKm ?? this.distanceKm,
      sleepStartMin: sleepStartMin ?? this.sleepStartMin,
      sleepEndMin: sleepEndMin ?? this.sleepEndMin,
    );
  }

  static String _fmtTime(int minutes) {
    final h24 = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    final period = h24 >= 12 ? 'pm' : 'am';
    var h12 = h24 % 12;
    if (h12 == 0) h12 = 12;
    final mm = m.toString().padLeft(2, '0');
    return '$h12:$mm$period';
  }

  String get sleepLabel =>
      '${_fmtTime(sleepStartMin)} - ${_fmtTime(sleepEndMin)}';
}
