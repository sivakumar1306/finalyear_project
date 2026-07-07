import 'dart:async';
import 'package:flutter/services.dart';

class BleService {
  static const _methodChannel = MethodChannel('com.medxai.qring/ble');
  static const _eventChannel = EventChannel('com.medxai.qring/ble_events');

  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  Stream<Map<String, dynamic>>? _eventStream;

  Stream<Map<String, dynamic>> get events {
    _eventStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((e) => Map<String, dynamic>.from(e as Map));
    return _eventStream!;
  }

  // ── Scanning ──────────────────────────────────────────────────────
  Future<void> startScan({String filterName = ''}) =>
      _methodChannel.invokeMethod('startScan', {'filterName': filterName});

  Future<void> stopScan() => _methodChannel.invokeMethod('stopScan');

  // ── Connection ─────────────────────────────────────────────────────
  Future<bool> connect(String address) async {
    final result = await _methodChannel.invokeMethod<bool>('connect', {'address': address});
    return result ?? false;
  }

  Future<void> disconnect() => _methodChannel.invokeMethod('disconnect');

  Future<bool> isConnected() async {
    final result = await _methodChannel.invokeMethod<bool>('isConnected');
    return result ?? false;
  }

  // ── Device Info ────────────────────────────────────────────────────
  Future<int> getBattery() async {
    final result = await _methodChannel.invokeMethod<int>('getBattery');
    return result ?? -1;
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
    final result = await _methodChannel.invokeMethod<String>('getDeviceSupport');
    return result ?? '{}';
  }

  // ── Heart Rate ─────────────────────────────────────────────────────
  Future<String> getTodayHeartRate() async =>
      await _methodChannel.invokeMethod<String>('getTodayHeartRate') ?? '{}';

  Future<String> getHeartRate(int dayIndex) async =>
      await _methodChannel.invokeMethod<String>('getHeartRate', {'dayIndex': dayIndex}) ?? '{}';

  Future<String> getHeartRates(int startDay, int count) async =>
      await _methodChannel.invokeMethod<String>('getHeartRates', {'startDay': startDay, 'count': count}) ?? '[]';

  Future<String> getHeartRateSetting() async =>
      await _methodChannel.invokeMethod<String>('getHeartRateSetting') ?? '{}';

  Future<bool> setHeartRateSetting({required bool enable, required int interval}) async =>
      await _methodChannel.invokeMethod<bool>('setHeartRateSetting', {'enable': enable, 'interval': interval}) ?? false;

  Future<String> manualModeHeart({required bool start}) async =>
      await _methodChannel.invokeMethod<String>('manualModeHeart', {'start': start}) ?? '{}';

  // Single-call measurement: starts, waits for a valid reading, auto-stops.
  // Returns the heart rate in bpm, or null if no reading received.
  Future<int?> readHeartRate() async =>
      _methodChannel.invokeMethod<int>('readHeartRate');

  Future<String> syncIntervalHeartRate() async =>
      await _methodChannel.invokeMethod<String>('syncIntervalHeartRate') ?? '[]';

  // ── Blood Pressure ─────────────────────────────────────────────────
  Future<String> getTodayBloodPressure() async =>
      await _methodChannel.invokeMethod<String>('getTodayBloodPressure') ?? '[]';

  Future<String> getBloodPressure(int dayIndex) async =>
      await _methodChannel.invokeMethod<String>('getBloodPressure', {'dayIndex': dayIndex}) ?? '[]';

  Future<String> getBloodPressures(int startDay, int count) async =>
      await _methodChannel.invokeMethod<String>('getBloodPressures', {'startDay': startDay, 'count': count}) ?? '[]';

  Future<String> getBloodPressureSetting() async =>
      await _methodChannel.invokeMethod<String>('getBloodPressureSetting') ?? '{}';

  Future<bool> setBloodPressureSetting({required bool enable, required int interval}) async =>
      await _methodChannel.invokeMethod<bool>('setBloodPressureSetting', {'enable': enable, 'interval': interval}) ?? false;

  Future<String> manualModeBP({required bool start}) async =>
      await _methodChannel.invokeMethod<String>('manualModeBP', {'start': start}) ?? '{}';

  // ── Blood Oxygen ───────────────────────────────────────────────────
  Future<String> getTodayBloodOxygen() async =>
      await _methodChannel.invokeMethod<String>('getTodayBloodOxygen') ?? '{}';

  Future<String> getBloodOxygen(int dayIndex) async =>
      await _methodChannel.invokeMethod<String>('getBloodOxygen', {'dayIndex': dayIndex}) ?? '{}';

  Future<String> getBloodOxygens(int startDay, int count) async =>
      await _methodChannel.invokeMethod<String>('getBloodOxygens', {'startDay': startDay, 'count': count}) ?? '[]';

