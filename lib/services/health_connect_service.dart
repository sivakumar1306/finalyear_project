import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

enum HealthSyncType {
  steps('Steps', 'Daily step count and activity'),
  heartRate('Heart Rate', 'Pulse & heart rate telemetry'),
  hrv('HRV', 'Heart rate variability metrics'),
  bloodOxygen('Blood Oxygen', 'SpO2 oxygen saturation'),
  sleep('Sleep', 'Sleep sessions & duration'),
  bloodPressure('Blood Pressure', 'Systolic & diastolic readings'),
  temperature('Body Temperature', 'Skin/body temperature readings');

  final String label;
  final String subtitle;

  const HealthSyncType(this.label, this.subtitle);
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

  const HealthConnectToday({
    this.steps,
    this.avgHeartRate,
    this.avgHrv,
    this.avgSpo2,
    this.sleepMinutes,
    this.bpSystolic,
    this.bpDiastolic,
    this.avgTemperatureC,
  });
}

class HealthConnectService {
  HealthConnectService._() {
    _health.configure();
  }

  static final HealthConnectService instance = HealthConnectService._();
  final Health _health = Health();

  static const String _keyEnabledTypes = 'health_connect_enabled_types';
  static const String _keyConnected = 'health_connect_connected';

  List<HealthDataType> _mapSyncTypeToHealthDataTypes(HealthSyncType type) {
    switch (type) {
      case HealthSyncType.steps:
        return [HealthDataType.STEPS];
      case HealthSyncType.heartRate:
        return [HealthDataType.HEART_RATE];
      case HealthSyncType.hrv:
        return [
          HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
        ];
      case HealthSyncType.bloodOxygen:
        return [HealthDataType.BLOOD_OXYGEN];
      case HealthSyncType.sleep:
        return [
          HealthDataType.SLEEP_ASLEEP,
          HealthDataType.SLEEP_IN_BED,
          HealthDataType.SLEEP_SESSION,
        ];
      case HealthSyncType.bloodPressure:
        return [
          HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
          HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
        ];
      case HealthSyncType.temperature:
        return [HealthDataType.BODY_TEMPERATURE];
    }
  }

  List<HealthDataType> _mapSyncTypesToHealthDataTypes(
    Set<HealthSyncType> types,
  ) {
    final list = <HealthDataType>[];
    for (final t in types) {
      list.addAll(_mapSyncTypeToHealthDataTypes(t));
    }
    return list.toSet().toList();
  }

  Future<bool> isAvailable() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final status = await _health.getHealthConnectSdkStatus();
        return status == HealthConnectSdkStatus.sdkAvailable;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> installHealthConnect() async {
    try {
      await _health.installHealthConnect();
    } catch (_) {
      final url = Uri.parse(
        'market://details?id=com.google.android.apps.healthdata',
      );
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        final webUrl = Uri.parse(
          'https://play.google.com/store/apps/details?id=com.google.android.apps.healthdata',
        );
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    }
  }

