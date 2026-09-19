import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ble_service.dart';
import '../services/incident_service.dart';
import '../services/supabase_service.dart';
import '../models/workout_model.dart';

class WorkoutProvider extends ChangeNotifier {
  final BleService _ble = BleService();

  Timer? _uiTimer;
  SharedPreferences? _prefs;

  bool _isWorkoutActive = false;
  WorkoutCategory? _currentCategory;
  String? _currentSport;
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
  int _hrSum = 0;
  int _latestHr = 0;

  // Phone-GPS trace (the ring reports no coordinates — SportLocation
  // carries only per-point HR). Sampled each measurement tick; empty when
  // permission is denied or GPS unavailable.
  final List<Map<String, dynamic>> _tracePoints = [];
  List<Map<String, dynamic>> get tracePoints =>
      List.unmodifiable(_tracePoints);

  int _todayWorkoutDurationS = 0;

  // True while ring polls are failing — the active screen shows
  // "Reconnecting…" instead of silent zeros.
  bool _ringUnreachable = false;
  bool get ringUnreachable => _ringUnreachable;

  bool get isWorkoutActive => _isWorkoutActive;
  WorkoutCategory? get currentCategory => _currentCategory;
  String? get currentSport => _currentSport;
  DateTime? get startTime => _startTime;
  int get elapsedSeconds => _elapsedSeconds;
  int get workoutSteps => _workoutSteps;
  int get workoutCalories => _workoutCalories;
  double get workoutDistanceM => _workoutDistanceM;
  int get latestHr => _latestHr;
  int get avgHr =>
      _hrReadings.isEmpty ? 0 : (_hrSum / _hrReadings.length).round();
  int get todayWorkoutDurationS => _todayWorkoutDurationS;

  // Completes after the initial SharedPreferences check; used by MainShell
  // to redirect to the active workout screen on app resume.
  late final Future<void> initialized;

  WorkoutProvider() {
    initialized = _resumeIfActive();
    loadTodayWorkoutDuration();
  }

