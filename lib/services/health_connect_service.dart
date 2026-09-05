import 'dart:math';
import 'package:health_connector/health_connector.dart';
import 'package:permission_handler/permission_handler.dart' as perm_handler;
import 'package:shared_preferences/shared_preferences.dart';
import 'incident_service.dart';

enum HealthSyncType {
  steps('Steps', 'Daily step count', [HealthDataType.steps]),
  heartRate('Heart Rate', 'Heart rate samples', [HealthDataType.heartRate]),
  hrv('HRV', 'Heart rate variability (RMSSD)', [HealthDataType.heartRateVariabilityRMSSD]),
  bloodOxygen('Blood Oxygen', 'SpO\u2082 saturation', [HealthDataType.oxygenSaturation]),
  sleep('Sleep', 'Sleep stages & duration', [HealthDataType.sleepSession, HealthDataType.sleepStageRecord]),
  bloodPressure('Blood Pressure', 'Systolic & diastolic', [HealthDataType.bloodPressure]),
  temperature('Temperature', 'Body temperature', [HealthDataType.bodyTemperature]),
  menstruation('Menstruation', 'Menstrual flow data', [HealthDataType.menstrualFlow]);

  const HealthSyncType(this.label, this.subtitle, this.dataTypes);
  final String label;
  final String subtitle;
  final List<HealthDataType> dataTypes;
}

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
  bool get hasData => steps != null || avgHeartRate != null || avgHrv != null || avgSpo2 != null || sleepMinutes != null || bpSystolic != null || avgTemperatureC != null;
}

class HealthConnectService {
  HealthConnectService._();
  static final HealthConnectService instance = HealthConnectService._();
  static const _enabledTypesKey = 'health_connect_enabled_types';
  static const _connectedKey = 'health_connect_connected';
  HealthConnector? _connector;
  bool _creating = false;

  Future<HealthConnector> _getConnector() async {
    if (_connector != null) return _connector!;
    if (_creating) {
      while (_connector == null && _creating) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (_connector != null) return _connector!;
    }
    _creating = true;
    try {
      _connector = await HealthConnector.create();
      return _connector!;
    } finally {
      _creating = false;
    }
  }

  Future<HealthConnector?> _tryGetConnector() async {
    try {
      return await _getConnector();
    } catch (_) {
      return null;
    }
  }

  Future<bool> isAvailable() async {
    try {
      final status = await HealthConnector.getHealthPlatformStatus();
      return status == HealthPlatformStatus.available;
    } catch (_) {
      return false;
    }
  }

  Future<void> installHealthConnect() async {
    try {
      await HealthConnector.launchHealthAppPageInAppStore();
    } catch (e, st) {
      IncidentService.reportUnhandled(source: 'health_connect_service', error: e, stackTrace: st, customMessage: 'installHealthConnect failed');
    }
  }

