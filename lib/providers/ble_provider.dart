import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ble_service.dart';
import '../services/supabase_service.dart';

class ScannedDevice {
  final String name;
  final String address;
  final int rssi;
  ScannedDevice({required this.name, required this.address, required this.rssi});
}

class BleProvider extends ChangeNotifier {
  final BleService _ble = BleService();

  bool _isConnected = false;
  bool _isScanning = false;
  bool _isReconnecting = false;
  int _battery = -1;
  String _deviceName = '';
  String _deviceAddress = '';
  Map<String, String> _firmwareVersion = {};
  final List<ScannedDevice> _scannedDevices = [];
  StreamSubscription? _eventSub;

  // Steps state
  int _todaySteps = 0;
  int _todayCalories = 0;
  double _todayDistanceM = 0.0;
  bool _syncingSteps = false;
  List<int> _todayStepsByInterval = [];

  // Heart rate state
  int _todayAvgHr = 0;
  int _todayMinHr = 0;
  int _todayMaxHr = 0;

  // SpO2 state
  int _todayAvgSpo2 = 0;
  int _todayMinSpo2 = 0;
  int _todayMaxSpo2 = 0;

  bool get isReconnecting => _isReconnecting;

  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;
  int get battery => _battery;
  String get deviceName => _deviceName;
  String get deviceAddress => _deviceAddress;
  Map<String, String> get firmwareVersion => _firmwareVersion;
  List<ScannedDevice> get scannedDevices => List.unmodifiable(_scannedDevices);

  int get todaySteps => _todaySteps;
  int get todayCalories => _todayCalories;
  double get todayDistanceM => _todayDistanceM;
  bool get syncingSteps => _syncingSteps;
  List<int> get todayStepsByInterval => List.unmodifiable(_todayStepsByInterval);

  int get todayAvgHr => _todayAvgHr;
  int get todayMinHr => _todayMinHr;
  int get todayMaxHr => _todayMaxHr;

  int get todayAvgSpo2 => _todayAvgSpo2;
  int get todayMinSpo2 => _todayMinSpo2;
  int get todayMaxSpo2 => _todayMaxSpo2;

  void updateStepsData(int steps, int calories, double distanceM, List<int> intervals) {
    _todaySteps = steps;
    _todayCalories = calories;
    _todayDistanceM = distanceM;
    _todayStepsByInterval = intervals;
    notifyListeners();
  }

  void updateHrData(int avg, int min, int max) {
    _todayAvgHr = avg;
    _todayMinHr = min;
    _todayMaxHr = max;
    notifyListeners();
  }

  void updateSpo2Data(int avg, int min, int max) {
    _todayAvgSpo2 = avg;
    _todayMinSpo2 = min;
    _todayMaxSpo2 = max;
    notifyListeners();
  }

  BleProvider() {
    _loadSavedDevice();
    _listenEvents();
    _loadTodayFromSupabase();
    _loadTodayHrFromSupabase();
    _loadTodaySpo2FromSupabase();
  }

  void _listenEvents() {
    _eventSub = _ble.events.listen((event) {
      final type = event['type'] as String;
      final data = Map<String, dynamic>.from(event['data'] as Map? ?? {});
      switch (type) {
        case 'connectionState':
          _isConnected = data['connected'] as bool? ?? false;
          if (_isConnected) {
            _onConnected();
          } else {
            _battery = -1;
          }
          notifyListeners();
          break;
        case 'scanResult':
          final dev = ScannedDevice(
            name: data['name'] as String? ?? '',
            address: data['address'] as String? ?? '',
            rssi: data['rssi'] as int? ?? -100,
          );
          final idx = _scannedDevices.indexWhere((d) => d.address == dev.address);
          if (idx >= 0) {
            _scannedDevices[idx] = dev;
          } else {
            _scannedDevices.add(dev);
          }
          _scannedDevices.sort((a, b) => b.rssi.compareTo(a.rssi));
          notifyListeners();
          break;
        case 'scanFinished':
          _isScanning = false;
          notifyListeners();
          break;
      }
    });
  }

