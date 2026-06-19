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

  // ── Pressure ───────────────────────────────────────────────────────
  Future<String> getTodayPressure() async =>
      await _methodChannel.invokeMethod<String>('getTodayPressure') ?? '{}';

  Future<String> getPressure(int dayIndex) async =>
      await _methodChannel.invokeMethod<String>('getPressure', {'dayIndex': dayIndex}) ?? '{}';

  Future<String> getPressureList(int startDay, int count) async =>
      await _methodChannel.invokeMethod<String>('getPressureList', {'startDay': startDay, 'count': count}) ?? '[]';

  Future<String> manualModePressure({required bool start}) async =>
      await _methodChannel.invokeMethod<String>('manualModePressure', {'start': start}) ?? '{}';

  // ── Temperature ────────────────────────────────────────────────────
  Future<String> getTodayTemperature() async =>
      await _methodChannel.invokeMethod<String>('getTodayTemperature') ?? '{}';

  Future<String> getTemperature(int dayIndex) async =>
      await _methodChannel.invokeMethod<String>('getTemperature', {'dayIndex': dayIndex}) ?? '{}';

  Future<String> getTemperatureList(int startDay, int count) async =>
      await _methodChannel.invokeMethod<String>('getTemperatureList', {'startDay': startDay, 'count': count}) ?? '[]';

  Future<String> syncTemperature() async =>
      await _methodChannel.invokeMethod<String>('syncTemperature') ?? '[]';

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
}