  Future<String> getBloodOxygenSetting() async =>
      await _methodChannel.invokeMethod<String>('getBloodOxygenSetting') ?? '{}';

  Future<bool> setBloodOxygenSetting({required bool enable, required int interval}) async =>
      await _methodChannel.invokeMethod<bool>('setBloodOxygenSetting', {'enable': enable, 'interval': interval}) ?? false;

  Future<String> manualModeBloodOxygen({required bool start}) async =>
      await _methodChannel.invokeMethod<String>('manualModeBloodOxygen', {'start': start}) ?? '{}';

  Future<String> syncIntervalBloodOxygen() async =>
      await _methodChannel.invokeMethod<String>('syncIntervalBloodOxygen') ?? '[]';

  // ── Steps ──────────────────────────────────────────────────────────
  Future<bool> syncTodaySteps() async =>
      await _methodChannel.invokeMethod<bool>('syncTodaySteps') ?? false;

  Future<String> getTodaySteps() async =>
      await _methodChannel.invokeMethod<String>('getTodaySteps') ?? '{}';

  Future<String> getSteps(int dayIndex) async =>
      await _methodChannel.invokeMethod<String>('getSteps', {'dayIndex': dayIndex}) ?? '{}';

  Future<String> getStepsList(int startDay, int count) async =>
      await _methodChannel.invokeMethod<String>('getStepsList', {'startDay': startDay, 'count': count}) ?? '[]';

  Future<String> syncStepDetails() async =>
      await _methodChannel.invokeMethod<String>('syncStepDetails') ?? '[]';

  // ── Sleep ──────────────────────────────────────────────────────────
  Future<String> getTodaySleep() async =>
      await _methodChannel.invokeMethod<String>('getTodaySleep') ?? '{}';

  Future<String> getSleep(int dayIndex) async =>
      await _methodChannel.invokeMethod<String>('getSleep', {'dayIndex': dayIndex}) ?? '{}';

  Future<String> getSleepList(int startDay, int count) async =>
      await _methodChannel.invokeMethod<String>('getSleepList', {'startDay': startDay, 'count': count}) ?? '[]';

  Future<String> syncSleep() async =>
      await _methodChannel.invokeMethod<String>('syncSleep') ?? '[]';

  // ── HRV ────────────────────────────────────────────────────────────
  Future<String> getTodayHrv() async =>
      await _methodChannel.invokeMethod<String>('getTodayHrv') ?? '{}';

  Future<String> getHrv(int dayIndex) async =>
      await _methodChannel.invokeMethod<String>('getHrv', {'dayIndex': dayIndex}) ?? '{}';

  Future<String> getHrvList(int startDay, int count) async =>
      await _methodChannel.invokeMethod<String>('getHrvList', {'startDay': startDay, 'count': count}) ?? '[]';

  Future<String> manualModeHrv({required bool start}) async =>
      await _methodChannel.invokeMethod<String>('manualModeHrv', {'start': start}) ?? '{}';

  // ── Pressure ───────────────────────────────────────────────────────
  Future<String> getTodayPressure() async =>
      await _methodChannel.invokeMethod<String>('getTodayPressure') ?? '{}';

  Future<String> getPressure(int dayIndex) async =>
      await _methodChannel.invokeMethod<String>('getPressure', {'dayIndex': dayIndex}) ?? '{}';

  Future<String> getPressureList(int startDay, int count) async =>
      await _methodChannel.invokeMethod<String>('getPressureList', {'startDay': startDay, 'count': count}) ?? '[]';

  Future<String> getPressureSetting() async =>
      await _methodChannel.invokeMethod<String>('getPressureSetting') ?? '{}';

  Future<bool> setPressureSetting({required bool enable}) async =>
      await _methodChannel.invokeMethod<bool>('setPressureSetting', {'enable': enable}) ?? false;

  Future<String> manualModePressure({required bool start}) async =>
      await _methodChannel.invokeMethod<String>('manualModePressure', {'start': start}) ?? '{}';

  // ── Temperature ────────────────────────────────────────────────────
  Future<String> getTodayTemperature() async =>
      await _methodChannel.invokeMethod<String>('getTodayTemperature') ?? '{}';

  Future<String> getTemperature(int dayIndex) async =>
      await _methodChannel.invokeMethod<String>('getTemperature', {'dayIndex': dayIndex}) ?? '{}';

  Future<String> getTemperatureList(int startDay, int count) async =>
      await _methodChannel.invokeMethod<String>('getTemperatureList', {'startDay': startDay, 'count': count}) ?? '[]';

  Future<String> getTemperatureSetting() async =>
      await _methodChannel.invokeMethod<String>('getTemperatureSetting') ?? '{}';

