import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'incident_service.dart';


enum HealthSyncType {
  steps,
  heartRate,
  hrv,
  bloodOxygen,
  sleep,
  bloodPressure,
  temperature,
  menstruation,
}

extension HealthSyncTypeLabel on HealthSyncType {
  String get label => switch (this) {
        HealthSyncType.steps => 'Steps',
        HealthSyncType.heartRate => 'Heart Rate',
        HealthSyncType.hrv => 'Heart Rate Variability',
        HealthSyncType.bloodOxygen => 'Blood Oxygen (SpO2)',
        HealthSyncType.sleep => 'Sleep',
        HealthSyncType.bloodPressure => 'Blood Pressure',
        HealthSyncType.temperature => 'Temperature',
        HealthSyncType.menstruation => 'Menstruation',
      };

  String get subtitle => switch (this) {
        HealthSyncType.steps => 'Daily step count',
        HealthSyncType.heartRate => 'Beats per minute',
        HealthSyncType.hrv => 'RMSSD in milliseconds',
        HealthSyncType.bloodOxygen => 'Oxygen saturation %',
        HealthSyncType.sleep => 'Sleep stages & duration',
        HealthSyncType.bloodPressure => 'Systolic / diastolic',
        HealthSyncType.temperature => 'Body temperature',
        HealthSyncType.menstruation => 'Cycle & period tracking',
      };
}

class HealthConnectToday {
  final int? steps;
  final double? avgHeartRate;
  final double? avgHrv;
  final double? avgSpo2;
  final int? sleepMinutes;
  final int? bpSystolic;
  final int? bpDiastolic;
  final double? avgTemperatureC;
  final bool hasMenstruationData;
  final int? daysSinceLastPeriod;

  const HealthConnectToday({
    this.steps,
    this.avgHeartRate,
    this.avgHrv,
    this.avgSpo2,
    this.sleepMinutes,
    this.bpSystolic,
    this.bpDiastolic,
    this.avgTemperatureC,
    this.hasMenstruationData = false,
    this.daysSinceLastPeriod,
  });
}

class HealthConnectService {
  HealthConnectService._();

  static final HealthConnectService instance = HealthConnectService._();

  Health? _health;
  bool? _cachedAvailability;

  static const _kEnabledPrefsKey = 'hc_enabled_types_v2';
  static const _kConnectedPrefsKey = 'hc_connected';

  // ── Health → HealthSyncType mapping ──────────────────────────────────────

  static final Map<HealthSyncType, List<HealthDataType>> _typeMap = {
    HealthSyncType.steps: [HealthDataType.STEPS],
    HealthSyncType.heartRate: [HealthDataType.HEART_RATE],
    HealthSyncType.hrv: [HealthDataType.HEART_RATE_VARIABILITY_RMSSD],
    HealthSyncType.bloodOxygen: [HealthDataType.BLOOD_OXYGEN],
    HealthSyncType.sleep: [
      HealthDataType.SLEEP_REM,
      HealthDataType.SLEEP_LIGHT,
      HealthDataType.SLEEP_DEEP,
      HealthDataType.SLEEP_AWAKE,
    ],
    HealthSyncType.bloodPressure: [
      HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
      HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
    ],
    HealthSyncType.temperature: [HealthDataType.BODY_TEMPERATURE],
    HealthSyncType.menstruation: [HealthDataType.MENSTRUATION_FLOW],
  };

  // ── Sleep configuration ──────────────────────────────────────────────────

  static const _kSleepStageDistribution = [
    (type: 'awake', fraction: 0.05),
    (type: 'light', fraction: 0.40),
    (type: 'deep', fraction: 0.20),
    (type: 'light', fraction: 0.10),
    (type: 'rem', fraction: 0.20),
    (type: 'light', fraction: 0.05),
  ];

  // ── Persistence ──────────────────────────────────────────────────────────

