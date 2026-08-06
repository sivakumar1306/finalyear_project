import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../models/fall_prediction/layer_inputs.dart';
import '../../models/fall_prediction/context_factors.dart';
import '../../models/fall_prediction/prediction_result.dart';
import '../../services/fall_prediction/fall_prediction_engine.dart';
import '../../services/fall_prediction/layer2_recovery.dart';
import '../../services/health_connect_service.dart';

import '../../services/fall_prediction/red_flag_override.dart';

class _MockEscalationService extends EscalationService {
  @override
  void triggerAlert({required EscalationLadder ladder, required String reason}) {
    // No-op for provider
  }
}

class _MockCorroborationService extends CorroborationService {
  @override
  Future<bool> verifyDualSource(CorroborationSource source) async {
    return false; // No-op
  }
}

/// Client-side fall prediction scores.
class FallPredictionProvider extends ChangeNotifier {
  final FallPredictionEngine _engine = FallPredictionEngine(
    redFlagService: RedFlagOverrideService(),
    escalationService: _MockEscalationService(),
    corroborationService: _MockCorroborationService(),
  );

  PredictionResult? _currentResult;
  PredictionResult? get currentResult => _currentResult;

  StreamSubscription<UserAccelerometerEvent>? _accelSubscription;
  Timer? _healthSyncTimer;
  int _sensorRefCount = 0;

  double _lastMagnitude = 0.0;
  ActivityExposure _lastActExp = const ActivityExposure(100.0);

  Layer1PhysiologyData _pData = Layer1PhysiologyData(
    hr: null,
    hrv: null,
    bp: null,
    spo2: null,
    temp: null,
  );

  Layer2RecoveryData _rData = Layer2RecoveryData(
    slp: null,
    slq: null,
    act: null,
    wkl: null,
    str: null,
  );

  final Layer4WomensHealthData _wData = Layer4WomensHealthData(
    isApplicable: false,
    hasConsentedToWomensHealth: false,
    cycleState: CycleState.optedOut,
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

    double? hrScore;
    if (today.avgHeartRate != null) {
      hrScore =
          (100.0 - ((today.avgHeartRate! - 70).abs() * 1.5)).clamp(0.0, 100.0);
    }

    double? hrvScore;
    if (today.avgHrv != null) {
      hrvScore = (today.avgHrv! / 60.0 * 100.0).clamp(0.0, 100.0);
    }

    double? bpScore;
    if (today.bpSystolic != null && today.bpDiastolic != null) {
      final sysDiff = (today.bpSystolic! - 120).abs().toDouble();
      final diaDiff = (today.bpDiastolic! - 80).abs().toDouble();
      bpScore = (100.0 - (sysDiff + diaDiff) * 1.5).clamp(0.0, 100.0);
    }

    double? spo2Score;
    if (today.avgSpo2 != null) {
      spo2Score = today.avgSpo2! >= 95
          ? 100.0
          : ((today.avgSpo2! - 80) / 15 * 100).clamp(0.0, 100.0);
    }

    double? tempScore;
    if (today.avgTemperatureC != null) {
      tempScore =
          (100.0 - (today.avgTemperatureC! - 36.5).abs() * 20).clamp(0.0, 100.0);
    }

    _pData = Layer1PhysiologyData(
      hr: hrScore,
      hrv: hrvScore,
      bp: bpScore,
      spo2: spo2Score,
      temp: tempScore,
    );

    double? sleepDurScore;
    if (today.sleepMinutes != null) {
      sleepDurScore = (today.sleepMinutes! / 480.0 * 100.0).clamp(0.0, 100.0);
    }

    double? sleepQualScore = sleepDurScore;
    if (today.deepMinutes != null &&
        today.sleepMinutes != null &&
        today.sleepMinutes! > 0) {
      final deepPct = today.deepMinutes! / today.sleepMinutes!;
      sleepQualScore = (deepPct / 0.2 * 100.0).clamp(0.0, 100.0);
    }

    double? activityScore;
    if (today.steps != null) {
      activityScore = (today.steps! / 10000.0 * 100.0).clamp(0.0, 100.0);
    }

    double? stressScore;
    if (hrvScore != null) {
      stressScore = (100.0 - hrvScore).clamp(0.0, 100.0);
    }

    ActivityRecovery? actRecovery;
    if (activityScore != null) {
      final activitySplit = ActivityDataTransformer.splitRawActivity(activityScore);
      _lastActExp = activitySplit.$2;
      actRecovery = activitySplit.$1;
    }

    _rData = Layer2RecoveryData(
      slp: sleepDurScore,
      slq: sleepQualScore,
      act: actRecovery,
      wkl: activityScore,
      str: stressScore,
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
    final mData = Layer3MotionData(
      acc: _lastMagnitude,
      gyr: null,
      gait: null,
      psw: null,
      ortho: null,
      plnt: null,
      fh: 10,
      actExp: _lastActExp,
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

