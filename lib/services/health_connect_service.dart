import 'dart:math';
import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A syncable metric group backed by Google Health Connect.
///
/// Each group maps to the native Health Connect permission(s) requested for it.
enum HealthSyncType {
  steps(
    'Steps',
    'Daily step count',
    [HealthDataType.STEPS],
  ),
  heartRate(
    'Heart Rate',
    'Heart rate samples',
    [HealthDataType.HEART_RATE],
  ),
  hrv(
    'HRV',
    'Heart rate variability (RMSSD)',
    [HealthDataType.HEART_RATE_VARIABILITY_RMSSD],
  ),
  bloodOxygen(
    'Blood Oxygen',
    'SpO\u2082 saturation',
    [HealthDataType.BLOOD_OXYGEN],
  ),
  sleep(
    'Sleep',
    'Sleep stages & duration',
    [
      HealthDataType.SLEEP_ASLEEP,
      HealthDataType.SLEEP_DEEP,
      HealthDataType.SLEEP_LIGHT,
      HealthDataType.SLEEP_REM,
      HealthDataType.SLEEP_AWAKE,
      HealthDataType.SLEEP_IN_BED,
    ],
  ),
  bloodPressure(
    'Blood Pressure',
    'Systolic & diastolic',
    [
      HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
      HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
    ],
  ),
  temperature(
    'Temperature',
    'Body temperature',
    [HealthDataType.BODY_TEMPERATURE],
  ),
  menstruation(
    'Menstruation',
    'Menstrual flow data',
    [HealthDataType.MENSTRUATION_FLOW],
  );

  const HealthSyncType(this.label, this.subtitle, this.dataTypes);

  final String label;
  final String subtitle;
  final List<HealthDataType> dataTypes;
}

/// Aggregated "today" readings pulled from Health Connect.
class HealthConnectToday {
  final DateTime fetchedAt;
  final int? steps;
  final double? avgHeartRate;
  final double? avgHrv;
  final double? avgSpo2;
  final int? sleepMinutes;
  final int? deepMinutes;
  final int? lightMinutes;
  final int? remMinutes;
  final int? awakeMinutes;
  final int? bpSystolic;
  final int? bpDiastolic;
  final double? avgTemperatureC;
  final int? daysSinceLastPeriod;
  final bool hasMenstruationData;

  const HealthConnectToday({
    required this.fetchedAt,
    this.steps,
    this.avgHeartRate,
    this.avgHrv,
    this.avgSpo2,
    this.sleepMinutes,
    this.deepMinutes,
    this.lightMinutes,
    this.remMinutes,
    this.awakeMinutes,
    this.bpSystolic,
    this.bpDiastolic,
    this.avgTemperatureC,
    this.daysSinceLastPeriod,
    this.hasMenstruationData = false,
  });

  bool get hasData =>
      steps != null ||
      avgHeartRate != null ||
      avgHrv != null ||
      avgSpo2 != null ||
      sleepMinutes != null ||
      bpSystolic != null ||
      avgTemperatureC != null;
}

/// Thin wrapper around the `health` plugin scoped to what this app needs:
/// availability checks, per-metric authorization, and reading today's data.
///
/// Singleton — mirrors BleProvider's usage pattern elsewhere in the app.
class HealthConnectService {
  HealthConnectService._();
  static final HealthConnectService instance = HealthConnectService._();

  static const _enabledTypesKey = 'health_connect_enabled_types';
  static const _connectedKey = 'health_connect_connected';