  Future<bool> setTemperatureSetting({required bool enable, required int interval}) async =>
      await _methodChannel.invokeMethod<bool>('setTemperatureSetting', {'enable': enable, 'interval': interval}) ?? false;

  Future<String> syncAutoTemperature() async =>
      await _methodChannel.invokeMethod<String>('syncAutoTemperature') ?? '{}';

  Future<String> syncManualTemperature() async =>
      await _methodChannel.invokeMethod<String>('syncManualTemperature') ?? '[]';

  // ── Sport Records ──────────────────────────────────────────────────
  Future<String> getSportRecords() async =>
      await _methodChannel.invokeMethod<String>('getSportRecords') ?? '[]';

  // ── Settings ───────────────────────────────────────────────────────
  Future<String> getHealthSettings() async =>
      await _methodChannel.invokeMethod<String>('getHealthSettings') ?? '{}';

  Future<bool> setHealthSettings(String jsonData) async =>
      await _methodChannel.invokeMethod<bool>('setHealthSettings', {'data': jsonData}) ?? false;

  Future<String> getNotificationSettings() async =>
      await _methodChannel.invokeMethod<String>('getNotificationSettings') ?? '{}';

  Future<bool> setNotificationSetting(String jsonData) async =>
      await _methodChannel.invokeMethod<bool>('setNotificationSetting', {'data': jsonData}) ?? false;

  Future<String> getDisplaySettings() async =>
      await _methodChannel.invokeMethod<String>('getDisplaySettings') ?? '{}';

  Future<bool> setDisplaySetting(String jsonData) async =>
      await _methodChannel.invokeMethod<bool>('setDisplaySetting', {'data': jsonData}) ?? false;

  Future<String> getTargetAndProfile() async =>
      await _methodChannel.invokeMethod<String>('getTargetAndProfile') ?? '{}';

  Future<bool> setTargetAndProfile(String jsonData) async =>
      await _methodChannel.invokeMethod<bool>('setTargetAndProfile', {'data': jsonData}) ?? false;

  Future<String> getAdvancedSettings() async =>
      await _methodChannel.invokeMethod<String>('getAdvancedSettings') ?? '{}';

  Future<bool> setAdvancedSetting(String jsonData) async =>
      await _methodChannel.invokeMethod<bool>('setAdvancedSetting', {'data': jsonData}) ?? false;

  // ── Touch Control ──────────────────────────────────────────────────
  Future<String> getTouchControlSetting() async =>
      await _methodChannel.invokeMethod<String>('getTouchControlSetting') ?? '{}';

  Future<String> setTouchControlSetting({required bool enable, int strength = 5}) async =>
      await _methodChannel.invokeMethod<String>(
          'setTouchControlSetting', {'enable': enable, 'strength': strength}) ??
      '{}';

  // ── Reminders ──────────────────────────────────────────────────────
  Future<String> getDrinkReminder() async =>
      await _methodChannel.invokeMethod<String>('getDrinkReminder') ?? '{}';

  Future<bool> setDrinkReminder(String jsonData) async =>
      await _methodChannel.invokeMethod<bool>('setDrinkReminder', {'data': jsonData}) ?? false;

  Future<String> getSedentaryReminder() async =>
      await _methodChannel.invokeMethod<String>('getSedentaryReminder') ?? '{}';

  Future<bool> setSedentaryReminder(String jsonData) async =>
      await _methodChannel.invokeMethod<bool>('setSedentaryReminder', {'data': jsonData}) ?? false;

  // ── OTA ────────────────────────────────────────────────────────────
  Future<bool> startOta(String filePath) async =>
      await _methodChannel.invokeMethod<bool>('startOta', {'filePath': filePath}) ?? false;

  // ── Notification ───────────────────────────────────────────────────
  Future<void> sendNotification({required int type, required String title, required String content}) =>
      _methodChannel.invokeMethod('sendNotification', {'type': type, 'title': title, 'content': content});

  // ── Workout ────────────────────────────────────────────────────────
  Future<void> startWorkout(String type, int startTimeMs) =>
      _methodChannel.invokeMethod('startWorkout', {'type': type, 'startTimeMs': startTimeMs});

  Future<void> stopWorkout() => _methodChannel.invokeMethod('stopWorkout');

  // ── Local readings (Room, via the continuous background measurement loop) ──
  // vital keys: heart_rate | spo2 | stress | blood_pressure | steps | hrv | temperature

  Future<String> getReadings(String vital, {int? fromMs, int? toMs, int limit = 1000}) async =>
      await _methodChannel.invokeMethod<String>('getReadings', {
        'vital': vital,
        'fromMs': fromMs ?? 0,
        'toMs': toMs ?? DateTime.now().millisecondsSinceEpoch,
        'limit': limit,
      }) ??
      '[]';

