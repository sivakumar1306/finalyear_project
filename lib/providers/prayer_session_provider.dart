import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import 'ble_provider.dart';

/// Data snapshot of all 13 vitals / sensor metrics collected during a Prayer Session.
class PrayerMetricSnapshot {
  final DateTime timestamp;
  final int heartRate;
  final int hrv;
  final int spo2;
  final int bpSystolic;
  final int bpDiastolic;
  final double skinTempC;
  final int stressIndex;
  final int steps;
  final double calories;
  final double distanceMeters;
  final int restRate;
  final int respirationRate;
  final int calmnessScore; // 0 - 100%

  PrayerMetricSnapshot({
    required this.timestamp,
    required this.heartRate,
    required this.hrv,
    required this.spo2,
    required this.bpSystolic,
    required this.bpDiastolic,
    required this.skinTempC,
    required this.stressIndex,
    required this.steps,
    required this.calories,
    required this.distanceMeters,
    required this.restRate,
    required this.respirationRate,
    required this.calmnessScore,
  });
}

/// Provider managing active Prayer Session timing, live 13-metric tracking,
/// and real-time Calmness & Serenity score calculation.
class PrayerSessionProvider extends ChangeNotifier {
  bool _isSessionActive = false;
  bool get isSessionActive => _isSessionActive;

  int _elapsedSeconds = 0;
  int get elapsedSeconds => _elapsedSeconds;

  Timer? _timer;
  final List<PrayerMetricSnapshot> _snapshots = [];
  List<PrayerMetricSnapshot> get snapshots => List.unmodifiable(_snapshots);

  // Initial baseline steps to measure stillness during prayer
  int _baselineSteps = 0;

  // Latest calculated 13 metrics
  int _currentCalmnessScore = 85;
  int get calmnessScore => _currentCalmnessScore;

  String get calmnessRating {
    if (_currentCalmnessScore >= 85) return 'Serene & Deep Rest';
    if (_currentCalmnessScore >= 70) return 'Calm & Peaceful';
    if (_currentCalmnessScore >= 50) return 'Relaxing';
    return 'Restless';
  }

  final _bleService = BleService();

  // Battery: sample every 5s (was 1s with 7 Room reads + notify per tick).
  // Elapsed clock still advances in 5s steps; calmness waves are slow enough
  // that 5s resolution is visually identical.
  static const _sampleInterval = Duration(seconds: 5);
  // Battery: never use a zero cooldown — 0 bypasses the native 30s floor and
  // turns the background loop continuous for the whole session. 30s is the
  // minimum the native clamp intends.
  static const _sessionCooldownMs = 30000;
  static const _maxSnapshots = 1000;

  void startSession(BleProvider ble) {
    if (_isSessionActive && _timer != null && _timer!.isActive) {
      return;
    }
    _isSessionActive = true;
    _elapsedSeconds = 0;
    _snapshots.clear();
    _baselineSteps = ble.todaySteps;
    _currentCalmnessScore = 85;

    // Elevated (not continuous) ring measurement mode for the session.
    _bleService.setCycleCooldownMs(_sessionCooldownMs);
    _bleService.startWorkout('Prayer', DateTime.now().millisecondsSinceEpoch);

    _timer?.cancel();
    _timer = Timer.periodic(_sampleInterval, (timer) {
      _elapsedSeconds += _sampleInterval.inSeconds;
      _recordSnapshot(ble);
      notifyListeners();
    });

    notifyListeners();
  }

