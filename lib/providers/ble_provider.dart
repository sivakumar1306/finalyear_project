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

  // Blood Pressure state
  int _latestBpSbp = 0;
  int _latestBpDbp = 0;

  // Stress state
  int _latestStressValue = 0;

  // HRV state
  int _todayAvgHrv = 0;

  // Sleep state
  int _todaySleepDuration = 0; // seconds
  int _todaySleepScore    = 0;

  // Background ring sync state
  bool   _isSyncing     = false;
  String _syncStep      = '';
  double _syncProgress  = 0.0;
  int    _syncGen       = 0; // incremented to cancel a stale in-progress sync

  // Delay (seconds) before issuing SDK commands after a connection event.
  int _connectDelaySeconds = 1;

  // ── Getters ───────────────────────────────────────────────────────────────

  bool get isReconnecting => _isReconnecting;
  bool get isConnected    => _isConnected;
  bool get isScanning     => _isScanning;
  int  get battery        => _battery;
  String get deviceName   => _deviceName;
  String get deviceAddress => _deviceAddress;
  Map<String, String> get firmwareVersion => _firmwareVersion;
  List<ScannedDevice> get scannedDevices => List.unmodifiable(_scannedDevices);

  int    get todaySteps           => _todaySteps;
  int    get todayCalories        => _todayCalories;
  double get todayDistanceM       => _todayDistanceM;
  bool   get syncingSteps         => _syncingSteps;
  List<int> get todayStepsByInterval => List.unmodifiable(_todayStepsByInterval);

  int get todayAvgHr  => _todayAvgHr;
  int get todayMinHr  => _todayMinHr;
  int get todayMaxHr  => _todayMaxHr;

  int get todayAvgSpo2 => _todayAvgSpo2;
  int get todayMinSpo2 => _todayMinSpo2;
  int get todayMaxSpo2 => _todayMaxSpo2;

  int get latestBpSbp       => _latestBpSbp;
  int get latestBpDbp       => _latestBpDbp;
  int get latestStressValue => _latestStressValue;
  int get todayAvgHrv       => _todayAvgHrv;

  int get todaySleepDuration => _todaySleepDuration;
  int get todaySleepScore    => _todaySleepScore;

  bool   get isSyncing    => _isSyncing;
  String get syncStep     => _syncStep;
  double get syncProgress => _syncProgress;

  // ── Manual update methods (called by individual screens) ──────────────────

  void updateStepsData(int steps, int calories, double distanceM, List<int> intervals) {
    _todaySteps      = steps;
    _todayCalories   = calories;
    _todayDistanceM  = distanceM;
    _todayStepsByInterval = intervals;
    notifyListeners();
  }

  void updateHrData(int avg, int min, int max) {
    _todayAvgHr = avg; _todayMinHr = min; _todayMaxHr = max;
    notifyListeners();
  }

  void updateSpo2Data(int avg, int min, int max) {
    _todayAvgSpo2 = avg; _todayMinSpo2 = min; _todayMaxSpo2 = max;
    notifyListeners();
  }

  void updateBpLatest(int sbp, int dbp) {
    _latestBpSbp = sbp; _latestBpDbp = dbp;
    notifyListeners();
  }

  void updateStressLatest(int value) {
    _latestStressValue = value;
    notifyListeners();
  }

  void updateHrvLatest(int avgHrv) {
    _todayAvgHrv = avgHrv;
    notifyListeners();
  }

  void updateSleepData(int duration, int score) {
    _todaySleepDuration = duration;
    _todaySleepScore    = score;
    notifyListeners();
  }

  // ── Constructor ───────────────────────────────────────────────────────────

  BleProvider() {
    _loadSavedDevice();
    _listenEvents();
    _loadTodayFromSupabase();
    _loadTodayHrFromSupabase();
    _loadTodaySpo2FromSupabase();
    _loadLatestBpFromSupabase();
    _loadLatestStressFromSupabase();
    _loadTodayHrvFromSupabase();
    _loadTodaySleepFromSupabase();
  }

  // ── Event listener ────────────────────────────────────────────────────────

  void _listenEvents() {
    _eventSub = _ble.events.listen((event) {
      final type = event['type'] as String;
      final data = Map<String, dynamic>.from(event['data'] as Map? ?? {});
      switch (type) {
        case 'connectionState':
          _isConnected = data['connected'] as bool? ?? false;
          if (_isConnected) {
            _onConnected(delay: _connectDelaySeconds);
          } else {
            _battery = -1;
          }
          notifyListeners();
          break;
        case 'scanResult':
          final dev = ScannedDevice(
            name:    data['name']    as String? ?? '',
            address: data['address'] as String? ?? '',
            rssi:    data['rssi']    as int?    ?? -100,
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

  // ── Device management ─────────────────────────────────────────────────────

  Future<void> _loadSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceName    = prefs.getString('device_name')    ?? '';
    _deviceAddress = prefs.getString('device_address') ?? '';
    notifyListeners();
    if (_deviceAddress.isNotEmpty) {
      _isConnected = await _ble.isConnected();
      if (_isConnected) {
        _onConnected(delay: 1);
        notifyListeners();
      } else {
        _connectDelaySeconds = 1;
        _reconnectToSaved();
      }
    }
  }

  Future<void> checkConnection() async {
    _isConnected = await _ble.isConnected();
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
        // _onConnected() is triggered by the connectionState event from the SDK,
        // which fires when the ring is fully ready (green light). Calling it here
        // (on raw GATT connect) is too early and causes sync to hang.
      }
    } catch (_) {}
    _isReconnecting = false;
    notifyListeners();
  }

  void _onConnected({int delay = 3}) {
    _initThenSync(delay);
  }

  Future<void> _initThenSync(int delaySeconds) async {
    await Future.delayed(Duration(seconds: delaySeconds));
    // Await setTime so the ring finishes its daily midnight reset before we
    // start fetching metrics. Skipping this await was the cause of the
    // blood-oxygen SDK crash at 12:03 AM.
    try { await _ble.setTime(); } catch (_) {}
    await refreshBattery();
    await refreshFirmwareVersion();
    if (_isConnected) syncAllFromRing();
  }

  // ── Sync cancellation ─────────────────────────────────────────────────────

  void _cancelSync() {
    if (!_isSyncing) return;
    _syncGen++;
    _isSyncing    = false;
    _syncStep     = '';
    _syncProgress = 0.0;
    notifyListeners();
  }

  // ── Background ring sync (all metrics sequentially) ───────────────────────

  Future<void> syncAllFromRing() async {
    if (_isSyncing || !_isConnected) return;
    final myGen = ++_syncGen;
    bool alive() => _syncGen == myGen;

    _isSyncing    = true;
    _syncProgress = 0.0;
    _syncStep     = 'Steps';
    notifyListeners();

    const kTimeout = Duration(seconds: 15);

    try {
      // 1. Steps (0% → 20%)
      try { await syncTodayStepsFromRing().timeout(kTimeout); } catch (_) {}
      if (!alive()) return;
      _syncProgress = 0.2; _syncStep = 'Heart Rate'; notifyListeners();

      // 2. Heart Rate (20% → 40%)
      try {
        final json = await _ble.getTodayHeartRate().timeout(kTimeout);
        _parseAndSaveHr(json);
      } catch (_) {}
      if (!alive()) return;
      _syncProgress = 0.4; _syncStep = 'Blood Oxygen'; notifyListeners();

      // 3. Blood Oxygen (40% → 60%)
      try {
        final json = await _ble.getTodayBloodOxygen().timeout(kTimeout);
        _parseAndSaveSpo2(json);
      } catch (_) {}
      if (!alive()) return;
      _syncProgress = 0.6; _syncStep = 'HRV'; notifyListeners();

      // 4. HRV (60% → 80%)
      try {
        final json = await _ble.getTodayHrv().timeout(kTimeout);
        _parseAndSaveHrv(json);
      } catch (_) {}
      if (!alive()) return;
      _syncProgress = 0.8; _syncStep = 'Sleep'; notifyListeners();

      // 5. Sleep (80% → 100%)
      try {
        final json = await _ble.getTodaySleep().timeout(kTimeout);
        _parseAndSaveSleep(json);
      } catch (_) {}
      if (!alive()) return;
      _syncProgress = 1.0; notifyListeners();

      // Brief pause so user sees 100% before overlay hides
      await Future.delayed(const Duration(milliseconds: 700));
    } finally {
      if (alive()) {
        _isSyncing    = false;
        _syncStep     = '';
        _syncProgress = 0.0;
        notifyListeners();
      }
    }
  }

  // ── Parse & save helpers (used by sync, no setState) ─────────────────────

  void _parseAndSaveHr(String jsonStr) {
    try {
      final m   = jsonDecode(jsonStr) as Map<String, dynamic>;
      final raw = (m['e'] as List<dynamic>? ?? []).map((v) => (v as num).toInt()).toList();
      final readings = raw.where((v) => v > 0).toList();
      if (readings.isEmpty) return;
      final avg = (readings.reduce((a, b) => a + b) / readings.length).round();
      final min = readings.reduce((a, b) => a < b ? a : b);
      final max = readings.reduce((a, b) => a > b ? a : b);
      _todayAvgHr = avg; _todayMinHr = min; _todayMaxHr = max;
      notifyListeners();
      _saveHrToDb(avg, min, max, readings.length);
    } catch (_) {}
  }

  void _parseAndSaveSpo2(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded == null || decoded is! Map<String, dynamic>) return;
      final maxRaw = (decoded['maxArray'] as List<dynamic>? ?? []).map((v) => (v as num).toInt()).toList();
      final minRaw = (decoded['minArray'] as List<dynamic>? ?? []).map((v) => (v as num).toInt()).toList();
      final readings = maxRaw.where((v) => v > 0).toList();
      if (readings.isEmpty) return;
      final avg = (readings.reduce((a, b) => a + b) / readings.length).round();
      final max = readings.reduce((a, b) => a > b ? a : b);
      final minReadings = minRaw.where((v) => v > 0).toList();
      final min = minReadings.isNotEmpty
          ? minReadings.reduce((a, b) => a < b ? a : b)
          : readings.reduce((a, b) => a < b ? a : b);
      _todayAvgSpo2 = avg; _todayMinSpo2 = min; _todayMaxSpo2 = max;
      notifyListeners();
      _saveSpo2ToDb(avg, min, max, readings.length);
    } catch (_) {}
  }

  void _parseAndSaveHrv(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded == null || decoded is! Map<String, dynamic>) return;
      final raw = (decoded['d'] as List<dynamic>? ?? []).map((v) => (v as num).toInt()).toList();
      final readings = raw.where((v) => v > 0).toList();
      if (readings.isEmpty) return;
      final avg = (readings.reduce((a, b) => a + b) / readings.length).round();
      final min = readings.reduce((a, b) => a < b ? a : b);
      final max = readings.reduce((a, b) => a > b ? a : b);
      _todayAvgHrv = avg;
      notifyListeners();
      _saveHrvToDb(avg, min, max, readings.length);
    } catch (_) {}
  }

  void _parseAndSaveSleep(String jsonStr) {
    try {
      final d     = jsonDecode(jsonStr) as Map<String, dynamic>;
      final total = (d['totalSleepDuration'] as num? ?? 0).toInt();
      final deep  = (d['deepDuration']       as num? ?? 0).toInt();
      final light = (d['lightDuration']      as num? ?? 0).toInt();
      final rem   = (d['remDuration']        as num? ?? 0).toInt();
      final awake = (d['awakeDuration']      as num? ?? 0).toInt();
      final st    = (d['sleepTime']          as num? ?? 0).toInt();
      final et    = (d['wakeTime']           as num? ?? 0).toInt();
      if (total <= 0) return;
      final window     = (st > 0 && et > 0) ? (et - st) : total;
      final efficiency = window > 0 ? (total / window * 100).clamp(0.0, 100.0) : 0.0;
      final deepPct    = total > 0 ? (deep / total * 100).clamp(0.0, 40.0) : 0.0;
      final remPct     = total > 0 ? (rem  / total * 100).clamp(0.0, 30.0) : 0.0;
      final score      = (efficiency * 0.4 + deepPct * 1.0 + remPct * 0.5).round().clamp(0, 100);
      _todaySleepDuration = total;
      _todaySleepScore    = score;
      notifyListeners();
      _saveSleepToDb(total, deep, light, rem, awake, score, st, et);
    } catch (_) {}
  }

  // ── DB save helpers ───────────────────────────────────────────────────────

  Future<void> _saveHrToDb(int avg, int min, int max, int count) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.upsertHr(
        userId: user.id, date: DateTime.now(),
        avgHr: avg, minHr: min, maxHr: max, sampleCount: count,
      );
    } catch (_) {}
  }

  Future<void> _saveSpo2ToDb(int avg, int min, int max, int count) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.upsertSpo2(
        userId: user.id, date: DateTime.now(),
        avgSpo2: avg, minSpo2: min, maxSpo2: max, sampleCount: count,
      );
    } catch (_) {}
  }

  Future<void> _saveHrvToDb(int avg, int min, int max, int count) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.upsertHrv(
        userId: user.id, date: DateTime.now(),
        avgHrv: avg, minHrv: min, maxHrv: max, sampleCount: count,
      );
    } catch (_) {}
  }

  Future<void> _saveSleepToDb(int total, int deep, int light, int rem,
      int awake, int score, int st, int et) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.upsertSleep(
        userId: user.id, date: DateTime.now(),
        totalDuration: total, deepDuration: deep, lightDuration: light,
        remDuration: rem, awakeDuration: awake,
        sleepScore: score, sleepTime: st, wakeTime: et,
      );
    } catch (_) {}
  }

  // ── Supabase load-on-startup ──────────────────────────────────────────────

  Future<void> _loadTodayFromSupabase() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return;
      final now = DateTime.now();
      final ds  = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final data = await SupabaseService.client
          .from('user_steps')
          .select()
          .eq('user_id', user.id)
          .eq('date', ds)
          .maybeSingle();
      if (data != null) {
        _todaySteps     = (data['steps']      as num? ?? 0).toInt();
        _todayCalories  = (data['calories']   as num? ?? 0).toInt();
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

  Future<void> _loadLatestBpFromSupabase() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return;
      final data = await SupabaseService.getLatestBp(user.id);
      if (data != null) {
        _latestBpSbp = (data['systolic']  as num? ?? 0).toInt();
        _latestBpDbp = (data['diastolic'] as num? ?? 0).toInt();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _loadLatestStressFromSupabase() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return;
      final data = await SupabaseService.getLatestStress(user.id);
      if (data != null) {
        _latestStressValue = (data['stress_value'] as num? ?? 0).toInt();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _loadTodayHrvFromSupabase() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return;
      final data = await SupabaseService.getHrvForDate(user.id, DateTime.now());
      if (data != null) {
        _todayAvgHrv = (data['avg_hrv'] as num? ?? 0).toInt();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _loadTodaySleepFromSupabase() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return;
      final data = await SupabaseService.getSleepForDate(user.id, DateTime.now());
      if (data != null) {
        _todaySleepDuration = (data['total_duration'] as num? ?? 0).toInt();
        _todaySleepScore    = (data['sleep_score']    as num? ?? 0).toInt();
        notifyListeners();
      }
    } catch (_) {}
  }

  // ── Steps sync (also called from StepsScreen) ─────────────────────────────

  Future<void> syncTodayStepsFromRing() async {
    if (_syncingSteps) return;
    _syncingSteps = true;
    notifyListeners();
    try {
      final json    = await _ble.getTodaySteps().timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(json);
      final list    = decoded is List ? decoded : <dynamic>[];
      int totalSteps = 0, totalCal = 0;
      double totalDist = 0.0;
      final slots = List<int>.filled(96, 0);
      for (final item in list) {
        final m     = item as Map<String, dynamic>;
        final d     = (m['d'] as num? ?? 0).toInt();
        final steps = (m['f'] as num? ?? 0).toInt();
        final cal   = (m['e'] as num? ?? 0).toInt() ~/ 1000;
        final dist  = (m['g'] as num? ?? 0).toDouble();
        totalSteps += steps;
        totalCal   += cal;
        totalDist  += dist;
        if (d >= 0 && d < 96) slots[d] += steps;
      }
      _todayStepsByInterval = slots;
      _todaySteps     = totalSteps;
      _todayCalories  = totalCal;
      _todayDistanceM = totalDist;
      notifyListeners();
      final user = SupabaseService.currentUser;
      if (user != null && (totalSteps > 0 || totalCal > 0)) {
        await SupabaseService.upsertSteps(
          userId: user.id, date: DateTime.now(),
          steps: totalSteps, calories: totalCal, distanceM: totalDist,
        );
      }
    } catch (_) {}
    _syncingSteps = false;
    notifyListeners();
  }

  // ── Device info ───────────────────────────────────────────────────────────

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

  // ── Scan / connect ────────────────────────────────────────────────────────

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
      // Cancel any in-progress sync so stale SDK callbacks don't collide with
      // the new ring's data, then disconnect before connecting to the new ring.
      _cancelSync();
      await _ble.disconnect();
      _isConnected    = false;
      _isReconnecting = false;
      _connectDelaySeconds = 2;
      notifyListeners();

      final ok = await _ble.connect(device.address);
      if (ok) {
        _deviceName    = device.name;
        _deviceAddress = device.address;
        _isConnected   = true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('device_name',    device.name);
        await prefs.setString('device_address', device.address);
        // _onConnected() is triggered by the connectionState event from the SDK,
        // which fires when the ring is fully ready (green light). Calling it here
        // (on raw GATT connect) is too early and causes sync to hang.
        notifyListeners();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Connect directly to the last saved ring address without requiring a BLE
  /// scan result. Useful when the ring is bonded but not advertising (e.g.
  /// after being used by another app).
  Future<bool> connectLastDevice() async {
    if (_deviceAddress.isEmpty) return false;
    try {
      final ok = await _ble.connect(_deviceAddress);
      if (ok) {
        _isConnected = true;
        notifyListeners();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect() async {
    _cancelSync();
    await _ble.disconnect();
    _isConnected = false;
    _battery     = -1;
    notifyListeners();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }
}