  Future<Set<HealthSyncType>> loadEnabledTypes() async {
    final prefs = await SharedPreferences.getInstance();
    final names = prefs.getStringList(_kEnabledPrefsKey) ?? [];
    return names
        .map((n) => HealthSyncType.values.where((t) => t.name == n).firstOrNull)
        .whereType<HealthSyncType>()
        .toSet();
  }

  Future<void> saveEnabledTypes(Set<HealthSyncType> types) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kEnabledPrefsKey,
      types.map((t) => t.name).toList(),
    );
    invalidateWriteCache();
  }

  Future<bool> loadConnected() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kConnectedPrefsKey) ?? false;
  }

  Future<void> saveConnected(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kConnectedPrefsKey, value);
    invalidateWriteCache();
  }

  // ── Initialization ───────────────────────────────────────────────────────

  Health get _client => _health ??= Health();

  Future<bool> isAvailable() async {
    if (_cachedAvailability != null) return _cachedAvailability!;
    try {
      _cachedAvailability = await _client.isHealthConnectAvailable();
      return _cachedAvailability!;
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'health_connect_service',
        error: e,
        stackTrace: st,
        customMessage: 'isAvailable failed',
      );
      _cachedAvailability = false;
      return false;
    }
  }

  Future<void> installHealthConnect() async {
    try {
      await _client.installHealthConnect();
      _cachedAvailability = null;
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'health_connect_service',
        error: e,
        stackTrace: st,
        customMessage: 'installHealthConnect failed',
      );
    }
  }

  // ── Authorization ────────────────────────────────────────────────────────

  Future<bool> requestAuthorization(Set<HealthSyncType> types) async {
    try {
      final healthTypes = _typesForSync(types);
      if (healthTypes.isEmpty) return false;
      // health 13.x requests READ-only when permissions are omitted, so ask
      // for READ+WRITE explicitly — the screen promises both and every
      // tryWrite* call needs WRITE.
      final permissions = List<HealthDataAccess>.filled(
        healthTypes.length,
        HealthDataAccess.READ_WRITE,
      );
      return await _client.requestAuthorization(
        healthTypes,
        permissions: permissions,
      );
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'health_connect_service',
        error: e,
        stackTrace: st,
        customMessage: 'requestAuthorization failed for $types',
      );
      return false;
    }
  }

  Future<void> revokePermissions() async {
    invalidateWriteCache();
    try {
      await _client.revokePermissions();
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'health_connect_service',
        error: e,
        stackTrace: st,
        customMessage: 'revokePermissions failed',
      );
    }
  }

  /// Returns the subset of [types] that have WRITE access granted in Health
  /// Connect. (hasPermissions defaults to a READ-only check when permissions
  /// are omitted, so WRITE must be passed explicitly.)
  Future<Set<HealthSyncType>> refreshWriteGrants(
    Set<HealthSyncType> types,
  ) async =>
      _refreshGrants(types, HealthDataAccess.WRITE);

  /// Returns the subset of [types] that have READ access granted in Health
  /// Connect. Used for the read path (Today preview, baselines) so a
  /// read-only grant still shows data.
  Future<Set<HealthSyncType>> refreshReadGrants(
    Set<HealthSyncType> types,
  ) async =>
      _refreshGrants(types, HealthDataAccess.READ);

  Future<Set<HealthSyncType>> _refreshGrants(
    Set<HealthSyncType> types,
    HealthDataAccess access,
  ) async {
    final granted = <HealthSyncType>{};
    for (final type in types) {
      try {
        final hTypes = _typeMap[type];
        if (hTypes == null || hTypes.isEmpty) continue;
        final permissions = List<HealthDataAccess>.filled(
          hTypes.length,
          access,
        );
        final hasPerm = await _client.hasPermissions(
          hTypes,
          permissions: permissions,
        );
        if (hasPerm == true) granted.add(type);
      } catch (_) {
        // health package throws on some types; treat as not granted.
      }
    }
    return granted;
  }

  // ── Write gating ─────────────────────────────────────────────────────────

  Set<HealthSyncType>? _writableCache;
  DateTime? _writableCacheTime;
  static const _writableCacheTtl = Duration(minutes: 5);

  /// Returns true when [type] is user-enabled and holds Health Connect WRITE
  /// permission. Results are cached briefly so hot paths (ring reading loop)
  /// don't hit the method channel and SharedPreferences on every sample.
  /// Without this gate every tryWrite* throws when unauthorized.
  Future<bool> canWrite(HealthSyncType type) async {
    final now = DateTime.now();
    if (_writableCache != null &&
        _writableCacheTime != null &&
        now.difference(_writableCacheTime!) < _writableCacheTtl) {
      return _writableCache!.contains(type);
    }
    try {
      final enabled = await loadEnabledTypes();
      final granted = await refreshWriteGrants(enabled);
      _writableCache = granted;
      _writableCacheTime = now;
      return granted.contains(type);
    } catch (_) {
      return false;
    }
  }

  /// Clears the cached write-grant set. Called whenever grants may have
  /// changed (connect / disconnect / toggle).
  void invalidateWriteCache() {
    _writableCache = null;
    _writableCacheTime = null;
  }

  // ── Writes ───────────────────────────────────────────────────────────────

  Future<void> tryWriteSteps(int steps, DateTime time) async {
    if (steps <= 0) return;
    if (!await canWrite(HealthSyncType.steps)) return;
    try {
      final ok = await _client.writeHealthData(
        value: steps.toDouble(),
        type: HealthDataType.STEPS,
        startTime: time,
        endTime: time,
      );
      if (!ok) {
        IncidentService.reportUnhandled(
          source: 'health_connect_service',
          error: 'writeHealthData returned false',
          stackTrace: StackTrace.current,
          customMessage: 'writeSteps failed (ok=false)',
        );
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'health_connect_service',
        error: e,
        stackTrace: st,
        customMessage: 'writeSteps failed',
      );
    }
  }

  Future<void> tryWriteHrv(num hrvMs, DateTime time) async {
    if (hrvMs <= 0) return;
    if (!await canWrite(HealthSyncType.hrv)) return;
    try {
      await _client.writeHealthData(
        value: hrvMs.toDouble(),
        type: HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
        startTime: time,
        endTime: time,
      );
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'health_connect_service',
        error: e,
        stackTrace: st,
        customMessage: 'writeHrv failed',
      );
    }
  }

  Future<void> tryWriteHeartRate(num bpm, DateTime time) async {
    if (bpm <= 0) return;
    if (!await canWrite(HealthSyncType.heartRate)) return;
    try {
      await _client.writeHealthData(
        value: bpm.toDouble(),
        type: HealthDataType.HEART_RATE,
        startTime: time,
        endTime: time,
      );
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'health_connect_service',
        error: e,
        stackTrace: st,
        customMessage: 'writeHeartRate failed',
      );
    }
  }

  Future<void> tryWriteSpo2(num percent, DateTime time) async {
    if (percent <= 0 || percent > 100) return;
    if (!await canWrite(HealthSyncType.bloodOxygen)) return;
    try {
      await _client.writeHealthData(
        value: percent.toDouble(),
        type: HealthDataType.BLOOD_OXYGEN,
        startTime: time,
        endTime: time,
      );
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'health_connect_service',
        error: e,
        stackTrace: st,
        customMessage: 'writeSpo2 failed',
      );
    }
  }

  /// Alias used by ble_provider.
  Future<void> tryWriteBloodOxygen(num percent, DateTime time) =>
      tryWriteSpo2(percent, time);

  Future<void> tryWriteTemperature(double celsius, DateTime time) async {
    if (celsius <= 0 || celsius > 50) return;
    if (!await canWrite(HealthSyncType.temperature)) return;
    try {
      await _client.writeHealthData(
        value: celsius,
        type: HealthDataType.BODY_TEMPERATURE,
        startTime: time,
        endTime: time,
      );
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'health_connect_service',
        error: e,
        stackTrace: st,
        customMessage: 'writeTemperature failed',
      );
    }
  }

  Future<void> tryWriteBloodPressure(
    num systolic,
    num diastolic,
    DateTime time,
  ) async {
    if (systolic <= 0 || diastolic <= 0) return;
    if (!await canWrite(HealthSyncType.bloodPressure)) return;
    // Health Connect stores BP as ONE BloodPressureRecord (systolic+diastolic
    // together). The generic writeHealthData path explicitly rejects both BP
    // types ("You must use the [writeBloodPressure] API") and silently
    // returns false — so the old two-call version never wrote anything.
    try {
      final ok = await _client.writeBloodPressure(
        systolic: systolic.toInt(),
        diastolic: diastolic.toInt(),
        startTime: time,
      );
      if (!ok) {
        IncidentService.reportUnhandled(
          source: 'health_connect_service',
          error: 'writeBloodPressure returned false',
          stackTrace: StackTrace.current,
          customMessage: 'writeBloodPressure failed (ok=false)',
        );
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'health_connect_service',
        error: e,
        stackTrace: st,
        customMessage: 'writeBloodPressure failed',
      );
    }
  }

  /// Writes sleep stages to Health Connect.
  ///
  /// Sleep is represented as a continuous timeline from [sleepTime] to [wakeTime]
  /// split into sequential stages (awake → light → deep → light → rem → light).
  /// Each stage occupies a contiguous time window with no gaps or overlaps.
  Future<void> tryWriteSleep({
    required DateTime sleepTime,
    required DateTime wakeTime,
    required int lightMinutes,
    required int deepMinutes,
    required int remMinutes,
    required int awakeMinutes,
  }) async {
    if (!await isAvailable()) return;
    if (!await canWrite(HealthSyncType.sleep)) return;
    // Health Connect rejects future end times — clamp to now.
    final now = DateTime.now();
    final effectiveWake = wakeTime.isAfter(now) ? now : wakeTime;
    if (sleepTime.isAfter(effectiveWake) ||
        sleepTime.isAtSameMomentAs(effectiveWake)) {
      return;
    }

    try {
      final stages = _buildSleepStages(
        sleepTime: sleepTime,
        wakeTime: effectiveWake,
        lightMinutes: lightMinutes,
        deepMinutes: deepMinutes,
        remMinutes: remMinutes,
        awakeMinutes: awakeMinutes,
      );

      for (final stage in stages) {
        // Skip degenerate stages — HC rejects from==to with PlatformException.
        if (!stage.to.isAfter(stage.from)) continue;
        await _client.writeHealthData(
          value: stage.value,
          type: stage.type,
          startTime: stage.from,
          endTime: stage.to,
        );
      }
    } catch (e, st) {
      // Permission revoked / HC disabled / invalid argument are expected:
      // drop the stale grant cache, stay silent, retry next sync.
      invalidateWriteCache();
      final s = e.toString();
      final expected = s.contains('SecurityException') ||
          s.contains('Security exception') ||
          s.contains('permission') ||
          s.contains('Permission') ||
          s.contains('not granted') ||
          s.contains('Invalid argument') ||
          s.contains('invalid argument') ||
          e is PlatformException;
      if (expected) {
        debugPrint('[HealthConnect] writeSleep suppressed (expected): $e');
        return;
      }
      IncidentService.reportUnhandled(
        source: 'health_connect_service',
        error: e,
        stackTrace: st,
        customMessage: 'writeSleep failed',
      );
    }
  }

  // ── Sleep stage builder ──────────────────────────────────────────────────

  List<_SleepStageEntry> _buildSleepStages({
    required DateTime sleepTime,
    required DateTime wakeTime,
    required int lightMinutes,
    required int deepMinutes,
    required int remMinutes,
    required int awakeMinutes,
  }) {
    final totalMinutes = wakeTime.difference(sleepTime).inMinutes;
    if (totalMinutes <= 0) return [];

    final actualMinutes = {
      'awake': awakeMinutes,
      'light': lightMinutes,
      'deep': deepMinutes,
      'rem': remMinutes,
    };

    final stages = <_SleepStageEntry>[];
    var current = sleepTime;

    for (final entry in _kSleepStageDistribution) {
      final targetMinutes = (totalMinutes * entry.fraction).round();
      final minutes = max(1, actualMinutes[entry.type] ?? targetMinutes);

      if (current.isAfter(wakeTime)) break;

      final end = current.add(Duration(minutes: minutes));
      final clampedEnd = end.isAfter(wakeTime) ? wakeTime : end;
      // Zero-duration windows are rejected by Health Connect — skip them.
      if (!clampedEnd.isAfter(current)) {
        current = clampedEnd;
        continue;
      }

      stages.add(
        _SleepStageEntry(
          type: _healthDataTypeForStage(entry.type),
          from: current,
          to: clampedEnd,
          value: _sleepStageValue(entry.type),
        ),
      );

      current = clampedEnd;
    }

    // Write any remaining awake time as the final stage.
    if (current.isBefore(wakeTime)) {
      stages.add(
        _SleepStageEntry(
          type: HealthDataType.SLEEP_AWAKE,
          from: current,
          to: wakeTime,
          value: _sleepStageValue('awake'),
        ),
      );
    }

    return stages;
  }

  HealthDataType _healthDataTypeForStage(String stage) => switch (stage) {
        'deep' => HealthDataType.SLEEP_DEEP,
        'rem' => HealthDataType.SLEEP_REM,
        'awake' => HealthDataType.SLEEP_AWAKE,
        _ => HealthDataType.SLEEP_LIGHT,
      };

  /// Numeric value written into Health Connect for each sleep stage.
  /// Deep=1, Light=2, REM=3, Awake=4 (matches HC convention).
  double _sleepStageValue(String stage) => switch (stage) {
        'deep' => 1.0,
        'light' => 2.0,
        'rem' => 3.0,
        _ => 4.0,
      };

  // ── Reads ────────────────────────────────────────────────────────────────

  Future<HealthConnectToday> fetchToday(Set<HealthSyncType> types) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final results = <HealthDataType, dynamic>{};

    for (final type in types) {
      final hTypes = _typeMap[type];
      if (hTypes == null) continue;

      for (final hType in hTypes) {
        try {
          final data = await _client.getHealthDataFromTypes(
            startTime: startOfDay,
            endTime: now,
            types: [hType],
          );
          results[hType] = data;
        } catch (e) {
          debugPrint('HC fetch error for $hType: $e');
        }
      }
    }

    return HealthConnectToday(
      steps: _sumSteps(types, results),
      avgHeartRate: _avgNumeric(HealthDataType.HEART_RATE, results),
      avgHrv: _avgNumeric(HealthDataType.HEART_RATE_VARIABILITY_RMSSD, results),
      avgSpo2: _avgNumeric(HealthDataType.BLOOD_OXYGEN, results),
      sleepMinutes: _sumSleepMinutes(results),
      bpSystolic: _avgInt(HealthDataType.BLOOD_PRESSURE_SYSTOLIC, results),
      bpDiastolic: _avgInt(HealthDataType.BLOOD_PRESSURE_DIASTOLIC, results),
      avgTemperatureC: _avgNumeric(HealthDataType.BODY_TEMPERATURE, results),
      hasMenstruationData: _hasData(HealthDataType.MENSTRUATION_FLOW, results),
      daysSinceLastPeriod: _daysSinceLastMenstruation(results),
    );
  }

  Future<Map<String, double>> fetchHistoricalBaselines() async {
    final now = DateTime.now();

    try {
      final stepsData = await _client.getHealthDataFromTypes(
        startTime: now.subtract(const Duration(days: 14)),
        endTime: now,
        types: [HealthDataType.STEPS],
      );
      final steps = _numericValues(HealthDataType.STEPS, stepsData);
      final avgSteps = steps.isNotEmpty ? _median(steps) : 0.0;

      final hrData = await _client.getHealthDataFromTypes(
        startTime: now.subtract(const Duration(days: 14)),
        endTime: now,
        types: [HealthDataType.HEART_RATE],
      );
      final hr = _numericValues(HealthDataType.HEART_RATE, hrData);
      final avgHR = hr.isNotEmpty ? _median(hr) : 70.0;

      final hrvData = await _client.getHealthDataFromTypes(
        startTime: now.subtract(const Duration(days: 28)),
        endTime: now,
        types: [HealthDataType.HEART_RATE_VARIABILITY_RMSSD],
      );
      final hrv = _numericValues(
        HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
        hrvData,
      );
      final avgHRV = hrv.isNotEmpty ? _median(hrv) : 50.0;

      final spo2Data = await _client.getHealthDataFromTypes(
        startTime: now.subtract(const Duration(days: 14)),
        endTime: now,
        types: [HealthDataType.BLOOD_OXYGEN],
      );
      final spo2 = _numericValues(HealthDataType.BLOOD_OXYGEN, spo2Data);
      final avgSpO2 = spo2.isNotEmpty ? _median(spo2) : 96.0;

      final tempData = await _client.getHealthDataFromTypes(
        startTime: now.subtract(const Duration(days: 14)),
        endTime: now,
        types: [HealthDataType.BODY_TEMPERATURE],
      );
      final temp = _numericValues(HealthDataType.BODY_TEMPERATURE, tempData);
      final avgTemp = temp.isNotEmpty ? _median(temp) : 36.5;

      final hrvStdDev = hrv.isNotEmpty ? _stdDev(hrv, avgHRV) : 8.0;

      return {
        'steps': avgSteps,
        'heartRate': avgHR,
        'hrv': avgHRV,
        'spo2': avgSpO2,
        'temperature': avgTemp,
        // Keys consumed by FallPredictionProvider (Layer1Baselines). The
        // provider previously read these keys while the map only contained
        // the short names above, so it always fell back to hardcoded
        // defaults and never actually used Health Connect history.
        'rolling14DayMedianHR': avgHR,
        'rolling28DayMeanHRV': avgHRV,
        'rolling28DayStdDevHRV': hrvStdDev,
        'baselineAdjustedTemp': avgTemp,
      };
    } catch (e) {
      debugPrint('Error fetching historical baselines: $e');
      return {
        'steps': 0,
        'heartRate': 70.0,
        'hrv': 50.0,
        'spo2': 96.0,
        'temperature': 36.5,
        'rolling14DayMedianHR': 65.0,
        'rolling28DayMeanHRV': 45.0,
        'rolling28DayStdDevHRV': 8.0,
        'baselineAdjustedTemp': 36.5,
      };
    }
  }

  // ── Read-only fetch methods ──────────────────────────────────────────────

  Future<double?> readLatestHeartRate() async {
    try {
      final now = DateTime.now();
      final data = await _client.getHealthDataFromTypes(
        startTime: now.subtract(const Duration(days: 1)),
        endTime: now,
        types: [HealthDataType.HEART_RATE],
      );
      final hrList = data.whereType<HealthDataPoint>().toList()
        ..sort((a, b) => b.dateTo.compareTo(a.dateTo));
      return hrList.isNotEmpty ? (hrList.first.value as NumericHealthValue).numericValue.toDouble() : null;
    } catch (_) {
      return null;
    }
  }

  Future<double?> readLatestHRV() async {
    try {
      final now = DateTime.now();
      final data = await _client.getHealthDataFromTypes(
        startTime: now.subtract(const Duration(days: 1)),
        endTime: now,
        types: [HealthDataType.HEART_RATE_VARIABILITY_RMSSD],
      );
      final list = data.whereType<HealthDataPoint>().toList()
        ..sort((a, b) => b.dateTo.compareTo(a.dateTo));
      return list.isNotEmpty ? (list.first.value as NumericHealthValue).numericValue.toDouble() : null;
    } catch (_) {
      return null;
    }
  }

  Future<double?> readLatestSpo2() async {
    try {
      final now = DateTime.now();
      final data = await _client.getHealthDataFromTypes(
        startTime: now.subtract(const Duration(days: 1)),
        endTime: now,
        types: [HealthDataType.BLOOD_OXYGEN],
      );
      final list = data.whereType<HealthDataPoint>().toList()
        ..sort((a, b) => b.dateTo.compareTo(a.dateTo));
      return list.isNotEmpty ? (list.first.value as NumericHealthValue).numericValue.toDouble() : null;
    } catch (_) {
      return null;
    }
  }

  Future<int?> readTotalStepsToday() async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final steps = await _client.getTotalStepsInInterval(startOfDay, now);
      return steps;
    } catch (_) {
      return null;
    }
  }

  // ── Aggregate helpers ────────────────────────────────────────────────────

  int? _sumSteps(Set<HealthSyncType> types, Map results) {
    if (!types.contains(HealthSyncType.steps)) return null;
    final list = results[HealthDataType.STEPS];
    if (list == null || list.isEmpty) return null;

    double total = 0;
    for (final dp in list) {
      total += (dp.value as NumericHealthValue).numericValue.toDouble();
    }
    return total.round();
  }

  double? _avgNumeric(HealthDataType type, Map results) {
    final list = results[type];
    if (list == null || list.isEmpty) return null;

    double total = 0;
    int count = 0;
    for (final dp in list) {
      final v = (dp.value as NumericHealthValue).numericValue.toDouble();
      if (v.isFinite && !v.isNaN) {
        total += v;
        count++;
      }
    }
    return count > 0 ? total / count : null;
  }

  int? _avgInt(HealthDataType type, Map results) {
    final avg = _avgNumeric(type, results);
    return avg?.round();
  }

  bool _hasData(HealthDataType type, Map results) {
    final list = results[type];
    return list != null && list.isNotEmpty;
  }

  int? _sumSleepMinutes(Map results) {
    final types = [
      HealthDataType.SLEEP_REM,
      HealthDataType.SLEEP_LIGHT,
      HealthDataType.SLEEP_DEEP,
      HealthDataType.SLEEP_AWAKE,
    ];

    int totalMinutes = 0;
    bool found = false;

    for (final type in types) {
      final list = results[type];
      if (list == null || list.isEmpty) continue;

      for (final dp in list) {
        final dur = (dp as HealthDataPoint).dateTo.difference(dp.dateFrom);
        totalMinutes += dur.inMinutes;
        found = true;
      }
    }
    return found ? totalMinutes : null;
  }

  int? _daysSinceLastMenstruation(Map results) {
    final list = results[HealthDataType.MENSTRUATION_FLOW];
    if (list == null || list.isEmpty) return null;

    final sorted = list.toList()
      ..sort((a, b) => b.dateFrom.compareTo(a.dateFrom));
    final latest = sorted.first;
    return DateTime.now().difference(latest.dateFrom).inDays;
  }

  // ── Numeric value extraction ─────────────────────────────────────────────

  List<double> _numericValues(HealthDataType type, dynamic data) {
    final list = data.whereType<HealthDataPoint>().toList();
    final values = <double>[];
    for (final dp in list) {
      final v = (dp.value as NumericHealthValue).numericValue.toDouble();
      if (v.isFinite && !v.isNaN) values.add(v);
    }
    return values;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  List<HealthDataType> _typesForSync(Set<HealthSyncType> syncTypes) {
    final types = <HealthDataType>{};
    for (final s in syncTypes) {
      final hTypes = _typeMap[s];
      if (hTypes != null) types.addAll(hTypes);
    }
    return types.toList();
  }

  double _median(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = List<double>.of(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }

  double _stdDev(List<double> values, double mean) {
    if (values.isEmpty) return 0;
    var sumSq = 0.0;
    for (final v in values) {
      final d = v - mean;
      sumSq += d * d;
    }
    return sqrt(sumSq / values.length);
  }
}

class _SleepStageEntry {
  final HealthDataType type;
  final DateTime from;
  final DateTime to;
  final double value;

  const _SleepStageEntry({
    required this.type,
    required this.from,
    required this.to,
    required this.value,
  });
}
