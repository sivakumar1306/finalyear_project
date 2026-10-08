import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../config.dart';

class BleService {
  static const _methodChannel = MethodChannel(AppConfig.bleMethodChannel);
  static const _eventChannel = EventChannel(AppConfig.bleEventChannel);

  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  Stream<Map<String, dynamic>>? _eventStream;

  /// Logs [PlatformException]s for critical channels without changing call sites.
  Future<T?> _invoke<T>(String method, [dynamic arguments]) async {
    try {
      return await _methodChannel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      debugPrint(
        '[BleService] $method PlatformException: ${e.code} ${e.message}',
      );
      rethrow;
    } on MissingPluginException catch (e) {
      debugPrint('[BleService] $method MissingPluginException: $e');
      rethrow;
    }
  }

  Stream<Map<String, dynamic>> get events {
    _eventStream ??= _eventChannel.receiveBroadcastStream().map(
      (e) => Map<String, dynamic>.from(e as Map),
    );
    return _eventStream!;
  }

  // ── Scanning ──────────────────────────────────────────────────────
  Future<void> startScan({String filterName = ''}) =>
      _invoke('startScan', {'filterName': filterName});

  Future<void> stopScan() => _invoke('stopScan');

  // ── Connection ─────────────────────────────────────────────────────
  Future<bool> connect(String address) async {
    final result = await _invoke<dynamic>('connect', {'address': address});
    if (result is bool) return result;
    if (result is Map) {
      final ok = result['ok'] == true;
      final got = '${result['address'] ?? ''}'.trim();
      if (!ok) return false;
      // Success for a different device used to be reported as a connect to
      // whatever the user tapped. Refuse that so the saved identity stays honest.
      if (got.isNotEmpty && got.toUpperCase() != address.toUpperCase()) {
        return false;
      }
      return true;
    }
    return false;
  }

  Future<void> disconnect() => _invoke('disconnect');

  Future<bool> isConnected() async {
    final result = await _invoke<bool>('isConnected');
    return result ?? false;
  }

  /// Last native crash/SDK failure recorded before a process death (or soft fail).
  Future<Map<String, dynamic>?> getLastNativeCrash() async {
    try {
      final result = await _methodChannel.invokeMethod<dynamic>(
        'getLastNativeCrash',
      );
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return null;
    } catch (e) {
      debugPrint('[BleService] getLastNativeCrash: $e');
      return null;
    }
  }

  Future<void> clearLastNativeCrash() async {
    try {
      await _methodChannel.invokeMethod('clearLastNativeCrash');
    } catch (e) {
      debugPrint('[BleService] clearLastNativeCrash: $e');
    }
  }

  Future<void> softResetBleSdk() async {
    try {
      await _methodChannel.invokeMethod('softResetBleSdk');
    } catch (e) {
      debugPrint('[BleService] softResetBleSdk: $e');
    }
  }

  // ── Device Info ────────────────────────────────────────────────────
  Future<int> getBattery() async {
    final result = await _methodChannel.invokeMethod<int>('getBattery');
    return result ?? -1;
  }

  Future<bool> findDevice({bool enable = true}) async {
    final result = await _methodChannel.invokeMethod<bool>('findDevice', {
      'enable': enable,
    });
    return result ?? false;
  }

