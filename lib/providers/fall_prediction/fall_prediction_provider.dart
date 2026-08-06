import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../models/fall_prediction/layer_inputs.dart';
import '../../models/fall_prediction/context_factors.dart';
import '../../models/fall_prediction/prediction_result.dart';
import '../../services/fall_prediction/fall_prediction_engine.dart';
import '../../services/fall_prediction/layer2_recovery.dart';
import '../../services/fall_prediction/layer1_physiology.dart' show BpSource;
import '../../services/health_connect_service.dart';
import '../ble_provider.dart';
import '../../services/supabase_service.dart';
import '../../services/fall_prediction/layer3_motion.dart';

import '../../services/fall_prediction/red_flag_override.dart';

class _RealEscalationService extends EscalationService {
  final Future<void> Function(String reason)? onAlert;

  _RealEscalationService({this.onAlert});

  @override
  void triggerAlert({required EscalationLadder ladder, required String reason}) {
    onAlert?.call(reason);
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
  late final FallPredictionEngine _engine;
  BleProvider? _bleProvider;

  void updateBleProvider(BleProvider ble) {
    _bleProvider = ble;
  }

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

  Layer4WomensHealthData _wData = Layer4WomensHealthData(
    isApplicable: false,
    hasConsentedToWomensHealth: false,
    cycleState: CycleState.optedOut,
    daysSinceLastPeriod: 0,
    cycleLength: 28,
    isPMS: false,
  );

  final ContextFactors _context = ContextFactors();

  FallPredictionProvider() {
    _engine = FallPredictionEngine(
      redFlagService: RedFlagOverrideService(),
      escalationService: _RealEscalationService(
        onAlert: (reason) async {
          await _bleProvider?.sendEmergencySms(message: reason);
        },
      ),
      corroborationService: _MockCorroborationService(),
    );
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

    final historicalBaselines = await healthService.fetchHistoricalBaselines();
    
    _pData = Layer1PhysiologyData(
      hr: today.avgHeartRate,
      hrv: today.avgHrv,
      bp: null, // We'll pass sys and dia directly
      spo2: today.avgSpo2,
      temp: today.avgTemperatureC,
      sys: today.bpSystolic?.toDouble(),
      dia: today.bpDiastolic?.toDouble(),
      baselines: Layer1Baselines(
        rolling14DayMedianHR: historicalBaselines['rolling14DayMedianHR'] ?? 65.0,
        rolling28DayMeanHRV: historicalBaselines['rolling28DayMeanHRV'] ?? 45.0,
        rolling28DayStdDevHRV: historicalBaselines['rolling28DayStdDevHRV'] ?? 8.0,
        baselineAdjustedTemp: historicalBaselines['baselineAdjustedTemp'] ?? 36.5,
      ),
    );

    if (today.hasMenstruationData && today.daysSinceLastPeriod != null) {
      bool isPMS = today.daysSinceLastPeriod! >= 21 && today.daysSinceLastPeriod! <= 28;
      CycleState state = CycleState.active;
      _wData = Layer4WomensHealthData(
        isApplicable: true,
        hasConsentedToWomensHealth: true,
        cycleState: state,
        daysSinceLastPeriod: today.daysSinceLastPeriod!,
        cycleLength: 28,
        isPMS: isPMS,
      );
    } else {
      _wData = Layer4WomensHealthData(
        isApplicable: false,
        hasConsentedToWomensHealth: false,
        cycleState: CycleState.optedOut,
        daysSinceLastPeriod: 0,
        cycleLength: 28,
        isPMS: false,
      );
    }

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
    if (today.avgHrv != null) {
      stressScore = (100.0 - (today.avgHrv! / 60.0 * 100.0).clamp(0.0, 100.0)).clamp(0.0, 100.0);
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

  void _recalculate() async {
    final userId = SupabaseService.currentUser?.id;
    List<FallEvent> trailingFalls = [];
    if (userId != null) {
      final layer3Svc = Layer3MotionService(SupabaseService.client);
      trailingFalls = await layer3Svc.fetchTrailing12MonthFalls(userId);
    }

    final mData = Layer3MotionData(
      acc: _lastMagnitude,
      gyr: null,
      gait: null,
      psw: null,
      ortho: null,
      plnt: null,
      fh: null,
      actExp: _lastActExp,
    );

    final v2Result = await _engine.calculateFRSv2(
      pData: _pData,
      rData: _rData,
      mData: mData,
      wData: _wData,
      bpSource: BpSource.none, // Fallback assumption
      context: _context,
      trailingFalls: trailingFalls,
    );

    if (v2Result != null) {
      _currentResult = PredictionResult(
        hsiBase: v2Result.hsiBase,
        hsi: v2Result.hsiAdj,
        frs24: v2Result.frs24,
        frs30: v2Result.frs30,
        riskLevel: RiskClassification.low, // Deprecated in UI, UI uses frs24.value.riskBand
        tau: v2Result.predictionHorizon,
        q: v2Result.coverageScore,
        explainability: v2Result.explainability,
      );
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _healthSyncTimer?.cancel();
    _accelSubscription?.cancel();
    _sensorRefCount = 0;
    super.dispose();
  }
}

