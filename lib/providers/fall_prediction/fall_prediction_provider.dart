import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../models/fall_prediction/physiological_data.dart';
import '../../models/fall_prediction/behavioral_data.dart';
import '../../models/fall_prediction/motion_data.dart';
import '../../models/fall_prediction/womens_health_data.dart';
import '../../models/fall_prediction/context_factors.dart';
import '../../models/fall_prediction/prediction_result.dart';
import '../../services/fall_prediction/fall_prediction_engine.dart';
import '../../services/health_connect_service.dart';

/// Client-side fall prediction scores.
class FallPredictionProvider extends ChangeNotifier {
  final FallPredictionEngine _engine = FallPredictionEngine();

  PredictionResult? _currentResult;
  PredictionResult? get currentResult => _currentResult;

  StreamSubscription<UserAccelerometerEvent>? _accelSubscription;
  Timer? _healthSyncTimer;
  int _sensorRefCount = 0;

  double _lastMagnitude = 0.0;

  PhysiologicalData _pData = PhysiologicalData(
    heartRate: 100,
    hrv: 100,
    bloodPressure: 100,
    spo2: 100,
    skinTemperature: 100,
  );

  BehavioralData _rData = BehavioralData(
    sleepDuration: 100,
    sleepQuality: 100,
    dailyActivity: 100,
    workoutLoad: 100,
    stress: 0,
  );

  final WomensHealthData _wData = WomensHealthData(
    isApplicable: false,
    daysSinceLastPeriod: 0,
    cycleLength: 28,
    isPMS: false,
  );

  final ContextFactors _context = ContextFactors();

  FallPredictionProvider() {
    _fetchHealthData();
    _healthSyncTimer =
        Timer.periodic(const Duration(minutes: 5), (_) => _fetchHealthData());
  }

  void acquireSensors() {
    _sensorRefCount++;
    if (_sensorRefCount == 1) {
      _startSensorListeners();
    }
  }

  void releaseSensors() {
    if (_sensorRefCount <= 0) return;
    _sensorRefCount--;
    if (_sensorRefCount == 0) {
      _accelSubscription?.cancel();
      _accelSubscription = null;
    }
  }

  Future<void> _fetchHealthData() async {
    final healthService = HealthConnectService.instance;
    final isAvailable = await healthService.isAvailable();
    if (!isAvailable) {
      _recalculate();
      return;
    }

    final types = await healthService.loadEnabledTypes();
    final today = await healthService.fetchToday(types);

    double hrScore = 100.0;
    if (today.avgHeartRate != null) {
      hrScore =
          (100.0 - ((today.avgHeartRate! - 70).abs() * 1.5)).clamp(0.0, 100.0);
    }

    double hrvScore = 100.0;
    if (today.avgHrv != null) {
      hrvScore = (today.avgHrv! / 60.0 * 100.0).clamp(0.0, 100.0);
    }

    double bpScore = 100.0;
    if (today.bpSystolic != null && today.bpDiastolic != null) {
      final sysDiff = (today.bpSystolic! - 120).abs().toDouble();
      final diaDiff = (today.bpDiastolic! - 80).abs().toDouble();
      bpScore = (100.0 - (sysDiff + diaDiff) * 1.5).clamp(0.0, 100.0);
    }

    double spo2Score = 100.0;
    if (today.avgSpo2 != null) {
      spo2Score = today.avgSpo2! >= 95
          ? 100.0
          : ((today.avgSpo2! - 80) / 15 * 100).clamp(0.0, 100.0);
    }

    double tempScore = 100.0;
    if (today.avgTemperatureC != null) {
      tempScore =
          (100.0 - (today.avgTemperatureC! - 36.5).abs() * 20).clamp(0.0, 100.0);
    }

    _pData = PhysiologicalData(
      heartRate: hrScore,
      hrv: hrvScore,
      bloodPressure: bpScore,
      spo2: spo2Score,
      skinTemperature: tempScore,
    );

    double sleepDurScore = 100.0;
    if (today.sleepMinutes != null) {
      sleepDurScore = (today.sleepMinutes! / 480.0 * 100.0).clamp(0.0, 100.0);
    }

    var sleepQualScore = sleepDurScore;
    if (today.deepMinutes != null &&
        today.sleepMinutes != null &&
        today.sleepMinutes! > 0) {
      final deepPct = today.deepMinutes! / today.sleepMinutes!;
      sleepQualScore = (deepPct / 0.2 * 100.0).clamp(0.0, 100.0);
    }

    double activityScore = 100.0;
    if (today.steps != null) {
      activityScore = (today.steps! / 10000.0 * 100.0).clamp(0.0, 100.0);
    }

    final stressScore = (100.0 - hrvScore).clamp(0.0, 100.0);

    _rData = BehavioralData(
      sleepDuration: sleepDurScore,
      sleepQuality: sleepQualScore,
      dailyActivity: activityScore,
      workoutLoad: activityScore,
      stress: stressScore,
    );

    _recalculate();
  }

  void _startSensorListeners() {
    _accelSubscription?.cancel();
    _accelSubscription =
        userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      final magnitude =
          sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      _lastMagnitude = magnitude;
      if (magnitude > 15.0) {
        _recalculate();
      }
    });
  }

  void _recalculate() {
    var impact = (_lastMagnitude / 50.0) * 100;
    impact = impact.clamp(0.0, 100.0);

    final mData = MotionData(
      impact: impact,
      orientation: 95,
      recoveryAttempts: 100,
      fallHistory: 10,
      accelerationMagnitude: _lastMagnitude,
    );

    _currentResult = _engine.calculateRisk(
      pData: _pData,
      rData: _rData,
      mData: mData,
      wData: _wData,
      context: _context,
    );

    notifyListeners();
  }

  @override
  void dispose() {
    _healthSyncTimer?.cancel();
    _accelSubscription?.cancel();
    _sensorRefCount = 0;
    super.dispose();
  }
}