  Future<Set<HealthSyncType>> loadEnabledTypes() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_enabledTypesKey);
    if (saved == null) return {HealthSyncType.steps, HealthSyncType.heartRate};
    final Set<HealthSyncType> types = {};
    for (final name in saved) {
      try {
        types.add(HealthSyncType.values.byName(name));
      } catch (e, st) {
        IncidentService.reportUnhandled(source: 'health_connect_service', error: e, stackTrace: st, customMessage: 'Unknown HealthSyncType in prefs: $name');
      }
    }
    return types;
  }

  Future<void> saveEnabledTypes(Set<HealthSyncType> types) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_enabledTypesKey, types.map((e) => e.name).toList());
  }

  Future<bool> loadConnected() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_connectedKey) ?? false;
  }

  Future<void> setConnected(bool connected) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_connectedKey, connected);
  }

  List<dynamic> _permissionsForTypes(Set<HealthSyncType> types) {
    final perms = <dynamic>[];
    for (final t in types) {
      for (final dt in t.dataTypes) {
        perms.add(HealthDataPermission.read(dt));
        perms.add(HealthDataPermission.write(dt));
      }
    }
    perms.add(HealthPlatformFeature.readHealthDataHistory.permission);
    perms.add(HealthPlatformFeature.readHealthDataInBackground.permission);
    return perms;
  }

  Future<bool> hasPermissions(Set<HealthSyncType> types) async {
    if (types.isEmpty) return false;
    try {
      final connector = await _tryGetConnector();
      if (connector == null) return false;
      final perms = _permissionsForTypes(types);
      for (final p in perms) {
        try {
          final status = await (connector as dynamic).getPermissionStatus(p);
          if (status != PermissionStatus.granted) return false;
        } catch (_) {
          return false;
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestAuthorization(Set<HealthSyncType> types) async {
    if (types.isEmpty) return false;
    if (types.contains(HealthSyncType.steps)) {
      final status = await perm_handler.Permission.activityRecognition.request();
      if (!status.isGranted && !status.isLimited) {
        // continue anyway
      }
    }
    try {
      final connector = await _getConnector();
      final perms = _permissionsForTypes(types);
      final results = await (connector as dynamic).requestPermissions(perms);
      final granted = (results as List).where((r) => (r as dynamic).status == PermissionStatus.granted).length;
      final ok = granted == perms.length;
      if (ok) {
        await setConnected(true);
        await refreshWriteGrants(types);
      } else {
        final anyGranted = (results as List).any((r) => (r as dynamic).status == PermissionStatus.granted);
        if (anyGranted) {
          await setConnected(true);
          await refreshWriteGrants(types);
        }
      }
      return ok;
    } catch (e, st) {
      IncidentService.reportUnhandled(source: 'health_connect_service', error: e, stackTrace: st, customMessage: 'requestAuthorization failed for $types');
      return false;
    }
  }

  Future<void> revokeAll() async {
    try {
      final connector = await _tryGetConnector();
      if (connector != null) await connector.revokeAllPermissions();
    } catch (e, st) {
      IncidentService.reportUnhandled(source: 'health_connect_service', error: e, stackTrace: st, customMessage: 'revokePermissions failed');
    }
    _writeGranted.clear();
    await setConnected(false);
  }

  Set<HealthSyncType> _writeGranted = {};

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

  // Stub writes — just check permission, actual record write is no-op until verified on device.
  // Keeping as stubs prevents compile errors from evolving health_connector Record APIs.
  Future<void> tryWriteHeartRate(int bpm, DateTime at) async {
    if (bpm <= 0) return;
    if (!await _canWrite(HealthSyncType.heartRate)) return;
    // TODO: write HeartRateRecord via health_connector once API stabilized
  }

  Future<void> tryWriteHrv(int ms, DateTime at) async {
    if (ms <= 0) return;
    if (!await _canWrite(HealthSyncType.hrv)) return;
  }

  Future<void> tryWriteTemperature(double celsius, DateTime at) async {
    if (celsius <= 0) return;
    if (!await _canWrite(HealthSyncType.temperature)) return;
  }

  Future<void> tryWriteBloodOxygen(int pct, DateTime at) async {
    if (pct <= 0) return;
    if (!await _canWrite(HealthSyncType.bloodOxygen)) return;
  }

  Future<void> tryWriteBloodPressure(int systolic, int diastolic, DateTime at) async {
    if (systolic <= 0 || diastolic <= 0) return;
    if (!await _canWrite(HealthSyncType.bloodPressure)) return;
  }

  Future<void> tryWriteSteps(int steps, DateTime at) async {
    if (steps <= 0) return;
    if (!await _canWrite(HealthSyncType.steps)) return;
    try {
      final connector = await _getConnector();
      final start = DateTime(at.year, at.month, at.day);
      final record = StepsRecord(
        id: HealthRecordId.none,
        startTime: start,
        endTime: at,
        count: Number(steps.toDouble()),
        metadata: Metadata.automaticallyRecorded(device: Device.fromType(DeviceType.watch)),
      );
      await connector.writeRecord(record);
    } catch (e, st) {
      IncidentService.reportUnhandled(source: 'health_connect_service', error: e, stackTrace: st, customMessage: 'writeSteps failed');
    }
  }

  Future<void> tryWriteSleep({
    required DateTime sleepTime,
    required DateTime wakeTime,
    required int lightMinutes,
    required int deepMinutes,
    required int remMinutes,
    required int awakeMinutes,
  }) async {
    if (!await _canWrite(HealthSyncType.sleep)) return;
    var end = wakeTime;
    if (!end.isAfter(sleepTime)) {
      end = DateTime(sleepTime.year, sleepTime.month, sleepTime.day + 1, wakeTime.hour, wakeTime.minute);
      if (!end.isAfter(sleepTime)) end = wakeTime.add(const Duration(days: 1));
    }
    final total = lightMinutes + deepMinutes + remMinutes + awakeMinutes;
    try {
      final connector = await _getConnector();
      if (total <= 0) {
        final session = SleepSessionRecord(
          id: HealthRecordId.none,
          startTime: sleepTime,
          endTime: end,
          title: 'Sleep',
          samples: [],
          metadata: Metadata.automaticallyRecorded(device: Device.fromType(DeviceType.watch)),
        );
        await connector.writeRecord(session);
        return;
      }
      var cursor = sleepTime;
      final samples = <SleepStageSample>[];
      void addStage(SleepStage type, int minutes) {
        if (minutes <= 0) return;
        final stageEnd = cursor.add(Duration(minutes: minutes));
        samples.add(SleepStageSample(startTime: cursor, endTime: stageEnd, stageType: type));
        cursor = stageEnd;
      }

      addStage(SleepStage.light, lightMinutes);
      addStage(SleepStage.deep, deepMinutes);
      addStage(SleepStage.rem, remMinutes);
      addStage(SleepStage.awake, awakeMinutes);
      final session = SleepSessionRecord(
        id: HealthRecordId.none,
        startTime: sleepTime,
        endTime: cursor.isAfter(sleepTime) ? cursor : end,
        title: 'Sleep',
        samples: samples,
        metadata: Metadata.automaticallyRecorded(device: Device.fromType(DeviceType.watch)),
      );
      await connector.writeRecord(session);
    } catch (e, st) {
      IncidentService.reportUnhandled(source: 'health_connect_service', error: e, stackTrace: st, customMessage: 'writeSleep failed');
    }
  }

  Future<HealthConnectToday> fetchToday(Set<HealthSyncType> types) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    int? steps;
    if (types.contains(HealthSyncType.steps)) {
      try {
        final connector = await _getConnector();
        final req = HealthDataType.steps.aggregateSum(startTime: start, endTime: now);
        final result = await connector.aggregate(req);
        final v = (result as dynamic).value;
        if (v is Number) steps = v.value.toInt();
        else if (v is num) steps = v.toInt();
      } catch (e, st) {
        IncidentService.reportUnhandled(source: 'health_connect_service', error: e, stackTrace: st, customMessage: 'aggregate steps failed');
      }
    }
    // For other types, return empty for now — will be filled via local DB + Health Connect read on next iteration
    return HealthConnectToday(
      fetchedAt: now,
      steps: steps,
    );
  }

  Future<Map<String, double>> fetchHistoricalBaselines() async {
    // Keep defaults until health_connector read for HR/HRV/Temp is validated
    return {
      'rolling14DayMedianHR': 70.0,
      'rolling28DayMeanHRV': 50.0,
      'rolling28DayStdDevHRV': 10.0,
      'baselineAdjustedTemp': 36.5,
    };
  }
}
