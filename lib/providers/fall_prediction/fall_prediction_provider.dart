import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../models/fall_prediction/layer_inputs.dart';
import '../../models/fall_prediction/context_factors.dart';
import '../../models/fall_prediction/prediction_result.dart';
import '../../models/fall_prediction/engine_outputs.dart';
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
  void triggerAlert({
    required EscalationLadder ladder,
    required String reason,
  }) {
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
  Timer? _recalcDebounce;
  int _sensorRefCount = 0;

  List<FallEvent>? _cachedTrailingFalls;
  DateTime? _lastFallsFetch;

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
    _healthSyncTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _fetchHealthData(),
    );
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

    final bleHr = _bleProvider?.todayAvgHr;
    final bleHrv = _bleProvider?.todayAvgHrv;
    final bleSpo2 = _bleProvider?.todayAvgSpo2;
    
    _pData = Layer1PhysiologyData(
      hr: today.avgHeartRate ?? (bleHr != null && bleHr > 0 ? bleHr.toDouble() : null),
      hrv: today.avgHrv ?? (bleHrv != null && bleHrv > 0 ? bleHrv.toDouble() : null),
      bp: null, // We'll pass sys and dia directly
      spo2: today.avgSpo2 ?? (bleSpo2 != null && bleSpo2 > 0 ? bleSpo2.toDouble() : null),
      temp: today.avgTemperatureC,
      sys: today.bpSystolic?.toDouble(),
      dia: today.bpDiastolic?.toDouble(),
      baselines: Layer1Baselines(
        rolling14DayMedianHR:
            historicalBaselines['rolling14DayMedianHR'] ?? 65.0,
        rolling28DayMeanHRV: historicalBaselines['rolling28DayMeanHRV'] ?? 45.0,
        rolling28DayStdDevHRV:
            historicalBaselines['rolling28DayStdDevHRV'] ?? 8.0,
        baselineAdjustedTemp:
            historicalBaselines['baselineAdjustedTemp'] ?? 36.5,
      ),
    );

    if (today.hasMenstruationData && today.daysSinceLastPeriod != null) {
      bool isPMS =
          today.daysSinceLastPeriod! >= 21 && today.daysSinceLastPeriod! <= 28;
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

    final bleSleepSecs = _bleProvider?.todaySleepDuration;
    final bleSleepDeepSecs = _bleProvider?.todaySleepDeepSecs;
    final bleSteps = _bleProvider?.todaySteps;
    
    double? sleepDurScore;
    final finalSleepMinutes = today.sleepMinutes ?? (bleSleepSecs != null && bleSleepSecs > 0 ? bleSleepSecs / 60.0 : null);
    if (finalSleepMinutes != null) {
      sleepDurScore = (finalSleepMinutes / 480.0 * 100.0).clamp(0.0, 100.0);
    }

    double? sleepQualScore = sleepDurScore;
    final finalDeepMinutes = today.deepMinutes ?? (bleSleepDeepSecs != null && bleSleepDeepSecs > 0 ? bleSleepDeepSecs / 60.0 : null);
    if (finalDeepMinutes != null &&
        finalSleepMinutes != null &&
        finalSleepMinutes > 0) {
      final deepPct = finalDeepMinutes / finalSleepMinutes;
      sleepQualScore = (deepPct / 0.2 * 100.0).clamp(0.0, 100.0);
    }

    double? activityScore;
    final finalSteps = today.steps ?? (bleSteps != null && bleSteps > 0 ? bleSteps : null);
    if (finalSteps != null) {
      activityScore = (finalSteps / 10000.0 * 100.0).clamp(0.0, 100.0);
    }

    double? stressScore;
    final finalAvgHrv = today.avgHrv ?? (bleHrv != null && bleHrv > 0 ? bleHrv.toDouble() : null);
    if (finalAvgHrv != null) {
      stressScore = (100.0 - (finalAvgHrv / 60.0 * 100.0).clamp(0.0, 100.0))
          .clamp(0.0, 100.0);
    }

    ActivityRecovery? actRecovery;
    if (activityScore != null) {
      final activitySplit = ActivityDataTransformer.splitRawActivity(
        activityScore,
      );
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
    _accelSubscription = userAccelerometerEventStream().listen((
      UserAccelerometerEvent event,
    ) {
      final magnitude = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      _lastMagnitude = magnitude;
      if (magnitude > 15.0) {
        _debounceRecalculate();
      }
    });
  }

  void _debounceRecalculate() {
    if (_recalcDebounce?.isActive ?? false) return;
    _recalcDebounce = Timer(const Duration(seconds: 2), () {
      _recalculate();
    });
  }

  void _recalculate() async {
    final userId = SupabaseService.currentUser?.id;
    List<FallEvent> trailingFalls = [];
    if (userId != null) {
      final now = DateTime.now();
      if (_cachedTrailingFalls == null ||
          _lastFallsFetch == null ||
          now.difference(_lastFallsFetch!).inHours >= 24) {
        final layer3Svc = Layer3MotionService(SupabaseService.client);
        _cachedTrailingFalls = await layer3Svc.fetchTrailing12MonthFalls(
          userId,
        );
        _lastFallsFetch = now;
      }
      trailingFalls = _cachedTrailingFalls!;
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
        riskLevel: RiskClassification
            .low, // Deprecated in UI, UI uses frs24.value.riskBand
        tau: v2Result.predictionHorizon,
        q: v2Result.coverageScore,
        explainability: v2Result.explainability,
      );
      notifyListeners();
    }
  }

  void simulateTier(String tier) {
    if (tier == 'clear') {
      _recalculate();
      return;
    }

    double score = 10.0;
    if (tier == 'high') {
      score = 75.0;
      _bleProvider?.simulateFallPrediction();
    }
    if (tier == 'medium') {
      score = 45.0;
    }

    _currentResult = PredictionResult(
      hsiBase: HsiBase(80.0),
      hsi: HsiAdj(70.0),
      frs24: Frs24(score),
      frs30: Frs30(score - 5.0),
      riskLevel: tier == 'high'
          ? RiskClassification.high
          : RiskClassification.moderate,
      tau: PredictionHorizon(const Duration(hours: 24)),
      q: CoverageScore(95.0),
      explainability: ExplainabilityPayload(
        hsiBase: 80,
        hsiBaseline: 85,
        hsiAdj: 70,
        attributionDeltas: AttributionDeltas(
          contextShiftDelta: -5,
          physiologicalDelta: -10,
        ),
        frs24Score: score.toInt(),
        frs24Band: score >= 60.0 ? FrsRiskBand.high : FrsRiskBand.moderate,
        topContributors: ['Heart Rate Variability', 'Activity Exposure'],
        coverageScoreQ: 95.0,
        coverageDetails: ['Good coverage'],
        recommendationAction: 'Take a rest',
      ),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _healthSyncTimer?.cancel();
    _accelSubscription?.cancel();
    _recalcDebounce?.cancel();
    _sensorRefCount = 0;
    super.dispose();
  }
}
