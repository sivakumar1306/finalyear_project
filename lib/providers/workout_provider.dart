import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ble_service.dart';
import '../services/supabase_service.dart';
import '../models/workout_model.dart';

class WorkoutProvider extends ChangeNotifier {
  final BleService _ble = BleService();

  Timer? _uiTimer;
  SharedPreferences? _prefs;

  bool _isWorkoutActive = false;
  WorkoutType? _currentType;
  DateTime? _startTime;
  int _elapsedSeconds = 0;
  int _workoutSteps = 0;
  int _workoutCalories = 0;
  double _workoutDistanceM = 0.0;
  int? _latestSpo2;
  int? _latestBpSbp;
  int? _latestBpDbp;
  int? _latestHr;

  bool get isWorkoutActive => _isWorkoutActive;
  WorkoutType? get currentType => _currentType;
  DateTime? get startTime => _startTime;
  int get elapsedSeconds => _elapsedSeconds;
  int get workoutSteps => _workoutSteps;
  int get workoutCalories => _workoutCalories;
  double get workoutDistanceM => _workoutDistanceM;
  int? get latestSpo2 => _latestSpo2;
  int? get latestBpSbp => _latestBpSbp;
  int? get latestBpDbp => _latestBpDbp;
  int? get latestHr => _latestHr;

  // Completes after the initial SharedPreferences check, used by MainShell
  // to redirect to active workout screen on app resume.
  late final Future<void> initialized;

  WorkoutProvider() {
    initialized = _resumeIfActive();
  }

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<void> _resumeIfActive() async {
    final prefs = await _getPrefs();
    final active = prefs.getBool('workout_active') ?? false;
    if (!active) return;

    final typeStr = prefs.getString('workout_type');
    final startMs = prefs.getInt('workout_start_time');
    if (typeStr == null || startMs == null) return;

    _currentType = WorkoutType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => WorkoutType.running,
    );
    _startTime = DateTime.fromMillisecondsSinceEpoch(startMs);
    _isWorkoutActive = true;
    _startUiTimer();
    notifyListeners();
  }

  Future<void> startWorkout(
    WorkoutType type, {
    required int baselineSteps,
    required int baselineCalories,
    required double baselineDistance,
  }) async {
    final prefs = await _getPrefs();
    final now = DateTime.now();
    final startMs = now.millisecondsSinceEpoch;

    await prefs.setBool('workout_active', true);
    await prefs.setString('workout_type', type.name);
    await prefs.setInt('workout_start_time', startMs);
    await prefs.setInt('workout_start_steps', baselineSteps);
    await prefs.setInt('workout_start_calories', baselineCalories);
    await prefs.setDouble('workout_start_distance', baselineDistance);

    _currentType = type;
    _startTime = now;
    _isWorkoutActive = true;
    _elapsedSeconds = 0;
    _workoutSteps = 0;
    _workoutCalories = 0;
    _workoutDistanceM = 0.0;
    _latestSpo2 = null;
    _latestBpSbp = null;
    _latestBpDbp = null;
    _latestHr = null;

    try {
      await _ble.startWorkout(type.name, startMs);
    } catch (_) {}

    _startUiTimer();
    notifyListeners();
  }

  Future<WorkoutSession?> stopWorkout() async {
    if (!_isWorkoutActive) return null;

    final endTime = DateTime.now();
    final duration = _elapsedSeconds;

    _uiTimer?.cancel();
    _uiTimer = null;

    try {
      await _ble.stopWorkout();
    } catch (_) {}

    WorkoutSession? session;
    final userId = SupabaseService.currentUser?.id;
    if (userId != null && _currentType != null && _startTime != null) {
      try {
        final id = await SupabaseService.insertWorkout(
          userId: userId,
          type: _currentType!.name,
          startedAt: _startTime!,
          endedAt: endTime,
          durationS: duration,
          steps: _workoutSteps,
          calories: _workoutCalories,
          distanceM: _workoutDistanceM,
          avgHr: _latestHr ?? 0,
          avgSpo2: _latestSpo2 ?? 0,
          avgBpSbp: _latestBpSbp ?? 0,
          avgBpDbp: _latestBpDbp ?? 0,
        );
        session = WorkoutSession(
          id: id ?? '',
          type: _currentType!,
          startTime: _startTime!,
          endTime: endTime,
          durationSeconds: duration,
          steps: _workoutSteps,
          calories: _workoutCalories,
          distanceM: _workoutDistanceM,
          avgHr: _latestHr ?? 0,
          avgSpo2: _latestSpo2 ?? 0,
          avgBpSbp: _latestBpSbp ?? 0,
          avgBpDbp: _latestBpDbp ?? 0,
        );
      } catch (_) {}
    }

    final prefs = await _getPrefs();
    for (final key in [
      'workout_active',
      'workout_type',
      'workout_start_time',
      'workout_start_steps',
      'workout_start_calories',
      'workout_start_distance',
      'workout_latest_spo2',
      'workout_latest_sbp',
      'workout_latest_dbp',
      'workout_latest_hr',
      'workout_current_steps',
      'workout_current_calories',
      'workout_current_distance',
    ]) {
      await prefs.remove(key);
    }

    _isWorkoutActive = false;
    _currentType = null;
    _startTime = null;
    _elapsedSeconds = 0;
    notifyListeners();

    return session;
  }

  void _startUiTimer() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  Future<void> _tick() async {
    if (_startTime == null) return;
    _elapsedSeconds = DateTime.now().difference(_startTime!).inSeconds;

    // Reload picks up values written by WorkoutService.kt — Flutter's SharedPreferences
    // caches in Dart memory, so native writes are invisible without an explicit reload.
    final prefs = await _getPrefs();
    await prefs.reload();

    // WorkoutService clears workout_active if startForeground fails. Detect that
    // and stop the Dart-side workout so the UI doesn't stay locked indefinitely.
    if (!(prefs.getBool('workout_active') ?? false)) {
      _uiTimer?.cancel();
      _uiTimer = null;
      _isWorkoutActive = false;
      _currentType = null;
      _startTime = null;
      _elapsedSeconds = 0;
      notifyListeners();
      return;
    }

    final spo2 = prefs.getInt('workout_latest_spo2');
    final sbp = prefs.getInt('workout_latest_sbp');
    final dbp = prefs.getInt('workout_latest_dbp');
    final hr = prefs.getInt('workout_latest_hr');
    final steps = prefs.getInt('workout_current_steps');
    final calories = prefs.getInt('workout_current_calories');
    final distance = prefs.getDouble('workout_current_distance');

    if (spo2 != null) _latestSpo2 = spo2;
    if (sbp != null) _latestBpSbp = sbp;
    if (dbp != null) _latestBpDbp = dbp;
    if (hr != null) _latestHr = hr;
    if (steps != null) _workoutSteps = steps;
    if (calories != null) _workoutCalories = calories;
    if (distance != null) _workoutDistanceM = distance;

    notifyListeners();
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    super.dispose();
  }
}