  Future<String> getTodaySummary(String vital) async =>
      await _methodChannel.invokeMethod<String>('getTodaySummary', {'vital': vital}) ?? '{}';

  Future<String> getLatestReading(String vital) async =>
      await _methodChannel.invokeMethod<String>('getLatestReading', {'vital': vital}) ?? '{}';

  Future<String> getStepsToday() async =>
      await _methodChannel.invokeMethod<String>('getStepsToday') ?? '{}';

  Future<String> getSyncStatus() async =>
      await _methodChannel.invokeMethod<String>('getSyncStatus') ?? '{}';

  Future<String> getMeasurementCycleHistory({int? fromMs, int? toMs}) async =>
      await _methodChannel.invokeMethod<String>('getMeasurementCycleHistory', {
        'fromMs': fromMs ?? 0,
        'toMs': toMs ?? DateTime.now().millisecondsSinceEpoch,
      }) ??
      '[]';

  /// Phase 1 fall-risk read surface — silent-logging only, no live alerts yet.
  /// See FallRiskAnalyzer.kt for scoring logic.
  Future<String> getFallRiskScore() async =>
      await _methodChannel.invokeMethod<String>('getFallRiskScore') ?? 'null';

  Future<String> getFallRiskLog({int? fromMs, int? toMs, int limit = 500}) async =>
      await _methodChannel.invokeMethod<String>('getFallRiskLog', {
        'fromMs': fromMs ?? 0,
        'toMs': toMs ?? DateTime.now().millisecondsSinceEpoch,
        'limit': limit,
      }) ??
      '[]';

  /// Phase 2 fall-event read surface — silent-logging only, see FallMotionDetector.kt.
  Future<String> getFallEvents({int? fromMs, int? toMs, int limit = 200}) async =>
      await _methodChannel.invokeMethod<String>('getFallEvents', {
        'fromMs': fromMs ?? 0,
        'toMs': toMs ?? DateTime.now().millisecondsSinceEpoch,
        'limit': limit,
      }) ??
      '[]';

  /// Dev/testing only — fires the real fall-alert notification pipeline on demand, so it can
  /// be tested/demoed without a genuine drop test + concurrent vitals spike.
  Future<bool> simulateFallEvent() async =>
      await _methodChannel.invokeMethod<bool>('simulateFallEvent') ?? false;

  /// Dev/testing only — posts a real NewReadingEvent so FallRiskAnalyzer's compute-and-log
  /// pipeline can be verified without a real ring connected (seedDemoData bypasses this path).
  Future<bool> simulateFallRiskTrigger() async =>
      await _methodChannel.invokeMethod<bool>('simulateFallRiskTrigger') ?? false;

  /// Emergency contacts — persisted natively (Room), not Flutter widget state, so a future
  /// caregiver-push or notification action can read them without the Dart engine running.
  Future<String> getEmergencyContacts() async =>
      await _methodChannel.invokeMethod<String>('getEmergencyContacts') ?? '[]';

  Future<bool> addEmergencyContact(String name, String phone) async =>
      await _methodChannel.invokeMethod<bool>('addEmergencyContact', {'name': name, 'phone': phone}) ?? false;

  Future<bool> deleteEmergencyContact(int id) async =>
      await _methodChannel.invokeMethod<bool>('deleteEmergencyContact', {'id': id}) ?? false;

  /// Dev/testing only — fills the local Room DB with plausible readings spanning
  /// the last [hoursBack] hours, so a freshly reinstalled app has data to show
  /// without needing the ring connected.
  Future<bool> seedDemoData({int hoursBack = 3}) async =>
      await _methodChannel.invokeMethod<bool>('seedDemoData', {'hoursBack': hoursBack}) ?? false;

  Future<bool> setVitalEnabled(String vital, bool enabled) async =>
      await _methodChannel.invokeMethod<bool>('setVitalEnabled', {'vital': vital, 'enabled': enabled}) ?? false;

  Future<bool> getVitalEnabled(String vital) async =>
      await _methodChannel.invokeMethod<bool>('getVitalEnabled', {'vital': vital}) ?? false;

  Future<bool> setMasterLoopEnabled(bool enabled) async =>
      await _methodChannel.invokeMethod<bool>('setMasterLoopEnabled', {'enabled': enabled}) ?? false;

  Future<bool> getMasterLoopEnabled() async =>
      await _methodChannel.invokeMethod<bool>('getMasterLoopEnabled') ?? false;

  Future<bool> setSyncEnabled(bool enabled) async =>
      await _methodChannel.invokeMethod<bool>('setSyncEnabled', {'enabled': enabled}) ?? false;

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