  Future<bool> saveStepsSnapshot({
    required int steps,
    required int calories,
    required double distanceM,
  }) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'saveStepsSnapshot',
      {'steps': steps, 'calories': calories, 'distanceM': distanceM},
    );
    return result ?? false;
  }

  Future<Map<String, dynamic>> getFirmwareVersion() async {
    final result = await _methodChannel.invokeMethod<Map>('getFirmwareVersion');
    return result != null ? Map<String, dynamic>.from(result) : {};
  }

  Future<bool> setTime() async {
    final result = await _methodChannel.invokeMethod<bool>('setTime');
    return result ?? false;
  }

  Future<String> getDeviceSupport() async {
    final result = await _methodChannel.invokeMethod<String>(
      'getDeviceSupport',
    );
    return result ?? '{}';
  }

  // ── Heart Rate ─────────────────────────────────────────────────────
  Future<String> getTodayHeartRate() async =>
      await _methodChannel.invokeMethod<String>('getTodayHeartRate') ?? '{}';

  Future<String> getHeartRate(int dayIndex) async =>
      await _methodChannel.invokeMethod<String>('getHeartRate', {
        'dayIndex': dayIndex,
      }) ??
      '{}';

  Future<String> getHeartRates(int startDay, int count) async =>
      await _methodChannel.invokeMethod<String>('getHeartRates', {
        'startDay': startDay,
        'count': count,
      }) ??
      '[]';

  Future<String> getHeartRateSetting() async =>
      await _methodChannel.invokeMethod<String>('getHeartRateSetting') ?? '{}';

  Future<bool> setHeartRateSetting({
    required bool enable,
    required int interval,
  }) async =>
      await _methodChannel.invokeMethod<bool>('setHeartRateSetting', {
        'enable': enable,
        'interval': interval,
      }) ??
      false;

  Future<String> manualModeHeart({required bool start}) async =>
      await _methodChannel.invokeMethod<String>('manualModeHeart', {
        'start': start,
      }) ??
      '{}';

  // Single-call measurement: starts, waits for a valid reading, auto-stops.
  // Returns the heart rate in bpm, or null if no reading received.
  Future<int?> readHeartRate() async =>
      _methodChannel.invokeMethod<int>('readHeartRate');

  /// Cancels an in-flight [readHeartRate]. Returns true when a session was
  /// active. The pending read completes with a CANCELLED error.
  Future<bool> cancelHeartRate() async =>
      await _methodChannel.invokeMethod<bool>('cancelHeartRate') ?? false;

  /// Ring-recorded manual heart-rate list (large-data, QRing parity).
  /// Fallback when live streaming yields nothing — returns raw JSON list
  /// of {index, data:[{m,v}]} entries.
  Future<String> syncManualHeartRate() async =>
      await _methodChannel.invokeMethod<String>('syncManualHeartRate') ?? '[]';

  Future<String> syncIntervalHeartRate() async =>
      await _methodChannel.invokeMethod<String>('syncIntervalHeartRate') ??
      '[]';

  // ── Blood Pressure ─────────────────────────────────────────────────
  Future<String> getTodayBloodPressure() async =>
      await _methodChannel.invokeMethod<String>('getTodayBloodPressure') ??
      '[]';

  Future<String> getBloodPressure(int dayIndex) async =>
      await _methodChannel.invokeMethod<String>('getBloodPressure', {
        'dayIndex': dayIndex,
      }) ??
      '[]';

  Future<String> getBloodPressures(int startDay, int count) async =>
      await _methodChannel.invokeMethod<String>('getBloodPressures', {
        'startDay': startDay,
        'count': count,
      }) ??
      '[]';

  Future<String> getBloodPressureSetting() async =>
      await _methodChannel.invokeMethod<String>('getBloodPressureSetting') ??
      '{}';

  Future<bool> setBloodPressureSetting({
    required bool enable,
    required int interval,
  }) async =>
      await _methodChannel.invokeMethod<bool>('setBloodPressureSetting', {
        'enable': enable,
        'interval': interval,
      }) ??
      false;

  Future<String> manualModeBP({required bool start}) async =>
      await _methodChannel.invokeMethod<String>('manualModeBP', {
        'start': start,
      }) ??
      '{}';

  // ── Blood Oxygen ───────────────────────────────────────────────────
  Future<String> getTodayBloodOxygen() async =>
      await _methodChannel.invokeMethod<String>('getTodayBloodOxygen') ?? '{}';

  Future<String> getBloodOxygen(int dayIndex) async =>
      await _methodChannel.invokeMethod<String>('getBloodOxygen', {
        'dayIndex': dayIndex,
      }) ??
      '{}';

  Future<String> getBloodOxygens(int startDay, int count) async =>
      await _methodChannel.invokeMethod<String>('getBloodOxygens', {
        'startDay': startDay,
        'count': count,
      }) ??
      '[]';

  Future<String> getBloodOxygenSetting() async =>
      await _methodChannel.invokeMethod<String>('getBloodOxygenSetting') ??
      '{}';

  Future<bool> setBloodOxygenSetting({
    required bool enable,
    required int interval,
  }) async =>
      await _methodChannel.invokeMethod<bool>('setBloodOxygenSetting', {
        'enable': enable,
        'interval': interval,
      }) ??
      false;

  Future<String> manualModeBloodOxygen({required bool start}) async =>
      await _methodChannel.invokeMethod<String>('manualModeBloodOxygen', {
        'start': start,
      }) ??
      '{}';

  Future<String> syncIntervalBloodOxygen() async =>
      await _methodChannel.invokeMethod<String>('syncIntervalBloodOxygen') ??
      '[]';

  // ── Steps ──────────────────────────────────────────────────────────
  // Dart-side timeouts (same rationale as Sleep): a hung native call
  // surfaces as TimeoutException instead of stalling the Activity page.
  Future<bool> syncTodaySteps() async =>
      await _methodChannel
          .invokeMethod<bool>('syncTodaySteps')
          .timeout(const Duration(seconds: 15)) ??
      false;

  Future<String> getTodaySteps() async =>
      await _methodChannel
          .invokeMethod<String>('getTodaySteps')
          .timeout(const Duration(seconds: 10)) ??
      '{}';

  Future<String> getSteps(int dayIndex) async =>
      await _methodChannel
          .invokeMethod<String>('getSteps', {
            'dayIndex': dayIndex,
          })
          .timeout(const Duration(seconds: 10)) ??
      '{}';

  Future<String> getStepsList(int startDay, int count) async =>
      await _methodChannel
          .invokeMethod<String>('getStepsList', {
            'startDay': startDay,
            'count': count,
          })
          .timeout(const Duration(seconds: 12)) ??
      '[]';

  Future<String> syncStepDetails() async =>
      await _methodChannel
          .invokeMethod<String>('syncStepDetails')
          .timeout(const Duration(seconds: 15)) ??
      '[]';

  // ── Sleep ──────────────────────────────────────────────────────────
  // 10s Dart-side timeouts: a hung native call surfaces as TimeoutException,
  // which callers treat as expected-offline (silent DB fallback, no incident).
  Future<String> getTodaySleep() async =>
      await _methodChannel
          .invokeMethod<String>('getTodaySleep')
          .timeout(const Duration(seconds: 10)) ??
      '{}';

  Future<String> getSleep(int dayIndex) async =>
      await _methodChannel
          .invokeMethod<String>('getSleep', {
            'dayIndex': dayIndex,
          })
          .timeout(const Duration(seconds: 10)) ??
      '{}';

  Future<String> getSleepList(int startDay, int count) async =>
      await _methodChannel
          .invokeMethod<String>('getSleepList', {
            'startDay': startDay,
            'count': count,
          })
          .timeout(const Duration(seconds: 12)) ??
      '[]';

  /// Large-data sleep sync. [dayIndex] 0 is last night. The native side waits
  /// for the real night inside the packet (up to ~18s) instead of returning
  /// the first empty callback.
  Future<String> syncSleep({int dayIndex = 0}) async =>
      await _methodChannel
          .invokeMethod<String>('syncSleep', {'dayIndex': dayIndex})
          .timeout(const Duration(seconds: 22)) ??
      '{}';

  Future<bool> saveLocalSleep({
    required String dateStr,
    required int totalDuration,
    required int deepDuration,
    required int lightDuration,
    required int remDuration,
    required int awakeDuration,
    required int sleepScore,
    int sleepTime = 0,
    int wakeTime = 0,
    int dayIndex = 0,
    String payloadJson = '{}',
    String source = 'ring',
  }) async {
    try {
      return await _methodChannel.invokeMethod<bool>('saveLocalSleep', {
            'dateStr': dateStr,
            'totalDuration': totalDuration,
            'deepDuration': deepDuration,
            'lightDuration': lightDuration,
            'remDuration': remDuration,
            'awakeDuration': awakeDuration,
            'sleepScore': sleepScore,
            'sleepTime': sleepTime,
            'wakeTime': wakeTime,
            'dayIndex': dayIndex,
            'payloadJson': payloadJson,
            'source': source,
          }) ??
          false;
    } catch (e) {
      debugPrint('saveLocalSleep: $e');
      return false;
    }
  }

  Future<String> getLocalSleep(String dateStr) async {
    try {
      return await _methodChannel.invokeMethod<String>('getLocalSleep', {
            'dateStr': dateStr,
          }) ??
          '{}';
    } catch (e) {
      debugPrint('getLocalSleep: $e');
      return '{}';
    }
  }

  Future<String> getLocalSleepHistory({
    required String from,
    required String to,
  }) async {
    try {
      return await _methodChannel.invokeMethod<String>('getLocalSleepHistory', {
            'from': from,
            'to': to,
          }) ??
          '[]';
    } catch (e) {
      debugPrint('getLocalSleepHistory: $e');
      return '[]';
    }
  }

  // ── HRV ────────────────────────────────────────────────────────────
  Future<String> getTodayHrv() async =>
      await _methodChannel.invokeMethod<String>('getTodayHrv') ?? '{}';

  Future<String> getHrv(int dayIndex) async =>
      await _methodChannel.invokeMethod<String>('getHrv', {
        'dayIndex': dayIndex,
      }) ??
      '{}';

  Future<String> getHrvList(int startDay, int count) async =>
      await _methodChannel.invokeMethod<String>('getHrvList', {
        'startDay': startDay,
        'count': count,
      }) ??
      '[]';

  Future<String> manualModeHrv({required bool start}) async =>
      await _methodChannel.invokeMethod<String>('manualModeHrv', {
        'start': start,
      }) ??
      '{}';

  Future<String> getHrvSetting() async =>
      await _methodChannel.invokeMethod<String>('getHrvSetting') ?? '{}';

  Future<bool> setHrvSetting({required bool enable}) async =>
      await _methodChannel.invokeMethod<bool>('setHrvSetting', {
        'enable': enable,
      }) ??
      false;

  // ── Pressure ───────────────────────────────────────────────────────
  Future<String> getTodayPressure() async =>
      await _methodChannel.invokeMethod<String>('getTodayPressure') ?? '{}';

  Future<String> getPressure(int dayIndex) async =>
      await _methodChannel.invokeMethod<String>('getPressure', {
        'dayIndex': dayIndex,
      }) ??
      '{}';

  Future<String> getPressureList(int startDay, int count) async =>
      await _methodChannel.invokeMethod<String>('getPressureList', {
        'startDay': startDay,
        'count': count,
      }) ??
      '[]';

  Future<String> getPressureSetting() async =>
      await _methodChannel.invokeMethod<String>('getPressureSetting') ?? '{}';

  Future<bool> setPressureSetting({required bool enable}) async =>
      await _methodChannel.invokeMethod<bool>('setPressureSetting', {
        'enable': enable,
      }) ??
      false;

  Future<String> manualModePressure({required bool start}) async =>
      await _methodChannel.invokeMethod<String>('manualModePressure', {
        'start': start,
      }) ??
      '{}';

  // ── Temperature ────────────────────────────────────────────────────
  Future<String> getTodayTemperature() async =>
      await _methodChannel.invokeMethod<String>('getTodayTemperature') ?? '{}';

  Future<String> getTemperature(int dayIndex) async =>
      await _methodChannel.invokeMethod<String>('getTemperature', {
        'dayIndex': dayIndex,
      }) ??
      '{}';

  Future<String> getTemperatureList(int startDay, int count) async =>
      await _methodChannel.invokeMethod<String>('getTemperatureList', {
        'startDay': startDay,
        'count': count,
      }) ??
      '[]';

  Future<String> getContinuousSugar() async {
    try {
      return await _methodChannel.invokeMethod<String>('getContinuousSugar') ?? '[]';
    } catch (_) {
      return '[]';
    }
  }

  Future<String> startEcgMeasure() async {
    try {
      return await _methodChannel.invokeMethod<String>('startEcgMeasure') ?? '{}';
    } catch (_) {
      return '{}';
    }
  }

  Future<String> getTemperatureSetting() async =>
      await _methodChannel.invokeMethod<String>('getTemperatureSetting') ??
      '{}';

  Future<bool> setTemperatureSetting({
    required bool enable,
    required int interval,
  }) async =>
      await _methodChannel.invokeMethod<bool>('setTemperatureSetting', {
        'enable': enable,
        'interval': interval,
      }) ??
      false;

  Future<String> syncAutoTemperature() async =>
      await _methodChannel.invokeMethod<String>('syncAutoTemperature') ?? '{}';

  Future<String> syncManualTemperature() async =>
      await _methodChannel
          .invokeMethod<String>('syncManualTemperature')
          .timeout(const Duration(seconds: 70)) ??
      '[]';

  /// POC: calls BleOperateManager.manualTemperature() to verify the ring
  /// actually supports command-based temperature measurement.
  Future<String> testManualTemperature() async =>
      await _methodChannel.invokeMethod<String>('testManualTemperature') ??
      '{}';

  // ── Sport Records ──────────────────────────────────────────────────
  Future<String> getSportRecords() async =>
      await _methodChannel.invokeMethod<String>('getSportRecords') ?? '[]';

  // Ring auto-detected sport sessions (SportPlusEntity). Same DayIndexedData
  // range shape as the other vitals: [{dayIndex|day_index, data:[...]}].
  Future<String> getTodaySport() async =>
      await _methodChannel
          .invokeMethod<String>('getTodaySport')
          .timeout(const Duration(seconds: 10)) ??
      '[]';

  Future<String> getSport(int dayIndex) async =>
      await _methodChannel
          .invokeMethod<String>('getSport', {'dayIndex': dayIndex})
          .timeout(const Duration(seconds: 10)) ??
      '[]';

  Future<String> getSports(int startDay, int count) async =>
      await _methodChannel
          .invokeMethod<String>('getSports', {
            'startDay': startDay,
            'count': count,
          })
          .timeout(const Duration(seconds: 15)) ??
      '[]';

  // ── Full ring history (dayIndex 0..6 buffer) ──────────────────────────
  // One dispatcher for the "view all history from the ring" path. Each vital
  // returns a JSON list of DayIndexedData ({dayIndex|day_index, data}).
  // See docs/mappings/history-coverage.md.
  static const int kRingHistoryMaxDays = 7;

  Future<String> fetchRingHistory(
    String vital, {
    int startDay = 0,
    int count = kRingHistoryMaxDays,
  }) {
    switch (vital) {
      case 'sleep':
        return getSleepList(startDay, count);
      case 'steps':
        return getStepsList(startDay, count);
      case 'heart_rate':
        return getHeartRates(startDay, count);
      case 'blood_pressure':
        return getBloodPressures(startDay, count);
      case 'pressure':
        return getPressureList(startDay, count);
      case 'hrv':
        return getHrvList(startDay, count);
      case 'spo2':
        return getBloodOxygens(startDay, count);
      case 'temperature':
        return getTemperatureList(startDay, count);
      case 'sport':
        return getSports(startDay, count);
      default:
        throw ArgumentError('No ring history for vital: $vital');
    }
  }

  // ── Settings ───────────────────────────────────────────────────────
  Future<String> getHealthSettings() async =>
      await _methodChannel.invokeMethod<String>('getHealthSettings') ?? '{}';

  Future<bool> setHealthSettings(String jsonData) async =>
      await _methodChannel.invokeMethod<bool>('setHealthSettings', {
        'data': jsonData,
      }) ??
      false;

  Future<String> getNotificationSettings() async =>
      await _methodChannel.invokeMethod<String>('getNotificationSettings') ??
      '{}';

  Future<bool> setNotificationSetting(String jsonData) async =>
      await _methodChannel.invokeMethod<bool>('setNotificationSetting', {
        'data': jsonData,
      }) ??
      false;

  Future<String> getDisplaySettings() async =>
      await _methodChannel.invokeMethod<String>('getDisplaySettings') ?? '{}';

  Future<bool> setDisplaySetting(String jsonData) async =>
      await _methodChannel.invokeMethod<bool>('setDisplaySetting', {
        'data': jsonData,
      }) ??
      false;

  Future<String> getTargetAndProfile() async =>
      await _methodChannel.invokeMethod<String>('getTargetAndProfile') ?? '{}';

  Future<bool> setTargetAndProfile(String jsonData) async =>
      await _methodChannel.invokeMethod<bool>('setTargetAndProfile', {
        'data': jsonData,
      }) ??
      false;

  Future<String> getAdvancedSettings() async =>
      await _methodChannel.invokeMethod<String>('getAdvancedSettings') ?? '{}';

  Future<bool> setAdvancedSetting(String jsonData) async =>
      await _methodChannel.invokeMethod<bool>('setAdvancedSetting', {
        'data': jsonData,
      }) ??
      false;

  // ── Gesture Control (PalmScreenReq — wrist-flip / palm-screen wake) ──
  /// Returns JSON: `{"enabled": bool, "isLeft": bool, "needPalm": bool}`.
  Future<String> getGestureSetting() async =>
      await _methodChannel.invokeMethod<String>('getGestureSetting') ?? '{}';

  Future<bool> setGestureSetting({
    required bool enable,
    bool isLeft = true,
  }) async =>
      await _methodChannel.invokeMethod<bool>('setGestureSetting', {
        'enable': enable,
        'isLeft': isLeft,
      }) ??
      false;

  // ── Touch Control ──────────────────────────────────────────────────
  Future<String> getTouchControlSetting() async =>
      await _methodChannel.invokeMethod<String>('getTouchControlSetting') ??
      '{}';

  Future<String> setTouchControlSetting({
    required bool enable,
    int strength = 5,
  }) async =>
      await _methodChannel.invokeMethod<String>('setTouchControlSetting', {
        'enable': enable,
        'strength': strength,
      }) ??
      '{}';

  // ── Ring System Control ──────────────────────────────────────────────
  /// Sends factory reset command (RestoreKeyReq) to the ring.
  Future<bool> factoryReset() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('factoryReset');
      return res ?? false;
    } catch (e) {
      debugPrint('factoryReset error: $e');
      return false;
    }
  }

  /// Sends power off command (SimpleKeyPowerOffReq) to shut down the ring.
  Future<bool> shutDownRing() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('shutDownRing');
      return res ?? false;
    } catch (e) {
      debugPrint('shutDownRing error: $e');
      return false;
    }
  }

  Future<String> getDrinkReminder() async =>
      await _methodChannel.invokeMethod<String>('getDrinkReminder') ?? '{}';

  Future<bool> setDrinkReminder(String jsonData) async =>
      await _methodChannel.invokeMethod<bool>('setDrinkReminder', {
        'data': jsonData,
      }) ??
      false;

  Future<String> getSedentaryReminder() async =>
      await _methodChannel.invokeMethod<String>('getSedentaryReminder') ?? '{}';

  Future<bool> setSedentaryReminder(String jsonData) async =>
      await _methodChannel.invokeMethod<bool>('setSedentaryReminder', {
        'data': jsonData,
      }) ??
      false;

  // ── OTA ────────────────────────────────────────────────────────────
  Future<bool> startOta(String filePath) async =>
      await _methodChannel.invokeMethod<bool>('startOta', {
        'filePath': filePath,
      }) ??
      false;

  // ── Notification ───────────────────────────────────────────────────
  Future<void> sendNotification({
    required int type,
    required String title,
    required String content,
  }) => _methodChannel.invokeMethod('sendNotification', {
    'type': type,
    'title': title,
    'content': content,
  });

  // ── Ring camera / photo control ────────────────────────────────────
  // Enters the ring's camera UI and starts the phone-side keep-alive loop
  // (native re-sends ACTION_KEEP_SCREEN_ON every ~2s). Listen on `events` for
  // a `cameraShutter` event with data `{"action": "capture"}` (ring's physical
  // shutter was pressed) or `{"action": "exit"}` (ring itself left camera mode).
  Future<bool> takePicture() async =>
      await _methodChannel.invokeMethod<bool>('takePicture') ?? false;

  /// Tells the ring to exit its camera UI and stops the native keep-alive loop.
  /// Always call this when the phone's camera screen is closed/disposed, even
  /// if a `cameraShutter` "exit" event was already received.
  Future<bool> exitCameraMode() async =>
      await _methodChannel.invokeMethod<bool>('exitCameraMode') ?? false;

  Future<bool> scanMediaFile(String path) async {
    try {
      return await _methodChannel.invokeMethod<bool>('scanMediaFile', {'path': path}) ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── Workout ────────────────────────────────────────────────────────
  Future<void> startWorkout(String type, int startTimeMs) => _methodChannel
      .invokeMethod('startWorkout', {'type': type, 'startTimeMs': startTimeMs});

  Future<void> stopWorkout() => _methodChannel.invokeMethod('stopWorkout');

  // ── Local readings (Room, via the continuous background measurement loop) ──
  // vital keys: heart_rate | spo2 | stress | blood_pressure | steps | hrv | temperature

  Future<String> getReadings(
    String vital, {
    int? fromMs,
    int? toMs,
    int limit = 1000,
  }) async =>
      await _methodChannel.invokeMethod<String>('getReadings', {
        'vital': vital,
        'fromMs': fromMs ?? 0,
        'toMs': toMs ?? DateTime.now().millisecondsSinceEpoch,
        'limit': limit,
      }) ??
      '[]';

  Future<String> getTodaySummary(String vital) async =>
      await _methodChannel.invokeMethod<String>('getTodaySummary', {
        'vital': vital,
      }) ??
      '{}';

  /// Any calendar day from local Room (raw first, then daily_vital_summary cache).
  Future<String> getDaySummary(
    String vital, {
    required int dayStartMs,
    int? dayEndMs,
  }) async =>
      await _methodChannel.invokeMethod<String>('getDaySummary', {
        'vital': vital,
        'dayStartMs': dayStartMs,
        'dayEndMs': dayEndMs ?? (dayStartMs + 24 * 60 * 60 * 1000 - 1),
      }) ??
      '{}';

  /// Multi-day offline history from local daily rollups (and recent raw recompute).
  Future<String> getLocalHistory(
    String vital, {
    required int fromDayStartMs,
    required int toDayStartMs,
  }) async =>
      await _methodChannel.invokeMethod<String>('getLocalHistory', {
        'vital': vital,
        'fromDayStartMs': fromDayStartMs,
        'toDayStartMs': toDayStartMs,
      }) ??
      '[]';

  /// Persist a cloud day-row into Room so the next open works offline.
  Future<bool> cacheCloudDaySummary({
    required String vital,
    required int dayStartMs,
    double? avg,
    double? min,
    double? max,
    int count = 0,
    double? avgSecondary,
    double? minSecondary,
    double? maxSecondary,
    int? steps,
    int? caloriesKcal,
    double? distanceM,
  }) async =>
      await _methodChannel.invokeMethod<bool>('cacheCloudDaySummary', {
        'vital': vital,
        'dayStartMs': dayStartMs,
        'avg': avg,
        'min': min,
        'max': max,
        'count': count,
        'avgSecondary': avgSecondary,
        'minSecondary': minSecondary,
        'maxSecondary': maxSecondary,
        'steps': steps,
        'caloriesKcal': caloriesKcal,
        'distanceM': distanceM,
      }) ??
      false;

  Future<String> getLocalDbStats() async =>
      await _methodChannel.invokeMethod<String>('getLocalDbStats') ?? '{}';

  Future<String> getLatestReading(String vital) async =>
      await _methodChannel.invokeMethod<String>('getLatestReading', {
        'vital': vital,
      }) ??
      '{}';

  /// Persist a single manual heart rate reading directly to Room (QRing-style
  /// app_heart). Used by heart_rate_screen after readHeartRate() so hourly
  /// chart + daily aggregate include it instead of blending avg ~/2.
  Future<bool> insertHeartRate({
    required int valueBpm,
    int? measuredAtMs,
    String source = 'manual',
  }) async =>
      await _methodChannel.invokeMethod<bool>('insertHeartRate', {
        'valueBpm': valueBpm,
        'measuredAt': measuredAtMs ?? DateTime.now().millisecondsSinceEpoch,
        'source': source,
      }) ??
      false;

  Future<bool> insertSpo2({
    required int valuePct,
    int? measuredAtMs,
    String source = 'manual',
  }) async =>
      await _methodChannel.invokeMethod<bool>('insertSpo2', {
        'valuePct': valuePct,
        'measuredAt': measuredAtMs ?? DateTime.now().millisecondsSinceEpoch,
        'source': source,
      }) ??
      false;

  Future<bool> insertHrv({
    required int valueMs,
    int? measuredAtMs,
    String source = 'manual',
  }) async =>
      await _methodChannel.invokeMethod<bool>('insertHrv', {
        'valueMs': valueMs,
        'measuredAt': measuredAtMs ?? DateTime.now().millisecondsSinceEpoch,
        'source': source,
      }) ??
      false;

  Future<bool> insertTemperature({
    required double valueC,
    int? measuredAtMs,
    String source = 'manual',
  }) async =>
      await _methodChannel.invokeMethod<bool>('insertTemperature', {
        'valueC': valueC,
        'measuredAt': measuredAtMs ?? DateTime.now().millisecondsSinceEpoch,
        'source': source,
      }) ??
      false;

  /// Trigger bulk pull of ring's autonomous interval logs (QRing
  /// heart_rate_detail blob → per-point rows). Call on connect / resume.
  Future<String> syncIntervalHeartRateDetail() async =>
      await _methodChannel.invokeMethod<String>('syncIntervalHeartRateDetail') ??
      '[]';

  Future<String> syncIntervalSpo2Detail() async =>
      await _methodChannel.invokeMethod<String>('syncIntervalSpo2Detail') ??
      '[]';

  Future<String> syncIntervalTemperatureDetail() async =>
      await _methodChannel.invokeMethod<String>('syncIntervalTemperatureDetail') ??
      '[]';

  Future<String> getStepsToday() async =>
      await _methodChannel
          .invokeMethod<String>('getStepsToday')
          .timeout(const Duration(seconds: 10)) ??
      '{}';

  Future<String> getSyncStatus() async =>
      await _methodChannel.invokeMethod<String>('getSyncStatus') ?? '{}';

  Future<bool> answerPhoneCall() async =>
      await _methodChannel.invokeMethod<bool>('answerPhoneCall') ?? false;

  Future<bool> endOrDeclinePhoneCall() async =>
      await _methodChannel.invokeMethod<bool>('endOrDeclinePhoneCall') ?? false;

  Future<bool> toggleMediaPlayPause() async =>
      await _methodChannel.invokeMethod<bool>('toggleMediaPlayPause') ?? false;

  Future<String> getMeasurementCycleHistory({int? fromMs, int? toMs}) async =>
      await _methodChannel.invokeMethod<String>('getMeasurementCycleHistory', {
        'fromMs': fromMs ?? 0,
        'toMs': toMs ?? DateTime.now().millisecondsSinceEpoch,
      }) ??
      '[]';

  Future<String> getMeasurementAttempts({int? fromMs, int? toMs, int limit = 1000}) async =>
      await _methodChannel.invokeMethod<String>('getMeasurementAttempts', {
        'fromMs': fromMs ?? 0,
        'toMs': toMs ?? DateTime.now().millisecondsSinceEpoch,
        'limit': limit,
      }) ??
      '[]';

  Future<String> getFailedMeasurementAttempts({int? fromMs, int? toMs, int limit = 1000}) async =>
      await _methodChannel.invokeMethod<String>('getFailedMeasurementAttempts', {
        'fromMs': fromMs ?? 0,
        'toMs': toMs ?? DateTime.now().millisecondsSinceEpoch,
        'limit': limit,
      }) ??
      '[]';

  Future<String> getMeasurementAttemptsForCycle(int cycleId) async =>
      await _methodChannel.invokeMethod<String>('getMeasurementAttemptsForCycle', {
        'cycleId': cycleId,
      }) ??
      '[]';

  Future<bool> isIgnoringBatteryOptimizations() async =>
      await _methodChannel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? true;

  Future<bool> requestIgnoreBatteryOptimizations() async =>
      await _methodChannel.invokeMethod<bool>('requestIgnoreBatteryOptimizations') ?? false;

  /// Phase 1 fall-risk read surface — silent-logging only, no live alerts yet.
  /// See FallRiskAnalyzer.kt for scoring logic.
  Future<String> getFallRiskScore() async =>
      await _methodChannel.invokeMethod<String>('getFallRiskScore') ?? 'null';

  Future<String> getFallRiskLog({
    int? fromMs,
    int? toMs,
    int limit = 500,
  }) async =>
      await _methodChannel.invokeMethod<String>('getFallRiskLog', {
        'fromMs': fromMs ?? 0,
        'toMs': toMs ?? DateTime.now().millisecondsSinceEpoch,
        'limit': limit,
      }) ??
      '[]';

  /// Phase 2 fall-event read surface — silent-logging only, see FallMotionDetector.kt.
  Future<String> getFallEvents({
    int? fromMs,
    int? toMs,
    int limit = 200,
  }) async =>
      await _methodChannel.invokeMethod<String>('getFallEvents', {
        'fromMs': fromMs ?? 0,
        'toMs': toMs ?? DateTime.now().millisecondsSinceEpoch,
        'limit': limit,
      }) ??
      '[]';

  /// Read-only Layer 3 input: in-memory phone-motion monitoring state from
  /// FallMotionDetector (see getMotionSnapshot in BlePlugin.kt). Returns '{}'
  /// when unavailable — callers treat missing keys as unknown, never as zero.
  Future<String> getMotionSnapshot() async =>
      await _methodChannel.invokeMethod<String>('getMotionSnapshot') ?? '{}';

  /// Focus/Prayer usage read surface — see PhoneModeSessionEntity / PhoneModePlugin.kt.
  Future<String> getPhoneModeSessions({
    int? fromMs,
    int? toMs,
    int limit = 200,
  }) async =>
      await _methodChannel.invokeMethod<String>('getPhoneModeSessions', {
        'fromMs': fromMs ?? 0,
        'toMs': toMs ?? DateTime.now().millisecondsSinceEpoch,
        'limit': limit,
      }) ??
      '[]';

  /// Dev/testing only — fires the real fall-alert notification pipeline on demand, so it can
  /// be tested/demoed without a genuine drop test + concurrent vitals spike.
  Future<bool> simulateFallEvent() async =>
      await _methodChannel.invokeMethod<bool>('simulateFallEvent') ?? false;

  /// Posts a phone-side alert notification (via AlertNotifier) for a vital that just
  /// crossed a user-enabled threshold — see BleProvider._checkAlertThresholds.
  Future<bool> postHealthAlert({
    required String title,
    required String message,
    required String vital,
  }) async =>
      await _methodChannel.invokeMethod<bool>('postHealthAlert', {
        'title': title,
        'message': message,
        'vital': vital,
      }) ??
      false;

  /// Dev/testing only — posts a real NewReadingEvent so FallRiskAnalyzer's compute-and-log
  /// pipeline can be verified without a real ring connected (seedDemoData bypasses this path).
  Future<bool> clearMockVitals() async =>
      await _methodChannel.invokeMethod<bool>('clearMockVitals') ?? false;

  Future<bool> simulateFallRiskTrigger() async =>
      await _methodChannel.invokeMethod<bool>('simulateFallRiskTrigger') ??
      false;

  /// Client-demo only — posts a real vitals spike then deterministically fires the
  /// predictive "you might fall soon" notification, so the alert flow can be shown
  /// without waiting on real elevated vitals. See FallPredictionNotifier.kt.
  Future<bool> simulateFallPrediction() async =>
      await _methodChannel.invokeMethod<bool>('simulateFallPrediction') ??
      false;

  /// Reads the fall-prediction pending flag — `{"pending": bool, "hr": int}`.
  /// Pending is set when a prediction fires (not only when the notification is tapped),
  /// so a normal app open still surfaces the alert. Does not clear; call
  /// [clearFallPredictionFlag] when the user dismisses the banner.
  Future<String> consumeFallPredictionFlag() async =>
      await _methodChannel.invokeMethod<String>('consumeFallPredictionFlag') ??
      '{"pending":false,"hr":0}';

  /// Clears a dismissed fall-prediction alert so it does not reappear on next resume.
  Future<bool> clearFallPredictionFlag() async =>
      await _methodChannel.invokeMethod<bool>('clearFallPredictionFlag') ??
      false;

  /// Emergency SMS countdown / last-send status — see EmergencySmsSender.kt.
  Future<String> getEmergencySmsStatus() async =>
      await _methodChannel.invokeMethod<String>('getEmergencySmsStatus') ??
      '{"active":false,"secondsRemaining":0}';

  /// Cancel a pending auto-SMS countdown (I'm okay / Cancel SMS).
  Future<bool> cancelEmergencySms() async =>
      await _methodChannel.invokeMethod<bool>('cancelEmergencySms') ?? false;

  /// Send SMS via SmsManager to **all** emergency contacts immediately.
  /// Optional [message] overrides the default fall-help text.
  Future<String> sendEmergencySms({String? message}) async {
    final args = <String, dynamic>{};
    if (message != null) args['message'] = message;
    return await _methodChannel.invokeMethod<String>(
          'sendEmergencySms',
          args,
        ) ??
        '{"ok":false,"sentCount":0,"error":"no response"}';
  }

  Future<bool> placeEmergencyCall(String phone) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'placeEmergencyCall',
      {'phone': phone},
    );
    return result ?? false;
  }

  /// Auto-call on fall *detection* (not prediction) — toggle + permission status.
  Future<String> getAutoCallOnFallEnabled() async =>
      await _methodChannel.invokeMethod<String>('getAutoCallOnFallEnabled') ??
      '{"enabled":false,"hasPermission":false}';

  Future<String> setAutoCallOnFallEnabled(bool enabled) async =>
      await _methodChannel.invokeMethod<String>('setAutoCallOnFallEnabled', {
        'enabled': enabled,
      }) ??
      '{"enabled":false,"hasPermission":false}';

  /// Emergency contacts — persisted natively (Room), not Flutter widget state, so a future
  /// caregiver-push or notification action can read them without the Dart engine running.
  Future<String> getEmergencyContacts() async =>
      await _methodChannel.invokeMethod<String>('getEmergencyContacts') ?? '[]';

  Future<bool> addEmergencyContact(String name, String phone) async =>
      await _methodChannel.invokeMethod<bool>('addEmergencyContact', {
        'name': name,
        'phone': phone,
      }) ??
      false;

  Future<bool> updateEmergencyContact(
    int id,
    String name,
    String phone,
  ) async =>
      await _methodChannel.invokeMethod<bool>('updateEmergencyContact', {
        'id': id,
        'name': name,
        'phone': phone,
      }) ??
      false;

  Future<bool> deleteEmergencyContact(int id) async =>
      await _methodChannel.invokeMethod<bool>('deleteEmergencyContact', {
        'id': id,
      }) ??
      false;

  /// Dev/testing only — fills the local Room DB with plausible readings spanning
  /// the last [hoursBack] hours, so a freshly reinstalled app has data to show
  /// without needing the ring connected.
  Future<bool> seedDemoData({int hoursBack = 3}) async =>
      await _methodChannel.invokeMethod<bool>('seedDemoData', {
        'hoursBack': hoursBack,
      }) ??
      false;

  Future<bool> setVitalEnabled(String vital, bool enabled) async =>
      await _methodChannel.invokeMethod<bool>('setVitalEnabled', {
        'vital': vital,
        'enabled': enabled,
      }) ??
      false;

  Future<bool> getVitalEnabled(String vital) async =>
      await _methodChannel.invokeMethod<bool>('getVitalEnabled', {
        'vital': vital,
      }) ??
      false;

  Future<bool> setMasterLoopEnabled(bool enabled) async =>
      await _methodChannel.invokeMethod<bool>('setMasterLoopEnabled', {
        'enabled': enabled,
      }) ??
      false;

  Future<bool> getMasterLoopEnabled() async =>
      await _methodChannel.invokeMethod<bool>('getMasterLoopEnabled') ?? false;

  /// Gap between automatic measurement cycles, in milliseconds. This is a phone-side
  /// setting (SharedPreferences via MeasurementConfig), so it works whether or not the
  /// ring is connected. Native clamps to [30s, 30min]; default is 3 minutes.
  Future<bool> setCycleCooldownMs(int ms) async =>
      await _methodChannel.invokeMethod<bool>('setCycleCooldownMs', {
        'ms': ms,
      }) ??
      false;

  Future<int> getCycleCooldownMs() async =>
      await _methodChannel.invokeMethod<int>('getCycleCooldownMs') ?? 180000;

  Future<bool> setSyncEnabled(bool enabled) async =>
      await _methodChannel.invokeMethod<bool>('setSyncEnabled', {
        'enabled': enabled,
      }) ??
      false;

  Future<bool> getSyncEnabled() async =>
      await _methodChannel.invokeMethod<bool>('getSyncEnabled') ?? false;

  // Debug/testing only — triggers the 6h Supabase push immediately instead of waiting.
  Future<bool> forceSyncNow() async =>
      await _methodChannel.invokeMethod<bool>('forceSyncNow') ?? false;

  Future<bool> configureSync({
    required String url,
    required String anonKey,
    required String userId,
    String? accessToken,
  }) async =>
      await _methodChannel.invokeMethod<bool>('configureSync', {
        'url': url,
        'anonKey': anonKey,
        'userId': userId,
        'accessToken': accessToken,
      }) ??
      false;
}