  final Health _health = Health();
  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (!_configured) {
      await _health.configure();
      _configured = true;
    }
  }

  /// Whether Google Health Connect is installed and usable on this device.
  Future<bool> isAvailable() async {
    await _ensureConfigured();
    try {
      return await _health.isHealthConnectAvailable();
    } catch (_) {
      return false;
    }
  }

  /// Opens the Play Store page for the Health Connect app (Android only).
  Future<void> installHealthConnect() async {
    await _ensureConfigured();
    await _health.installHealthConnect();
  }

  /// Persisted set of metric groups the user wants to sync.
  Future<Set<HealthSyncType>> loadEnabledTypes() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_enabledTypesKey);
    if (saved == null) return {HealthSyncType.steps, HealthSyncType.heartRate};
    final Set<HealthSyncType> types = {};
    for (final name in saved) {
      try {
        types.add(HealthSyncType.values.byName(name));
      } catch (_) {}
    }
    return types;
  }

  Future<void> saveEnabledTypes(Set<HealthSyncType> types) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _enabledTypesKey,
      types.map((e) => e.name).toList(),
    );
  }

  Future<bool> loadConnected() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_connectedKey) ?? false;
  }

  Future<void> setConnected(bool connected) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_connectedKey, connected);
  }

  /// True when Health Connect has granted every [HealthSyncType] in [types]
  /// READ_WRITE access (both reading and writing the data).
  Future<bool> hasPermissions(Set<HealthSyncType> types) async {
    if (types.isEmpty) return false;
    await _ensureConfigured();
    final all = types.expand((t) => t.dataTypes).toList();
    try {
      final granted = await _health.hasPermissions(
        all,
        permissions: List.filled(all.length, HealthDataAccess.READ_WRITE),
      );
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Requests READ_WRITE authorization for [types]. On Android this shows the
  /// Health Connect permission sheet (read + write for each metric).
  /// Returns true when everything was granted.
  Future<bool> requestAuthorization(Set<HealthSyncType> types) async {
    if (types.isEmpty) return false;
    await _ensureConfigured();

    // Step counts need the Activity Recognition runtime permission first.
    if (types.contains(HealthSyncType.steps)) {
      final status = await Permission.activityRecognition.request();
      if (!status.isGranted && !status.isLimited) {
        // Continue anyway — Health Connect may still report manual steps.
      }
    }

    final all = types.expand((t) => t.dataTypes).toList();
    try {
      final granted = await _health.requestAuthorization(
        all,
        permissions: List.filled(all.length, HealthDataAccess.READ_WRITE),
      );
      if (granted) {
        await setConnected(true);
        await refreshWriteGrants(types);
        // Best-effort: unlock data older than the default 30-day window.
        try {
          if (await _health.isHealthDataHistoryAvailable()) {
            await _health.requestHealthDataHistoryAuthorization();
          }
        } catch (_) {}
      }
      return granted;
    } catch (_) {
      return false;
    }
  }

  /// Revokes all Health Connect permissions and clears the connected flag.
  Future<void> revokeAll() async {
    await _ensureConfigured();
    try {
      await _health.revokePermissions();
    } catch (_) {}
    _writeGranted.clear();
    await setConnected(false);
  }

  // ── Two-way sync: writing ring measurements into Health Connect ──────────
  //
  // Every write is best-effort: it silently no-ops when the app is not
  // connected or the metric wasn't granted READ_WRITE, so callers can fire
  // these from measurement hot paths without error handling.
  //
  // `clientRecordId` is deterministic per reading, so re-pushing the same
  // reading (e.g. after a screen refresh) replaces it instead of duplicating.

  Set<HealthSyncType> _writeGranted = {};

  /// Re-checks which [types] currently have READ_WRITE and caches the result.
  /// Call after [requestAuthorization] and when the screen refreshes.
  Future<Set<HealthSyncType>> refreshWriteGrants(Set<HealthSyncType> types) async {
    final granted = <HealthSyncType>{};
    for (final type in types) {
      if (await hasPermissions({type})) granted.add(type);
    }
    _writeGranted = granted;
    return granted;
  }

  Future<bool> _canWrite(HealthSyncType type) async {
    if (_writeGranted.isNotEmpty) return _writeGranted.contains(type);
    final ok = await hasPermissions({type});
    if (ok) _writeGranted = {type};
    return ok;
  }

  Future<void> tryWriteHeartRate(int bpm, DateTime at) => _writeSample(
        type: HealthSyncType.heartRate,
        dataType: HealthDataType.HEART_RATE,
        value: bpm.toDouble(),
        at: at,
      );

  Future<void> tryWriteHrv(int ms, DateTime at) => _writeSample(
        type: HealthSyncType.hrv,
        dataType: HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
        value: ms.toDouble(),
        at: at,
      );

  Future<void> tryWriteTemperature(double celsius, DateTime at) => _writeSample(
        type: HealthSyncType.temperature,
        dataType: HealthDataType.BODY_TEMPERATURE,
        value: celsius,
        at: at,
      );

  Future<void> _writeSample({
    required HealthSyncType type,
    required HealthDataType dataType,
    required double value,
    required DateTime at,
  }) async {
    if (value <= 0) return;
    if (!await _canWrite(type)) return;
    try {
      await _health.writeHealthData(
        value: value,
        type: dataType,
        startTime: at,
        endTime: at,
        clientRecordId: 'sundr-${dataType.name}-${at.millisecondsSinceEpoch}',
        recordingMethod: RecordingMethod.automatic,
      );
    } catch (_) {}
  }

  Future<void> tryWriteBloodOxygen(int pct, DateTime at) async {
    if (pct <= 0) return;
    if (!await _canWrite(HealthSyncType.bloodOxygen)) return;
    try {
      await _health.writeBloodOxygen(
        saturation: pct.toDouble(),
        startTime: at,
        endTime: at,
        recordingMethod: RecordingMethod.automatic,
      );
    } catch (_) {}
  }

  Future<void> tryWriteBloodPressure(
    int systolic,
    int diastolic,
    DateTime at,
  ) async {
    if (systolic <= 0 || diastolic <= 0) return;
    if (!await _canWrite(HealthSyncType.bloodPressure)) return;
    try {
      await _health.writeBloodPressure(
        systolic: systolic,
        diastolic: diastolic,
        startTime: at,
        endTime: at,
        clientRecordId: 'sundr-BP-${at.millisecondsSinceEpoch}',
        recordingMethod: RecordingMethod.automatic,
      );
    } catch (_) {}
  }

  /// Writes today's cumulative step count (midnight → [at]) so it replaces any
  /// previous push for the same day instead of accumulating.
  Future<void> tryWriteSteps(int steps, DateTime at) async {
    if (steps <= 0) return;
    if (!await _canWrite(HealthSyncType.steps)) return;
    final start = DateTime(at.year, at.month, at.day);
    try {
      await _health.writeHealthData(
        value: steps.toDouble(),
        type: HealthDataType.STEPS,
        startTime: start,
        endTime: at,
        clientRecordId: 'sundr-STEPS-${start.millisecondsSinceEpoch}',
        recordingMethod: RecordingMethod.automatic,
      );
    } catch (_) {}
  }

  /// Writes a night of sleep as stage segments (light → deep → rem → awake)
  /// laid out contiguously from [sleepTime]. Durations are in minutes.
  /// Keyed to the night, so re-syncing the same night replaces the session.
  Future<void> tryWriteSleep({
    required DateTime sleepTime,
    required DateTime wakeTime,
    required int lightMinutes,
    required int deepMinutes,
    required int remMinutes,
    required int awakeMinutes,
  }) async {
    if (!await _canWrite(HealthSyncType.sleep)) return;
    final dayKey = sleepTime.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

    // Overnight sessions (wake < sleep, e.g. 23:00 → 07:00) end the next day.
    var end = wakeTime;
    if (!end.isAfter(sleepTime)) {
      end = DateTime(sleepTime.year, sleepTime.month, sleepTime.day + 1);
    }

    var cursor = sleepTime;
    var index = 0;

    Future<void> writeStage(HealthDataType stage, int minutes) async {
      if (minutes <= 0) return;
      final stageEnd = cursor.add(Duration(minutes: minutes));
      try {
        await _health.writeHealthData(
          value: 0,
          type: stage,
          startTime: cursor,
          endTime: stageEnd,
          clientRecordId: 'sundr-sleep-$dayKey-${index++}',
          recordingMethod: RecordingMethod.automatic,
        );
      } catch (_) {}
      cursor = stageEnd;
    }

    await writeStage(HealthDataType.SLEEP_LIGHT, lightMinutes);
    await writeStage(HealthDataType.SLEEP_DEEP, deepMinutes);
    await writeStage(HealthDataType.SLEEP_REM, remMinutes);
    await writeStage(HealthDataType.SLEEP_AWAKE, awakeMinutes);

    // If no stage breakdown is available, fall back to one ASLEEP session.
    if (lightMinutes + deepMinutes + remMinutes + awakeMinutes <= 0) {
      try {
        await _health.writeHealthData(
          value: 0,
          type: HealthDataType.SLEEP_ASLEEP,
          startTime: sleepTime,
          endTime: end,
          clientRecordId: 'sundr-sleep-$dayKey-asleep',
          recordingMethod: RecordingMethod.automatic,
        );
      } catch (_) {}
    }
  }

  /// Fetches today's aggregated data for the given [types].
  Future<HealthConnectToday> fetchToday(Set<HealthSyncType> types) async {
    await _ensureConfigured();

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);

    final allTypes = types.expand((t) => t.dataTypes).toList();

    int? steps;
    if (types.contains(HealthSyncType.steps)) {
      try {
        steps = await _health.getTotalStepsInInterval(start, now);
      } catch (_) {}
    }

    final List<HealthDataPoint> points;
    try {
      points = await _health.getHealthDataFromTypes(
        types: allTypes,
        startTime: start,
        endTime: now,
      );
    } catch (_) {
      return HealthConnectToday(
        fetchedAt: now,
        steps: steps,
        avgHeartRate: _average(pointsByType(const [], HealthDataType.HEART_RATE)),
        avgHrv: _average(pointsByType(const [], HealthDataType.HEART_RATE_VARIABILITY_RMSSD)),
        avgSpo2: _average(pointsByType(const [], HealthDataType.BLOOD_OXYGEN)),
        avgTemperatureC: _average(pointsByType(const [], HealthDataType.BODY_TEMPERATURE)),
      );
    }

    final byType = <HealthDataType, List<HealthDataPoint>>{};
    for (final p in points) {
      byType.putIfAbsent(p.type, () => []).add(p);
    }

    List<HealthDataPoint> ptsOf(HealthDataType t) => byType[t] ?? const [];

    double? avgOf(HealthDataType t) => _average(ptsOf(t));

    // Blood pressure: use the most recent systolic + diastolic pair.
    int? bpSystolic;
    int? bpDiastolic;
    final sys = ptsOf(HealthDataType.BLOOD_PRESSURE_SYSTOLIC);
    final dia = ptsOf(HealthDataType.BLOOD_PRESSURE_DIASTOLIC);
    if (sys.isNotEmpty) {
      sys.sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
      bpSystolic = _numValue(sys.last)?.round().toInt();
    }
    if (dia.isNotEmpty) {
      dia.sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
      bpDiastolic = _numValue(dia.last)?.round().toInt();
    }

    // Sleep stages arrive in minutes per sample; sum them.
    int sumMinutes(HealthDataType t) =>
        ptsOf(t).fold(0, (sum, p) => sum + (_numValue(p)?.round().toInt() ?? 0));

    int? daysSinceLastPeriod;
    bool hasMenstruationData = false;
    if (types.contains(HealthSyncType.menstruation)) {
      try {
        final startMenstruation = now.subtract(const Duration(days: 45));
        final mPoints = await _health.getHealthDataFromTypes(
          types: [HealthDataType.MENSTRUATION_FLOW],
          startTime: startMenstruation,
          endTime: now,
        );
        if (mPoints.isNotEmpty) {
          hasMenstruationData = true;
          mPoints.sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
          final lastPeriod = mPoints.last.dateFrom;
          daysSinceLastPeriod = now.difference(lastPeriod).inDays;
        }
      } catch (_) {}
    }

    return HealthConnectToday(
      fetchedAt: DateTime.now(),
      steps: steps,
      avgHeartRate: avgOf(HealthDataType.HEART_RATE),
      avgHrv: avgOf(HealthDataType.HEART_RATE_VARIABILITY_RMSSD),
      avgSpo2: avgOf(HealthDataType.BLOOD_OXYGEN),
      sleepMinutes: sumMinutes(HealthDataType.SLEEP_ASLEEP) != 0
          ? sumMinutes(HealthDataType.SLEEP_ASLEEP)
          : null,
      deepMinutes: sumMinutes(HealthDataType.SLEEP_DEEP),
      lightMinutes: sumMinutes(HealthDataType.SLEEP_LIGHT),
      remMinutes: sumMinutes(HealthDataType.SLEEP_REM),
      awakeMinutes: sumMinutes(HealthDataType.SLEEP_AWAKE),
      bpSystolic: bpSystolic,
      bpDiastolic: bpDiastolic,
      avgTemperatureC: avgOf(HealthDataType.BODY_TEMPERATURE),
      daysSinceLastPeriod: daysSinceLastPeriod,
      hasMenstruationData: hasMenstruationData,
    );
  }

  /// Fetches historical baselines for Layer 1 Fall Risk Engine
  Future<Map<String, double>> fetchHistoricalBaselines() async {
    await _ensureConfigured();
    final now = DateTime.now();
    
    // Default values if data isn't available
    double medianHR = 70.0;
    double meanHRV = 50.0;
    double stdDevHRV = 10.0;
    double baselineTemp = 36.5;

    try {
      final start14 = now.subtract(const Duration(days: 14));
      final hrPoints = await _health.getHealthDataFromTypes(
        types: [HealthDataType.HEART_RATE],
        startTime: start14,
        endTime: now,
      );
      if (hrPoints.isNotEmpty) {
        final hrValues = hrPoints.map(_numValue).whereType<double>().toList();
        if (hrValues.isNotEmpty) {
          hrValues.sort();
          medianHR = hrValues[hrValues.length ~/ 2];
        }
      }

      final start28 = now.subtract(const Duration(days: 28));
      final hrvPoints = await _health.getHealthDataFromTypes(
        types: [HealthDataType.HEART_RATE_VARIABILITY_RMSSD],
        startTime: start28,
        endTime: now,
      );
      if (hrvPoints.isNotEmpty) {
        final hrvValues = hrvPoints.map(_numValue).whereType<double>().toList();
        if (hrvValues.isNotEmpty) {
          final sum = hrvValues.reduce((a, b) => a + b);
          meanHRV = sum / hrvValues.length;
          
          if (hrvValues.length > 1) {
            double sumSqDiffs = 0.0;
            for (final v in hrvValues) {
              sumSqDiffs += (v - meanHRV) * (v - meanHRV);
            }
            stdDevHRV = sqrt(sumSqDiffs / (hrvValues.length - 1));
          }
        }
      }

      final tempPoints = await _health.getHealthDataFromTypes(
        types: [HealthDataType.BODY_TEMPERATURE],
        startTime: start14,
        endTime: now,
      );
      if (tempPoints.isNotEmpty) {
        final tempValues = tempPoints.map(_numValue).whereType<double>().toList();
        if (tempValues.isNotEmpty) {
          baselineTemp = tempValues.reduce((a, b) => a + b) / tempValues.length;
        }
      }
    } catch (_) {}

    return {
      'rolling14DayMedianHR': medianHR,
      'rolling28DayMeanHRV': meanHRV,
      'rolling28DayStdDevHRV': stdDevHRV,
      'baselineAdjustedTemp': baselineTemp,
    };
  }

  static double? _numValue(HealthDataPoint p) {
    final v = p.value;
    if (v is NumericHealthValue) return v.numericValue.toDouble();
    return null;
  }

  static double? _average(List<HealthDataPoint> points) {
    if (points.isEmpty) return null;
    var sum = 0.0;
    var count = 0;
    for (final p in points) {
      final v = _numValue(p);
      if (v != null) {
        sum += v;
        count++;
      }
    }
    return count == 0 ? null : sum / count;
  }

  // Reused by the error path above without allocating per-call.
  static List<HealthDataPoint> pointsByType(
    List<HealthDataPoint> points,
    HealthDataType type,
  ) =>
      points.where((p) => p.type == type).toList();
}
