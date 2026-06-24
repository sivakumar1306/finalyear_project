import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ble_service.dart';
import '../services/supabase_service.dart';
import '../models/workout_model.dart';

class WorkoutProvider extends ChangeNotifier {
  final BleService _ble = BleService();

  // 1-second timer: updates elapsed time only (synchronous, always reliable)
  Timer? _uiTimer;

  SharedPreferences? _prefs;

  bool _isWorkoutActive = false;
  WorkoutType? _currentType;
  DateTime? _startTime;
  int _elapsedSeconds = 0;

  // Baseline readings captured at workout start
  int _initialSteps = 0;
  int _initialCalories = 0;
  double _initialDistance = 0.0;

  // Delta values displayed and saved (current - initial)
  int _workoutSteps = 0;
  int _workoutCalories = 0;
  double _workoutDistanceM = 0.0;

  // Heart rate collected during workout
  final List<int> _hrReadings = [];
  int _latestHr = 0;

  bool get isWorkoutActive => _isWorkoutActive;
  WorkoutType? get currentType => _currentType;
  DateTime? get startTime => _startTime;
  int get elapsedSeconds => _elapsedSeconds;
  int get workoutSteps => _workoutSteps;
  int get workoutCalories => _workoutCalories;
  double get workoutDistanceM => _workoutDistanceM;
  int get latestHr => _latestHr;
  int get avgHr => _hrReadings.isEmpty
      ? 0
      : (_hrReadings.reduce((a, b) => a + b) / _hrReadings.length).round();

  // Completes after the initial SharedPreferences check; used by MainShell
  // to redirect to the active workout screen on app resume.
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
    if (!(prefs.getBool('workout_active') ?? false)) return;

    final typeStr = prefs.getString('workout_type');
    final startMs = prefs.getInt('workout_start_time');
    if (typeStr == null || startMs == null) return;

