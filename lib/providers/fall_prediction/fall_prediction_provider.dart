import 'dart:async';
import 'package:flutter/material.dart';

import '../../models/fall_prediction/layer_inputs.dart';
import '../../models/fall_prediction/context_factors.dart';
import '../../models/fall_prediction/prediction_result.dart';
import '../../models/fall_prediction/engine_outputs.dart';
import '../../services/fall_prediction/fall_prediction_engine.dart';
import '../../services/fall_prediction/layer2_recovery.dart';
import '../../services/fall_prediction/layer1_physiology.dart' show BpSource;
import '../../services/health_connect_service.dart';
import '../../services/local_vitals_service.dart';
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
    // Recompute as soon as new ring readings arrive instead of waiting for
    // the 15-minute sync (the first score after launch was computed before
    // any reading existed and read "not enough data" for up to 15 minutes).
    final signature = _bleSignature(ble);
    if (signature != _lastBleSignature) {
      _lastBleSignature = signature;
      _scheduleRefresh();
    }
  }

  /// Recompute now, e.g. when the Fall Risk tab is opened.
  Future<void> refresh() => _fetchHealthData();

  // Battery: a burst of readings (one measurement cycle) costs one pass.
  static const _minRefreshGap = Duration(seconds: 60);
  String? _lastBleSignature;
  DateTime? _lastFetchAt;
  bool _fetching = false;

  String _bleSignature(BleProvider b) =>
      '${b.todayAvgHr}|${b.todayAvgHrv}|${b.todayAvgSpo2}|${b.latestTempC}|'
      '${b.latestBpSbp}/${b.latestBpDbp}|${b.todaySleepDuration}|${b.todaySteps}';

  void _scheduleRefresh() {
    if (_recalcDebounce?.isActive ?? false) return;
    final last = _lastFetchAt;
    var wait = last == null
        ? const Duration(seconds: 2)
        : _minRefreshGap - DateTime.now().difference(last);
    if (wait < const Duration(seconds: 2)) wait = const Duration(seconds: 2);
    _recalcDebounce = Timer(wait, () {
      if (!_disposed) _fetchHealthData();
    });
  }

  PredictionResult? _currentResult;
  PredictionResult? get currentResult => _currentResult;

  Timer? _healthSyncTimer;
  Timer? _recalcDebounce;

  List<FallEvent>? _cachedTrailingFalls;
  DateTime? _lastFallsFetch;
  ({double? steps, double? median, double? spread})? _cachedStepsBaseline;
  DateTime? _lastStepsFetch;

  /// Latest native motion-monitoring snapshot (FallMotionDetector state).
  /// Exposed for future UI ("monitoring active/idle"); deliberately NOT fed
  /// into scoring — sensors only run during HIGH-tier risk windows, so the
  /// sample is biased and "quiet while watched 10 min" must not read as
  /// general stability.
  Map<String, dynamic> _motionSnapshot = const {};
  Map<String, dynamic> get motionSnapshot =>
      Map<String, dynamic>.unmodifiable(_motionSnapshot);

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
          _bleProvider?.raiseFallAlert(reason);
        },
      ),
      corroborationService: _MockCorroborationService(),
    );
    _fetchHealthData();
    // Battery: was every 5 min with ~8 heavy Health Connect queries per fire.
    // 15 min is plenty for fall-risk baselines (trailing falls already 24h-cached).
    _healthSyncTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _fetchHealthData(),
    );
  }

  Future<void> _fetchHealthData() async {
    if (_fetching || _disposed) return;
    _fetching = true;
    _lastFetchAt = DateTime.now();
    try {
      await _gatherInputs();
    } finally {
      _fetching = false;
    }
  }

  Future<void> _gatherInputs() async {
    final healthService = HealthConnectService.instance;
    final isAvailable = await healthService.isAvailable();
    // Without Health Connect the ring's own readings below are the only
    // source; they used to be skipped entirely on such phones.
    var today = const HealthConnectToday();
    var historicalBaselines = <String, double>{};
    if (isAvailable) {
      final types = await healthService.loadEnabledTypes();
      today = await healthService.fetchToday(types);
      historicalBaselines = await healthService.fetchHistoricalBaselines();
    }

    final bleHr = _bleProvider?.todayAvgHr;
    final bleHrv = _bleProvider?.todayAvgHrv;
    final bleSpo2 = _bleProvider?.todayAvgSpo2;
    final bleTemp = _bleProvider?.latestTempC;
    final bleSys = _bleProvider?.latestBpSbp;
    final bleDia = _bleProvider?.latestBpDbp;

    _pData = Layer1PhysiologyData(
      hr: today.avgHeartRate ?? (bleHr != null && bleHr > 0 ? bleHr.toDouble() : null),
      hrv: today.avgHrv ?? (bleHrv != null && bleHrv > 0 ? bleHrv.toDouble() : null),
      bp: null, // We'll pass sys and dia directly
      spo2: today.avgSpo2 ?? (bleSpo2 != null && bleSpo2 > 0 ? bleSpo2.toDouble() : null),
      temp: today.avgTemperatureC ?? (bleTemp != null && bleTemp > 0 ? bleTemp : null),
      sys: today.bpSystolic?.toDouble() ??
          (bleSys != null && bleSys > 0 && bleDia != null && bleDia > 0 ? bleSys.toDouble() : null),
      dia: today.bpDiastolic?.toDouble() ??
          (bleSys != null && bleSys > 0 && bleDia != null && bleDia > 0 ? bleDia.toDouble() : null),
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
    final finalDeepMinutes = bleSleepDeepSecs != null && bleSleepDeepSecs > 0 ? bleSleepDeepSecs / 60.0 : null;
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



  /// Daily step history from the phone's local store, refreshed hourly
  /// (it only changes once a day).
  Future<({double? steps, double? median, double? spread})> _stepsBaseline(DateTime now) async {
    final cached = _cachedStepsBaseline;
    if (cached != null && _lastStepsFetch != null && now.difference(_lastStepsFetch!).inHours < 1) {
      return cached;
    }
    try {
      final rows = await LocalVitalsService().getHistory('steps', days: 36, end: now);
      final daily = <DateTime, int>{};
      for (final r in rows) {
        final dayMs = (r['dayEpochMs'] as num?)?.toInt();
        final steps = (r['steps'] as num?)?.toInt() ?? (r['avg'] as num?)?.round() ?? 0;
        if (dayMs == null || steps <= 0) continue;
        final d = DateTime.fromMillisecondsSinceEpoch(dayMs);
        daily[DateTime(d.year, d.month, d.day)] = steps;
      }
      _cachedStepsBaseline = Layer3MotionService.stepsBaseline(daily, today: now);
      _lastStepsFetch = now;
    } catch (_) {
      _cachedStepsBaseline ??= (steps: null, median: null, spread: null);
    }
    return _cachedStepsBaseline!;
  }

  void _recalculate() async {
    // Primary source: native Room `fall_event` (written by FallMotionDetector
    // and FallRiskAnalyzer). The Supabase `falls` table is merged as a
    // secondary source for history that outlived the 90-day local retention
    // (ReadingRepository.purgeOldSyncedReadings) or came from another device.
    // Cache TTL is 1h (not 24h) so a fresh fall event feeds the next
    // 15-minute health sync promptly.
    List<FallEvent> trailingFalls = [];
    double? fh;
    final now = DateTime.now();
    final oneYearAgo = now.subtract(const Duration(days: 365));
    final fallsStale = _cachedTrailingFalls == null ||
        _lastFallsFetch == null ||
        now.difference(_lastFallsFetch!).inHours >= 1;
    if (fallsStale) {
      try {
        final nativeRows =
            await _bleProvider?.getFallEvents(limit: 500) ?? [];
        final nativeFalls = Layer3MotionService.parseNativeFallEvents(
          nativeRows,
          since: oneYearAgo,
        );
        final userId = SupabaseService.currentUser?.id;
        var remoteFalls = <FallEvent>[];
        if (userId != null) {
          try {
            remoteFalls = await Layer3MotionService(SupabaseService.client)
                .fetchTrailing12MonthFalls(userId);
          } catch (_) {
            remoteFalls = [];
          }
        }
        final merged = [...nativeFalls, ...remoteFalls]
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        _cachedTrailingFalls = merged;
        _lastFallsFetch = now;
        try {
          _motionSnapshot =
              await _bleProvider?.getMotionSnapshot() ?? const {};
        } catch (_) {
          _motionSnapshot = const {};
        }
      } catch (_) {
        // Keep the previous cache when the refresh fails; only fall back to
        // unknown history when there is nothing cached at all.
        _cachedTrailingFalls ??= [];
      }
      trailingFalls = _cachedTrailingFalls!;
    } else {
      trailingFalls = _cachedTrailingFalls!;
    }
    // Known-zero history (local DB queried) is 0.0; unknown (no source at
    // all) stays null so the coverage score penalizes honestly.
    fh = _bleProvider != null
        ? trailingFalls.length.toDouble()
        : (trailingFalls.isNotEmpty ? trailingFalls.length.toDouble() : null);
    // Motion (report, Table 3.3): the last full day's steps against the
    // personal 28-day median, and fall alerts in the last 14 days. Unknown
    // history (no source at all) stays null, as for fall history above.
    final stepsBaseline = await _stepsBaseline(now);
    final fourteenDaysAgo = now.subtract(const Duration(days: 14));
    final nearFalls = _bleProvider != null
        ? trailingFalls.where((f) => f.timestamp.isAfter(fourteenDaysAgo)).length
        : null;

    final mData = Layer3MotionData(
      steps: stepsBaseline.steps,
      stepsMedian: stepsBaseline.median,
      stepsSpread: stepsBaseline.spread,
      nearFalls14d: nearFalls,
      fh: fh,
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

    if (v2Result != null && !_disposed) {
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
        breakdown: v2Result.breakdown,
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
      _bleProvider?.simulateMediumFallPredictionBanner();
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
        frs24Score: score.round(),
        frs24Band: score.riskBand,
        topContributors: ['Heart Rate Variability', 'Activity Exposure'],
        frsContributors: ['Motion Instability', 'Recent Fall History'],
        coverageScoreQ: 95.0,
        coverageDetails: ['Good coverage'],
        recommendationAction: 'Take a rest',
        frsBreakdown: {
          'Motion Instability': 25,
          'Recovery Deficit': 10,
        },
      ),
    );
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _healthSyncTimer?.cancel();
    _recalcDebounce?.cancel();
    super.dispose();
  }
}