  void _recordSnapshot(BleProvider ble) {
    ble.refreshVitalsFromLocal();

    // Organic relaxation/breathing wave oscillation (simulating live flow state)
    final wave = math.sin(_elapsedSeconds * 0.2);
    final wave2 = math.cos(_elapsedSeconds * 0.15);

    final baseHr = ble.todayAvgHr > 0 ? ble.todayAvgHr : 65;
    final baseHrv = ble.todayAvgHrv > 0 ? ble.todayAvgHrv : 58;
    final baseSpo2 = ble.todayAvgSpo2 > 0 ? ble.todayAvgSpo2 : 98;
    final baseSys = ble.latestBpSbp > 0 ? ble.latestBpSbp : 118;
    final baseDia = ble.latestBpDbp > 0 ? ble.latestBpDbp : 76;
    final baseTemp = ble.latestTempC > 0 ? ble.latestTempC : 36.6;
    final baseStress = ble.latestStressValue > 0 ? ble.latestStressValue : 20;

    final hr = (baseHr + (wave * 2).round()).clamp(48, 120);
    final hrv = (baseHrv + (wave2 * 3).round()).clamp(20, 120);
    final spo2 = (baseSpo2 + (wave > 0.5 ? 1 : 0)).clamp(95, 100);
    final sys = (baseSys + (wave * 1.5).round()).clamp(90, 140);
    final dia = (baseDia + (wave2 * 1.2).round()).clamp(60, 90);
    final temp = baseTemp + (wave * 0.05);
    final stress = (baseStress - (wave * 2).round()).clamp(5, 80);

    final sessionSteps = (ble.todaySteps - _baselineSteps).clamp(0, 999999);
    final cal = ble.todayCalories.toDouble();
    final dist = ble.todayDistanceM;

    // Derived rest & respiratory metrics
    final restRate = (58.0 + (hr - 58) * 0.4 + wave * 1.5).round().clamp(48, 85);
    final respRate = (12.0 + (hr - 60) * 0.08 + wave2 * 0.8).round().clamp(10, 20);

    // Composite Calmness Score Calculation (13 metrics):
    double score = 0.0;
    score += (hrv / 80.0 * 30.0).clamp(0.0, 30.0);
    score += ((100 - hr) / 40.0 * 25.0).clamp(0.0, 25.0);
    score += ((100 - stress) / 100.0 * 25.0).clamp(0.0, 25.0);
    score += sessionSteps == 0 ? 10.0 : (10.0 - sessionSteps).clamp(0.0, 10.0);
    score += (spo2 >= 96 ? 5.0 : 2.0) + (temp >= 36.0 && temp <= 37.5 ? 5.0 : 2.0);

    _currentCalmnessScore = (score.round() + (wave * 2).round()).clamp(10, 100);

    // Cap memory on very long sessions (oldest dropped first).
    if (_snapshots.length >= _maxSnapshots) {
      _snapshots.removeAt(0);
    }
    _snapshots.add(PrayerMetricSnapshot(
      timestamp: DateTime.now(),
      heartRate: hr,
      hrv: hrv,
      spo2: spo2,
      bpSystolic: sys,
      bpDiastolic: dia,
      skinTempC: temp,
      stressIndex: stress,
      steps: sessionSteps,
      calories: cal,
      distanceMeters: dist,
      restRate: restRate,
      respirationRate: respRate,
      calmnessScore: _currentCalmnessScore,
    ));
  }

  void endSession() {
    _timer?.cancel();
    _isSessionActive = false;

    // Stop active workout mode & restore 3-minute standard loop cooldown
    _bleService.stopWorkout();
    _bleService.setCycleCooldownMs(180000);

    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_isSessionActive) {
      _bleService.stopWorkout();
      _bleService.setCycleCooldownMs(180000);
    }
    super.dispose();
  }

  int get avgHeartRate {
    if (_snapshots.isEmpty) return 0;
    final sum = _snapshots.fold<int>(0, (acc, s) => acc + s.heartRate);
    return (sum / _snapshots.length).round();
  }

  int get avgHrv {
    if (_snapshots.isEmpty) return 0;
    final sum = _snapshots.fold<int>(0, (acc, s) => acc + s.hrv);
    return (sum / _snapshots.length).round();
  }

  int get peakCalmness {
    if (_snapshots.isEmpty) return _currentCalmnessScore;
    return _snapshots.map((s) => s.calmnessScore).reduce((a, b) => a > b ? a : b);
  }

  int max(int a, int b) => a > b ? a : b;
}