  Future<void> loadTodayWorkoutDuration() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return;
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      final rows = await SupabaseService.getWorkoutHistory(
        userId: user.id,
        from: startOfDay,
        to: endOfDay,
      );
      int total = 0;
      for (final row in rows) {
        total += (row['duration_s'] as num? ?? 0).toInt();
      }
      _todayWorkoutDurationS = total;
      notifyListeners();
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'workout_provider',
        error: e,
        stackTrace: st,
        customMessage: 'loadTodayWorkoutDuration failed',
      );
    }
  }

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<void> _resumeIfActive() async {
    final prefs = await _getPrefs();
    if (!(prefs.getBool('workout_active') ?? false)) return;

    final catStr = prefs.getString('workout_category');
    final sport = prefs.getString('workout_sport');
    final startMs = prefs.getInt('workout_start_time');
    if (catStr == null || startMs == null) return;

    _currentCategory = workoutCategoryFromString(catStr) ?? WorkoutCategory.running;
    _currentSport = sport ?? _currentCategory!.sports.first;
    _startTime = DateTime.fromMillisecondsSinceEpoch(startMs);
    _initialSteps = prefs.getInt('workout_start_steps') ?? 0;
    _initialCalories = prefs.getInt('workout_start_calories') ?? 0;
    _initialDistance = prefs.getDouble('workout_start_distance') ?? 0.0;
    _hrReadings.clear();
    _hrSum = 0;
    _latestHr = 0;
    _isWorkoutActive = true;

    _startUiTimer();
    _runMeasurementLoop(); // fire-and-forget
    notifyListeners();
  }

  Future<void> startWorkout(WorkoutCategory category, String sport) async {
    final now = DateTime.now();

    _currentCategory = category;
    _currentSport = sport;
    _startTime = now;
    _isWorkoutActive = true;
    _elapsedSeconds = 0;
    _workoutSteps = 0;
    _workoutCalories = 0;
    _workoutDistanceM = 0.0;
    _hrReadings.clear();
    _hrSum = 0;
    _latestHr = 0;
    _tracePoints.clear();

    // Warm the ring buffer first so the baseline reflects current totals —
    // without this, baseline == first poll and every delta reads 0.
    // A failed baseline is flagged (not zeroed): the first successful poll
    // re-baselines instead of inflating to full-day totals.
    bool baselineStale = false;
    try {
      await _ble.syncTodaySteps().timeout(const Duration(seconds: 15));
      final raw = await _ble.getTodaySteps();
      final (s, c, d) = _parseSteps(raw);
      _initialSteps = s;
      _initialCalories = c;
      _initialDistance = d;
    } catch (_) {
      _initialSteps = 0;
      _initialCalories = 0;
      _initialDistance = 0.0;
      baselineStale = true;
    }
    final prefs = await _getPrefs();
    await prefs.setBool('workout_active', true);
    await prefs.setBool('workout_baseline_stale', baselineStale);
    await prefs.setString('workout_category', category.name);
    await prefs.setString('workout_sport', sport);
    await prefs.setInt('workout_start_time', now.millisecondsSinceEpoch);
    await prefs.setInt('workout_start_steps', _initialSteps);
    await prefs.setInt('workout_start_calories', _initialCalories);
    await prefs.setDouble('workout_start_distance', _initialDistance);

    try {
      await _ble.startWorkout(sport, now.millisecondsSinceEpoch);
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'workout_provider',
        error: e,
        stackTrace: st,
        customMessage: 'ble.startWorkout failed',
      );
    }

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
    final category = _currentCategory!;
    final sport = _currentSport ?? category.sports.first;

    try {
      await _ble.stopWorkout();
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'workout_provider',
        error: e,
        stackTrace: st,
        customMessage: 'ble.stopWorkout failed',
      );
    }

    WorkoutSession? session;
    final userId = SupabaseService.currentUser?.id;
    final workoutMap = <String, dynamic>{
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'workout_type': sport,
      'started_at': _startTime!.toIso8601String(),
      'ended_at': endTime.toIso8601String(),
      'duration_s': duration,
      'steps': _workoutSteps,
      'calories': _workoutCalories,
      'distance_m': _workoutDistanceM,
      'avg_hr': computedAvgHr,
      'created_at': endTime.toIso8601String(),
      'locations': List<Map<String, dynamic>>.from(_tracePoints),
    };

    if (userId != null && _startTime != null) {
      try {
        final id = await SupabaseService.insertWorkout(
          userId: userId,
          type: sport,
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
          locations: _tracePoints.isEmpty
              ? null
              : List<Map<String, dynamic>>.from(_tracePoints),
        );
        if (id != null) workoutMap['id'] = id;
      } catch (e) {
        debugPrint('WorkoutProvider: insertWorkout failed: $e');
      }
    }

    await _saveLocalWorkout(workoutMap);

    session = WorkoutSession(
      id: workoutMap['id']?.toString() ?? '',
      category: category,
      sport: sport,
      startTime: _startTime!,
      endTime: endTime,
      durationSeconds: duration,
      steps: _workoutSteps,
      calories: _workoutCalories,
      distanceM: _workoutDistanceM,
      avgHr: computedAvgHr,
    );

    final prefs = await _getPrefs();
    for (final key in [
      'workout_active',
      'workout_baseline_stale',
      'workout_category',
      'workout_sport',
      'workout_start_time',
      'workout_start_steps',
      'workout_start_calories',
      'workout_start_distance',
    ]) {
      await prefs.remove(key);
    }

    _isWorkoutActive = false;
    _ringUnreachable = false;
    _currentCategory = null;
    _currentSport = null;
    _startTime = null;
    _elapsedSeconds = 0;
    _hrReadings.clear();
    _hrSum = 0;
    _latestHr = 0;
    _tracePoints.clear();
    notifyListeners();
    loadTodayWorkoutDuration();

    return session;
  }

  // ── Local Workout Persistence ─────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getLocalWorkouts() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString('local_workout_history');
    if (raw == null || raw.isEmpty) return [];
    try {
      final List<dynamic> list = jsonDecode(raw);
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveLocalWorkout(Map<String, dynamic> workoutMap) async {
    final prefs = await _getPrefs();
    final existing = await getLocalWorkouts();
    existing.insert(0, workoutMap);
    if (existing.length > 100) {
      existing.removeLast();
    }
    await prefs.setString('local_workout_history', jsonEncode(existing));
  }

  // ── Measurement loop ─────────────────────────────────────────────────────────
  //
  // Single unified BLE poll loop (was two concurrent loops: HR every 4s +
  // steps every 2s). One 10s loop halves radio wakeups and avoids the two loops
  // colliding on the shared SDK slot. The 1s UI timer above still drives the
  // elapsed-time display; this loop only handles BLE data.
  Future<void> _runMeasurementLoop() async {
    while (_isWorkoutActive) {
      // HR reading (plausible-range guard mirrors native VitalRanges).
      try {
        final hr = await _ble.readHeartRate();
        if (!_isWorkoutActive) break;
        const hrMin = 30, hrMax = 220;
        if (hr != null && hr >= hrMin && hr <= hrMax) {
          if (_hrReadings.length >= 500) {
            _hrSum -= _hrReadings.removeAt(0);
          }
          _hrReadings.add(hr);
          _hrSum += hr;
          _latestHr = hr;
          notifyListeners();
        }
      } catch (e, st) {
        IncidentService.reportUnhandled(
          source: 'workout_provider',
          error: e,
          stackTrace: st,
          customMessage: 'measurementLoop readHeartRate failed',
        );
      }
      if (!_isWorkoutActive) break;
      await _pollRing();
      await _sampleGps();
      await Future.delayed(const Duration(seconds: 10));
    }
  }

  /// One low-accuracy GPS fix per measurement tick. Silent on denial,
  /// disabled services, or timeouts — trace stays partial, never fatal.
  Future<void> _sampleGps() async {
    if (!_isWorkoutActive || _tracePoints.length >= 600) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.deniedForever) return;
      if (perm == LocationPermission.denied) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );
      _tracePoints.add({
        'lat': pos.latitude,
        'lng': pos.longitude,
        't': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {}
  }

  // ── Timer & ring helpers ──────────────────────────────────────────────────

  void _startUiTimer() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (_startTime == null) return;
    _elapsedSeconds = DateTime.now().difference(_startTime!).inSeconds;
    notifyListeners();
  }

  Future<void> _pollRing() async {
    try {
      await _ble.syncTodaySteps();
      final raw = await _ble.getTodaySteps();
      final (steps, cal, dist) = _parseSteps(raw);

      if (steps > 0 || cal > 0 || dist > 0) {
        // Recover from a stale zero baseline once the ring responds.
        try {
          final prefs = await _getPrefs();
          if (prefs.getBool('workout_baseline_stale') ?? false) {
            _initialSteps = steps;
            _initialCalories = cal;
            _initialDistance = dist;
            await prefs.setBool('workout_baseline_stale', false);
          }
        } catch (_) {}
        _workoutSteps = (steps - _initialSteps).clamp(0, 9999999);
        _workoutCalories = (cal - _initialCalories).clamp(0, 9999999);
        _workoutDistanceM = (dist - _initialDistance).clamp(0.0, 9999999.0);
        if (_ringUnreachable) {
          _ringUnreachable = false;
        }
        notifyListeners();
      }
    } catch (_) {
      // Ring unreachable — surface it instead of freezing on stale values.
      if (!_ringUnreachable) {
        _ringUnreachable = true;
        notifyListeners();
      }
    }
  }

  // Same ProGuard field mapping used by StepsScreen and BleProvider:
  //   e = calories raw (小卡), f = walkSteps, g = distance (meters).
  // Raw calories are summed first and converted once, so sub-1000 sessions
  // still count (min 1 kcal) instead of truncating to 0 per slot.
  (int steps, int calories, double distance) _parseSteps(String jsonStr) {
    final decoded = jsonDecode(jsonStr);
    final list = decoded is List ? decoded : <dynamic>[];
    int totalSteps = 0, totalCalRaw = 0;
    double totalDist = 0.0;
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final m = item;
      totalSteps +=
          (m['f'] as num? ?? m['walkSteps'] as num? ?? 0).toInt() +
          (m['runSteps'] as num? ?? 0).toInt();
      totalCalRaw +=
          (m['e'] as num? ?? m['calorie'] as num? ?? 0).toInt();
      totalDist +=
          (m['g'] as num? ?? m['distance'] as num? ?? 0.0).toDouble();
    }
    final totalCal =
        totalCalRaw >= 1000 ? totalCalRaw ~/ 1000 : (totalCalRaw > 0 ? 1 : 0);
    return (totalSteps, totalCal, totalDist);
  }

  @override
  void dispose() {
    _isWorkoutActive = false;
    _uiTimer?.cancel();
    super.dispose();
  }
}