  Future<void> _loadSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceName = prefs.getString('device_name') ?? '';
    _deviceAddress = prefs.getString('device_address') ?? '';
    notifyListeners();
    if (_deviceAddress.isNotEmpty) {
      // Check if the background service kept us connected
      _isConnected = await _ble.isConnected();
      if (_isConnected) {
        _onConnected();
        notifyListeners();
      } else {
        // Not connected — reconnect in background without blocking UI
        _reconnectToSaved();
      }
    }
  }

  Future<void> checkConnection() async {
    _isConnected = await _ble.isConnected();
    if (_isConnected) _onConnected();
    notifyListeners();
  }

  Future<void> _reconnectToSaved() async {
    if (_deviceAddress.isEmpty || _isReconnecting) return;
    _isReconnecting = true;
    notifyListeners();
    try {
      final ok = await _ble.connect(_deviceAddress);
      if (ok) {
        _isConnected = true;
        _onConnected();
      }
    } catch (_) {}
    _isReconnecting = false;
    notifyListeners();
  }

  void _onConnected() {
    _ble.setTime();
    refreshBattery();
    refreshFirmwareVersion();
    // Steps are fetched by StepsScreen directly to avoid concurrent BLE calls.
  }

  Future<void> _loadTodayFromSupabase() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return;
      final now = DateTime.now();
      final ds = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final data = await SupabaseService.client
          .from('user_steps')
          .select()
          .eq('user_id', user.id)
          .eq('date', ds)
          .maybeSingle();
      if (data != null) {
        _todaySteps = (data['steps'] as num? ?? 0).toInt();
        _todayCalories = (data['calories'] as num? ?? 0).toInt();
        _todayDistanceM = (data['distance_m'] as num? ?? 0).toDouble();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _loadTodayHrFromSupabase() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return;
      final data = await SupabaseService.getTodayHr(user.id);
      if (data != null) {
        _todayAvgHr = (data['avg_hr'] as num? ?? 0).toInt();
        _todayMinHr = (data['min_hr'] as num? ?? 0).toInt();
        _todayMaxHr = (data['max_hr'] as num? ?? 0).toInt();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _loadTodaySpo2FromSupabase() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return;
      final data = await SupabaseService.getTodaySpo2(user.id);
      if (data != null) {
        _todayAvgSpo2 = (data['avg_spo2'] as num? ?? 0).toInt();
        _todayMinSpo2 = (data['min_spo2'] as num? ?? 0).toInt();
        _todayMaxSpo2 = (data['max_spo2'] as num? ?? 0).toInt();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> syncTodayStepsFromRing() async {
    if (_syncingSteps) return;
    _syncingSteps = true;
    notifyListeners();
    try {
      final json = await _ble.getTodaySteps();
      final decoded = jsonDecode(json);
      final list = decoded is List ? decoded : <dynamic>[];
      int totalSteps = 0, totalCal = 0;
      double totalDist = 0.0;
      // SDK ProGuard obfuscates BleStepDetails: d=slot, e=steps, f=calories, g=distance
      final slots = List<int>.filled(96, 0);
      for (final item in list) {
        final m = item as Map<String, dynamic>;
        final d     = (m['d'] as num? ?? 0).toInt(); // timeIndex: 15-min slot 0–95
        // ProGuard field order: e=calorie(小卡), f=walkSteps, g=distance(m), h=runSteps
        final steps = (m['f'] as num? ?? 0).toInt();           // walkSteps — raw count
        final cal   = (m['e'] as num? ?? 0).toInt() ~/ 1000;  // 小卡 → kcal
        final dist  = (m['g'] as num? ?? 0).toDouble();         // meters
        totalSteps += steps;
        totalCal   += cal;
        totalDist  += dist;
        if (d >= 0 && d < 96) slots[d] += steps;
      }
      _todayStepsByInterval = slots;
      _todaySteps = totalSteps;
      _todayCalories = totalCal;
      _todayDistanceM = totalDist;
      notifyListeners();
      final user = SupabaseService.currentUser;
      if (user != null && (totalSteps > 0 || totalCal > 0)) {
        await SupabaseService.upsertSteps(
          userId: user.id,
          date: DateTime.now(),
          steps: totalSteps,
          calories: totalCal,
          distanceM: totalDist,
        );
      }
    } catch (_) {}
    _syncingSteps = false;
    notifyListeners();
  }

  Future<void> refreshBattery() async {
    try {
      _battery = await _ble.getBattery();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshFirmwareVersion() async {
    try {
      final v = await _ble.getFirmwareVersion();
      _firmwareVersion = v.map((k, val) => MapEntry(k, val.toString()));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> startScan({String filterName = ''}) async {
    _scannedDevices.clear();
    _isScanning = true;
    notifyListeners();
    await _ble.startScan(filterName: filterName);
  }

  Future<void> stopScan() async {
    await _ble.stopScan();
    _isScanning = false;
    notifyListeners();
  }

  Future<bool> connect(ScannedDevice device) async {
    try {
      final ok = await _ble.connect(device.address);
      if (ok) {
        _deviceName = device.name;
        _deviceAddress = device.address;
        _isConnected = true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('device_name', device.name);
        await prefs.setString('device_address', device.address);
        _onConnected();
        notifyListeners();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect() async {
    await _ble.disconnect();
    _isConnected = false;
    _battery = -1;
    notifyListeners();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }
}