    _currentType = WorkoutType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => WorkoutType.running,
    );
    _startTime = DateTime.fromMillisecondsSinceEpoch(startMs);
    _initialSteps = prefs.getInt('workout_start_steps') ?? 0;
    _initialCalories = prefs.getInt('workout_start_calories') ?? 0;
    _initialDistance = prefs.getDouble('workout_start_distance') ?? 0.0;
    _hrReadings.clear();
    _latestHr = 0;
    _isWorkoutActive = true;

    _startUiTimer();
    _runMeasurementLoop(); // fire-and-forget
    notifyListeners();
  }

  Future<void> startWorkout(WorkoutType type) async {
    final now = DateTime.now();

    _currentType = type;
    _startTime = now;
    _isWorkoutActive = true;
    _elapsedSeconds = 0;
    _workoutSteps = 0;
    _workoutCalories = 0;
    _workoutDistanceM = 0.0;
    _hrReadings.clear();
    _latestHr = 0;

    // Fetch current ring values as the workout baseline before the user
    // moves. If the ring is unreachable, fall back to zero — polls will
    // still collect relative progress once the ring responds.
    try {
      final raw = await _ble.getTodaySteps();
      final (s, c, d) = _parseSteps(raw);
      _initialSteps = s;
      _initialCalories = c;
      _initialDistance = d;
    } catch (_) {
      _initialSteps = 0;
      _initialCalories = 0;
      _initialDistance = 0.0;
    }

    final prefs = await _getPrefs();
    await prefs.setBool('workout_active', true);
    await prefs.setString('workout_type', type.name);
    await prefs.setInt('workout_start_time', now.millisecondsSinceEpoch);
    await prefs.setInt('workout_start_steps', _initialSteps);
    await prefs.setInt('workout_start_calories', _initialCalories);
    await prefs.setDouble('workout_start_distance', _initialDistance);

    try {
      await _ble.startWorkout(type.name, now.millisecondsSinceEpoch);
    } catch (_) {}

    _startUiTimer();
    _runMeasurementLoop(); // fire-and-forget
    notifyListeners();
  }

  Future<WorkoutSession?> stopWorkout() async {
    if (!_isWorkoutActive) return null;

    // Signal the loop to exit after its current await completes
    _isWorkoutActive = false;
    _uiTimer?.cancel();
    _uiTimer = null;

    // Final steps poll to capture the most recent readings before saving
    await _pollRing();

    final endTime = DateTime.now();
    final duration = _elapsedSeconds;
    final computedAvgHr = avgHr; // snapshot before state is cleared

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
          avgHr: computedAvgHr,
          avgSpo2: 0,
          avgBpSbp: 0,
          avgBpDbp: 0,
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
          avgHr: computedAvgHr,
        );
      } catch (e) {
        debugPrint('WorkoutProvider: insertWorkout failed: $e');
      }
    }

    final prefs = await _getPrefs();
    for (final key in [
      'workout_active',
      'workout_type',
      'workout_start_time',
      'workout_start_steps',
      'workout_start_calories',
      'workout_start_distance',
    ]) {
      await prefs.remove(key);
    }

    _isWorkoutActive = false;
    _currentType = null;
    _startTime = null;
    _elapsedSeconds = 0;
    _hrReadings.clear();
    _latestHr = 0;
    notifyListeners();

    return session;
  }

  // ── Measurement loop ─────────────────────────────────────────────────────────
  //
  // Alternates between:
  //   1. HR reading  — blocks until the ring returns a valid beat (~15-30 s)
  //   2. Steps poll  — fetch accumulated steps/cal/dist and compute delta
  //
  // The loop runs until _isWorkoutActive is false, which stopWorkout() sets
  // before awaiting its own final poll. Each await checks the flag so the
  // loop exits cleanly at the next opportunity without being forcefully cancelled.

  Future<void> _runMeasurementLoop() async {
    while (_isWorkoutActive) {
      // ── 1. Heart rate ─────────────────────────────────────────────────────
      try {
        final hr = await _ble.readHeartRate();
        if (!_isWorkoutActive) break;
        if (hr != null && hr > 0) {
          _hrReadings.add(hr);
          _latestHr = hr;
          notifyListeners();
        }
      } catch (_) {
        // Ring unreachable or timed out — skip HR this round, still poll steps
        if (!_isWorkoutActive) break;
      }

      if (!_isWorkoutActive) break;

      // ── 2. Steps / calories / distance ────────────────────────────────────
      await _pollRing();
    }
  }

  // ── Timer & ring helpers ──────────────────────────────────────────────────

  void _startUiTimer() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  // Synchronous: just advances elapsed seconds and refreshes the UI.
  void _tick() {
    if (_startTime == null) return;
    _elapsedSeconds = DateTime.now().difference(_startTime!).inSeconds;
    notifyListeners();
  }

  // Fetches current ring totals and subtracts the workout baseline.
  // On failure, keeps the last valid values (never resets to zero).
  Future<void> _pollRing() async {
    try {
      final raw = await _ble.getTodaySteps();
      final (steps, cal, dist) = _parseSteps(raw);

      // Only apply if the ring returned real data
      if (steps > 0 || cal > 0 || dist > 0) {
        _workoutSteps    = (steps - _initialSteps).clamp(0, 9999999);
        _workoutCalories = (cal   - _initialCalories).clamp(0, 9999999);
        _workoutDistanceM = (dist - _initialDistance).clamp(0.0, 9999999.0);
        notifyListeners();
      }
    } catch (_) {
      // Keep last valid values on ring error
    }
  }

  // Same ProGuard field mapping used by StepsScreen and BleProvider:
  //   e = calories (小卡, divide by 1000 for kcal)
  //   f = walkSteps
  //   g = distance (meters)
  (int steps, int calories, double distance) _parseSteps(String jsonStr) {
    final decoded = jsonDecode(jsonStr);
    final list = decoded is List ? decoded : <dynamic>[];
    int totalSteps = 0, totalCal = 0;
    double totalDist = 0.0;
    for (final item in list) {
      final m = item as Map<String, dynamic>;
      totalSteps += (m['f'] as num? ?? 0).toInt();
      totalCal   += (m['e'] as num? ?? 0).toInt() ~/ 1000;
      totalDist  += (m['g'] as num? ?? 0).toDouble();
    }
    return (totalSteps, totalCal, totalDist);
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    super.dispose();
  }
}
