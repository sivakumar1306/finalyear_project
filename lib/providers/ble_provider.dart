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
  int _todayAvgStress = 0;
  int _todayMinStress = 0;
  int _todayMaxStress = 0;

  // HRV state
  int _todayAvgHrv = 0;

  // Sleep state
  int _todaySleepDuration = 0; // seconds
  int _todaySleepScore    = 0;

  // Temperature state
  double _latestTempC = 0.0;

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
  int get todayAvgStress => _todayAvgStress;
  int get todayMinStress => _todayMinStress;
  int get todayMaxStress => _todayMaxStress;
  int get todayAvgHrv       => _todayAvgHrv;

  int get todaySleepDuration => _todaySleepDuration;
  int get todaySleepScore    => _todaySleepScore;

  double get latestTempC => _latestTempC;

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

  void updateTempLatest(double valueC) {
    _latestTempC = valueC;
    notifyListeners();
  }

  // ── Constructor ───────────────────────────────────────────────────────────

  BleProvider() {
    _loadSavedDevice();
    _listenEvents();
    // HR/SpO2/Stress/BP/Steps are now continuously acquired by the native background
    // loop and stored in local Room — read from there first, only falling back to
    // Supabase if local is empty (e.g. very first run before the loop has produced data).
    _loadTodayVitalsFromLocal();
    // HRV/Temperature are unrelated passive "ask the ring what it already recorded"
    // reads, not part of the new one-click measurement loop — left untouched.
    _loadTodayHrvFromSupabase();
    _loadTodaySleepFromSupabase();
    _loadLatestTempFromSupabase();
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
        case 'newReading':
          _onNewReadingEvent(data);
          break;
      }
    });
  }

  // ── Local-DB-backed vitals (continuous background measurement loop) ──────
  //
  // HR/SpO2/Stress/BP/Steps are now acquired continuously by the native
  // MeasurementLoopManager and stored in local Room, independent of whether
  // this screen/provider is alive. These helpers read that local DB (the
  // single source of truth) rather than re-triggering ring measurements.

  void _onNewReadingEvent(Map<String, dynamic> data) {
    switch (data['vital'] as String?) {
      case 'HEART_RATE': _refreshHrFromLocal(); break;
      case 'SPO2': _refreshSpo2FromLocal(); break;
      case 'STRESS': _refreshStressFromLocal(); break;
      case 'BLOOD_PRESSURE': _refreshBpFromLocal(); break;
      case 'STEPS': _refreshStepsFromLocal(); break;
    }
  }

  /// Dev/testing only — seeds the local DB with [hoursBack] hours of plausible
  /// readings (no ring connection needed) and refreshes the vitals shown in the
  /// app, so data survives a reinstall's data wipe without needing to re-pair.
  Future<void> seedDemoData({int hoursBack = 3}) async {
    await _ble.seedDemoData(hoursBack: hoursBack);
    await _loadTodayVitalsFromLocal();
  }

  Future<void> _loadTodayVitalsFromLocal() async {
    if (!await _refreshHrFromLocal()) await _loadTodayHrFromSupabase();
    if (!await _refreshSpo2FromLocal()) await _loadTodaySpo2FromSupabase();
    if (!await _refreshStressFromLocal()) await _loadLatestStressFromSupabase();
    if (!await _refreshBpFromLocal()) await _loadLatestBpFromSupabase();
    if (!await _refreshStepsFromLocal()) await _loadTodayFromSupabase();
  }

  Future<bool> _refreshHrFromLocal() async {
    try {
      final m = jsonDecode(await _ble.getTodaySummary('heart_rate')) as Map<String, dynamic>;
      if ((m['count'] as num? ?? 0) <= 0) return false;
      _todayAvgHr = (m['avg'] as num?)?.round() ?? 0;
      _todayMinHr = (m['min'] as num?)?.toInt() ?? 0;
      _todayMaxHr = (m['max'] as num?)?.toInt() ?? 0;
      notifyListeners();
      return true;
    } catch (_) { return false; }
  }

  Future<bool> _refreshSpo2FromLocal() async {
    try {
      final m = jsonDecode(await _ble.getTodaySummary('spo2')) as Map<String, dynamic>;
      if ((m['count'] as num? ?? 0) <= 0) return false;
      _todayAvgSpo2 = (m['avg'] as num?)?.round() ?? 0;
      _todayMinSpo2 = (m['min'] as num?)?.toInt() ?? 0;
      _todayMaxSpo2 = (m['max'] as num?)?.toInt() ?? 0;
      notifyListeners();
      return true;
    } catch (_) { return false; }
  }

  Future<bool> _refreshStressFromLocal() async {
    try {
      final m = jsonDecode(await _ble.getLatestReading('stress'));
      if (m is! Map<String, dynamic>) return false;
      _latestStressValue = (m['value'] as num?)?.toInt() ?? 0;
      try {
        final summary = jsonDecode(await _ble.getTodaySummary('stress')) as Map<String, dynamic>;
        if ((summary['count'] as num? ?? 0) > 0) {
          _todayAvgStress = (summary['avg'] as num?)?.round() ?? 0;
          _todayMinStress = (summary['min'] as num?)?.toInt() ?? 0;
          _todayMaxStress = (summary['max'] as num?)?.toInt() ?? 0;
        }
      } catch (_) {}
      notifyListeners();
      return true;
    } catch (_) { return false; }
  }

  Future<bool> _refreshBpFromLocal() async {
    try {
      final m = jsonDecode(await _ble.getLatestReading('blood_pressure'));
      if (m is! Map<String, dynamic>) return false;
      _latestBpSbp = (m['systolic'] as num?)?.toInt() ?? 0;
      _latestBpDbp = (m['diastolic'] as num?)?.toInt() ?? 0;
      notifyListeners();
      return true;
    } catch (_) { return false; }
  }

  Future<bool> _refreshStepsFromLocal() async {
    try {
      final m = jsonDecode(await _ble.getStepsToday());
      if (m is! Map<String, dynamic>) return false;
      _todaySteps     = (m['steps'] as num?)?.toInt() ?? 0;
      _todayCalories  = (m['caloriesKcal'] as num?)?.toInt() ?? 0;
      _todayDistanceM = (m['distanceM'] as num?)?.toDouble() ?? 0.0;
      notifyListeners();
      return true;
    } catch (_) { return false; }
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

  // HR/SpO2/Steps/Stress/BP are no longer acquired here — the native background
  // MeasurementLoopManager now continuously owns those (see _refresh*FromLocal above).
  // This only covers the vitals still fetched via passive "ask the ring what it already
  // recorded" calls: HRV and Temperature (their one-click loop entries stay disabled
  // until separately fixed), plus Sleep (out of scope for this pipeline).
  Future<void> syncAllFromRing() async {
    if (_isSyncing || !_isConnected) return;
    final myGen = ++_syncGen;
    bool alive() => _syncGen == myGen;

    _isSyncing    = true;
    _syncProgress = 0.0;
    _syncStep     = 'HRV';
    notifyListeners();

    const kTimeout = Duration(seconds: 8);

    try {
      // 1. HRV (0% → 33%)
      try {
        final json = await _ble.getTodayHrv().timeout(kTimeout);
        _parseAndSaveHrv(json);
      } catch (_) {}
      if (!alive()) return;
      _syncProgress = 0.33; _syncStep = 'Sleep'; notifyListeners();

      // 2. Sleep (33% → 66%)
      try {
        final json = await _ble.getTodaySleep().timeout(kTimeout);
        _parseAndSaveSleep(json);
      } catch (_) {}
      if (!alive()) return;
      _syncProgress = 0.66; _syncStep = 'Temperature'; notifyListeners();

      // 3. Temperature (66% → 100%) — use syncAutoTemperature to fetch from ring
      try {
        final json = await _ble.syncAutoTemperature().timeout(const Duration(seconds: 15));
        _parseAndSaveTemp(json);
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

  void _parseAndSaveTemp(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      double latestVal = 0.0;
      DateTime? latestTime;

      if (decoded is List && decoded.isNotEmpty) {
        // TemperatureOnceEntity list: [{mTime, mValue}, ...]
        for (final item in decoded) {
          final m = item as Map<String, dynamic>;
          final ts = (m['mTime'] as num?)?.toInt() ?? (m['a'] as num?)?.toInt();
          var val = (m['mValue'] as num?)?.toDouble() ?? (m['b'] as num?)?.toDouble();
          if (ts == null || val == null || val <= 0) continue;
          if (val > 100) val /= 10;
          final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000).toLocal();
          if (latestTime == null || dt.isAfter(latestTime)) {
            latestTime = dt;
            latestVal = val;
          }
        }
      } else if (decoded is Map<String, dynamic>) {
        // TemperatureEntity: interval array
        final rawVals = (decoded['mValues'] as List<dynamic>?)
            ?? (decoded['d'] as List<dynamic>?);
        if (rawVals != null) {
          for (final raw in rawVals.reversed) {
            var v = (raw as num).toDouble();
            if (v <= 0) continue;
            if (v > 100) v /= 10;
            latestVal = v;
            break;
          }
        }
      }

      if (latestVal <= 0) return;
      _latestTempC = latestVal;
      notifyListeners();

      final user = SupabaseService.currentUser;
      if (user != null) {
        SupabaseService.insertTemp(
          userId: user.id,
          measuredAt: latestTime ?? DateTime.now(),
          valueC: latestVal,
          source: 'auto',
        ).catchError((_) {});
      }
    } catch (_) {}
  }

  // ── DB save helpers ───────────────────────────────────────────────────────

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

  Future<void> _loadLatestTempFromSupabase() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return;
      final data = await SupabaseService.getLatestTemp(user.id);
      if (data != null) {
        final v = (data['value_c'] as num? ?? 0).toDouble();
        if (v > 0) {
          _latestTempC = v;
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  // ── Steps refresh (also called from StepsScreen for pull-to-refresh) ──────
  // Steps are now captured every measurement cycle by the native loop and stored
  // locally — this just re-reads that local snapshot rather than re-fetching the
  // ring/upserting Supabase itself (the native SupabaseSyncManager owns that now).
  Future<void> syncTodayStepsFromRing() async {
    if (_syncingSteps) return;
    _syncingSteps = true;
    notifyListeners();
    await _refreshStepsFromLocal();
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

  // This is the "Unbind" action (Settings screen) — it must forget the device, not just
  // drop the live connection. Previously it left device_name/device_address in
  // SharedPreferences untouched, so BleConnectionService's native 8s reconnect loop (which
  // reads that same prefs key directly, independent of Dart/login state) would just
  // reconnect to the "unbound" ring again moments later — including popping Android's
  // system BLE pairing dialog unprompted, before the user even reaches the login screen.
  Future<void> disconnect() async {
    _cancelSync();
    await _ble.disconnect();
    _isConnected    = false;
    _battery        = -1;
    _deviceName     = '';
    _deviceAddress  = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('device_name');
    await prefs.remove('device_address');
    notifyListeners();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }
}