  Future<Set<HealthSyncType>> loadEnabledTypes() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyEnabledTypes);
    if (list == null) {
      return HealthSyncType.values.toSet();
    }
    final result = <HealthSyncType>{};
    for (final name in list) {
      for (final type in HealthSyncType.values) {
        if (type.name == name) {
          result.add(type);
        }
      }
    }
    return result;
  }

  Future<void> saveEnabledTypes(Set<HealthSyncType> types) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _keyEnabledTypes,
      types.map((e) => e.name).toList(),
    );
  }

  Future<bool> loadConnected() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyConnected) ?? false;
  }

  Future<void> _saveConnected(bool connected) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyConnected, connected);
  }

  Future<bool> hasPermissions(Set<HealthSyncType> types) async {
    try {
      final healthTypes = _mapSyncTypesToHealthDataTypes(types);
      if (healthTypes.isEmpty) return false;
      final permissions = healthTypes
          .map((_) => HealthDataAccess.READ)
          .toList();
      final has = await _health.hasPermissions(
        healthTypes,
        permissions: permissions,
      );
      return has ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestAuthorization(Set<HealthSyncType> types) async {
    try {
      final healthTypes = _mapSyncTypesToHealthDataTypes(types);
      if (healthTypes.isEmpty) return false;
      final permissions = healthTypes
          .map((_) => HealthDataAccess.READ)
          .toList();
      final granted = await _health.requestAuthorization(
        healthTypes,
        permissions: permissions,
      );
      await _saveConnected(granted);
      return granted;
    } catch (_) {
      return false;
    }
  }

  Future<void> revokeAll() async {
    try {
      await _health.revokePermissions();
    } catch (_) {}
    await _saveConnected(false);
  }

  Future<HealthConnectToday?> fetchToday(Set<HealthSyncType> types) async {
    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      final healthTypes = _mapSyncTypesToHealthDataTypes(types);

      if (healthTypes.isEmpty) return null;

      final dataPoints = await _health.getHealthDataFromTypes(
        startTime: midnight,
        endTime: now,
        types: healthTypes,
      );

      int? steps;
      double? sumHr;
      int countHr = 0;
      double? sumHrv;
      int countHrv = 0;
      double? sumSpo2;
      int countSpo2 = 0;
      int totalSleepMinutes = 0;
      int? bpSystolic;
      int? bpDiastolic;
      double? sumTemp;
      int countTemp = 0;

      for (final p in dataPoints) {
        final val = p.value;
        switch (p.type) {
          case HealthDataType.STEPS:
            if (val is NumericHealthValue) {
              steps = (steps ?? 0) + val.numericValue.toInt();
            }
            break;
          case HealthDataType.HEART_RATE:
            if (val is NumericHealthValue) {
              sumHr = (sumHr ?? 0) + val.numericValue.toDouble();
              countHr++;
            }
            break;
          case HealthDataType.HEART_RATE_VARIABILITY_RMSSD:
            if (val is NumericHealthValue) {
              sumHrv = (sumHrv ?? 0) + val.numericValue.toDouble();
              countHrv++;
            }
            break;
          case HealthDataType.BLOOD_OXYGEN:
            if (val is NumericHealthValue) {
              sumSpo2 = (sumSpo2 ?? 0) + val.numericValue.toDouble();
              countSpo2++;
            }
            break;
          case HealthDataType.SLEEP_ASLEEP:
          case HealthDataType.SLEEP_IN_BED:
          case HealthDataType.SLEEP_SESSION:
            final dur = p.dateTo.difference(p.dateFrom).inMinutes;
            if (dur > 0) totalSleepMinutes += dur;
            break;
          case HealthDataType.BLOOD_PRESSURE_SYSTOLIC:
            if (val is NumericHealthValue) {
              bpSystolic = val.numericValue.toInt();
            }
            break;
          case HealthDataType.BLOOD_PRESSURE_DIASTOLIC:
            if (val is NumericHealthValue) {
              bpDiastolic = val.numericValue.toInt();
            }
            break;
          case HealthDataType.BODY_TEMPERATURE:
            if (val is NumericHealthValue) {
              sumTemp = (sumTemp ?? 0) + val.numericValue.toDouble();
              countTemp++;
            }
            break;
          default:
            break;
        }
      }

      return HealthConnectToday(
        steps: steps,
        avgHeartRate: countHr > 0 ? (sumHr! / countHr) : null,
        avgHrv: countHrv > 0 ? (sumHrv! / countHrv) : null,
        avgSpo2: countSpo2 > 0 ? (sumSpo2! / countSpo2) : null,
        sleepMinutes: totalSleepMinutes > 0 ? totalSleepMinutes : null,
        bpSystolic: bpSystolic,
        bpDiastolic: bpDiastolic,
        avgTemperatureC: countTemp > 0 ? (sumTemp! / countTemp) : null,
      );
    } catch (e) {
      debugPrint('Error fetching Health Connect data: $e');
      return null;
    }
  }
}
