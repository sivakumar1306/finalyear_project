import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ble_service.dart';
import '../services/goal_prefs.dart';
import '../services/health_connect_service.dart';
import '../services/notification_prefs.dart';
import '../services/supabase_service.dart';

class ScannedDevice {
  final String name;
  final String address;
  final int rssi;
  ScannedDevice({
    required this.name,
    required this.address,
    required this.rssi,
  });
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
  int _todaySleepScore = 0;
  int _todaySleepDeepSecs = 0;
  int _todaySleepLightSecs = 0;
  int _todaySleepRemSecs = 0;

  // Temperature state
  double _latestTempC = 0.0;

  // Background ring sync state
  bool _isSyncing = false;
  String _syncStep = '';
  double _syncProgress = 0.0;
  int _syncGen = 0; // incremented to cancel a stale in-progress sync

  // Delay (seconds) before issuing SDK commands after a connection event.
  int _connectDelaySeconds = 1;

  // Completed when native's "bindReady" event arrives for the current connection —
  // signals the bind handshake (see BlePlugin.kt sendBindSuccessWithRetry) has finished
  // (confirmed or gave up retrying), so it's now safe to issue heavier traffic like the
  // sleep large-data sync. Firing that sync while bind was still in flight collided with
  // it and made the native SDK conclude the device was unreachable, self-unbind, and
  // loop forever without ever completing pairing.
  Completer<void>? _bindReadyCompleter;

  // Set right before every connect() attempt and *not* cleared on timeout/failure —
  // so that if native later succeeds after our own connect() Future has already timed
  // out (e.g. a bind/rebond cycle that legitimately runs past CONNECT_TIMEOUT_MS), the
  // later "connectionState:true" event in _listenEvents() still knows which device to
  // persist. Without this, Home's "haven't bound a device yet" check (which gates on
  // deviceAddress, not isConnected) stays stuck even though the ring is really connected.
  String? _pendingDeviceName;
  String? _pendingDeviceAddress;

  // Fall-prediction banner (client demo) — set when a prediction notification tap
  // opens/resumes the app; Home screen shows the banner until "Take action"/"ignore".
  bool _showFallPredictionBanner = false;
  int _fallPredictionHr = 0;
  String _fallPredictionTier = 'low';

  // Edge-tracking for user-configurable health alerts (Select Notifications screen):
  // which alert keys are currently "active" (condition still true), so a notification
  // fires once per episode rather than on every single reading while it stays elevated.
  final Set<String> _activeAlerts = {};

  // Emergency SMS auto-send countdown (native EmergencySmsSender) — polled while active.
  bool _emergencySmsActive = false;
  int _emergencySmsSecondsRemaining = 0;
  String _emergencySmsReason = '';
  bool _emergencySmsHasPermission = true;
  int _emergencySmsLastSentCount = 0;
  String? _emergencySmsLastError;
  Timer? _emergencySmsPollTimer;

  // Ring camera / photo control — broadcasts native "cameraShutter" events
  // ("capture" | "exit") so a camera screen can react without owning its own
  // EventChannel subscription. See BlePlugin.kt's takePicture()/exitCameraMode().
  final StreamController<String> _cameraShutterController =
      StreamController<String>.broadcast();
  Stream<String> get cameraShutterEvents => _cameraShutterController.stream;

  // Gesture Controls (PalmScreenReq) — ring-side wrist-flip/palm-screen wake.
  bool _gestureEnabled = false;
  bool get gestureEnabled => _gestureEnabled;

  String? _lastError;
  String? get lastError => _lastError;

  void _recordError(Object e, [StackTrace? st, String? context]) {
    final label = context == null ? '$e' : '$context: $e';
    _lastError = label;
    debugPrint('BleProvider $label');
    if (st != null) debugPrint('$st');
  }

  void clearLastError() {
    _lastError = null;
  }

  // Low battery prompt — phone-side only (SharedPreferences), driven by the
  // ring's proactive battery push (see BlePlugin.kt's "batteryPush" event,
  // native dataType 0x0c). Edge-triggered like the other _maybeAlert() calls
  // below, so it fires once per drop below threshold rather than repeatedly.
  static const _kLowBatteryPromptKey = 'low_battery_prompt_enabled';
  static const _kLowBatteryThreshold = 15;
  bool _lowBatteryPromptEnabled = false;
  bool get lowBatteryPromptEnabled => _lowBatteryPromptEnabled;

  // ── Getters ───────────────────────────────────────────────────────────────

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
  List<int> get todayStepsByInterval =>
      List.unmodifiable(_todayStepsByInterval);

  int get todayAvgHr => _todayAvgHr;
  int get todayMinHr => _todayMinHr;
  int get todayMaxHr => _todayMaxHr;

  int get todayAvgSpo2 => _todayAvgSpo2;
  int get todayMinSpo2 => _todayMinSpo2;
  int get todayMaxSpo2 => _todayMaxSpo2;

  int get latestBpSbp => _latestBpSbp;
  int get latestBpDbp => _latestBpDbp;
  int get latestStressValue => _latestStressValue;
  int get todayAvgStress => _todayAvgStress;
  int get todayMinStress => _todayMinStress;
  int get todayMaxStress => _todayMaxStress;
  int get todayAvgHrv => _todayAvgHrv;

  int get todaySleepDuration => _todaySleepDuration;
  int get todaySleepScore => _todaySleepScore;
  int get todaySleepDeepSecs => _todaySleepDeepSecs;
  int get todaySleepLightSecs => _todaySleepLightSecs;
  int get todaySleepRemSecs => _todaySleepRemSecs;

  double get latestTempC => _latestTempC;

  bool get isSyncing => _isSyncing;
  String get syncStep => _syncStep;
  double get syncProgress => _syncProgress;

  bool get showFallPredictionBanner => _showFallPredictionBanner;
  int get fallPredictionHr => _fallPredictionHr;
  String get fallPredictionTier => _fallPredictionTier;

  bool get emergencySmsActive => _emergencySmsActive;
  int get emergencySmsSecondsRemaining => _emergencySmsSecondsRemaining;
  String get emergencySmsReason => _emergencySmsReason;
  bool get emergencySmsHasPermission => _emergencySmsHasPermission;
  int get emergencySmsLastSentCount => _emergencySmsLastSentCount;
  String? get emergencySmsLastError => _emergencySmsLastError;

  /// When true, a corroborated fall *detection* immediately calls the first emergency contact.
  bool _autoCallOnFallEnabled = false;
  bool _autoCallOnFallHasPermission = false;
  bool _autoCallOnFallPredictionEnabled = false;

  bool get autoCallOnFallEnabled => _autoCallOnFallEnabled;
  bool get autoCallOnFallHasPermission => _autoCallOnFallHasPermission;
  bool get autoCallOnFallPredictionEnabled => _autoCallOnFallPredictionEnabled;

  // ── Manual update methods (called by individual screens) ──────────────────

  void updateStepsData(
    int steps,
    int calories,
    double distanceM,
    List<int> intervals,
  ) {
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

  void updateBpLatest(int sbp, int dbp) {
    _latestBpSbp = sbp;
    _latestBpDbp = dbp;
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
    _todaySleepScore = score;
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
    // HRV/Temperature are now also produced by the native measurement loop; these
    // Supabase reads only cover data recorded before the loop started collecting them.
    _loadTodayHrvFromSupabase();
    _loadTodaySleepFromSupabase();
    _loadTodayTempFromSupabase();
    syncEmergencyContactsFromCloud().then((_) => _syncContactsToCloud());
    loadLowBatteryPromptSetting();
  }

  // ── Event listener ────────────────────────────────────────────────────────

  void _listenEvents() {
    _eventSub = _ble.events.listen(
      (event) {
        try {
          if (!hasListeners) return;
          final type = event['type']?.toString();
          if (type == null || type.isEmpty) return;
          final rawData = event['data'];
          final data = rawData is Map
              ? Map<String, dynamic>.from(rawData)
              : <String, dynamic>{};
          switch (type) {
            case 'connectionState':
              _isConnected = data['connected'] as bool? ?? false;
              if (_isConnected) {
                if (_deviceAddress.isEmpty && _pendingDeviceAddress != null) {
                  // Native connected successfully after our own connect() call had
                  // already timed out and given up (see connect()'s doc comment) — the
                  // connection is real, we just never recorded which device it was.
                  // Persist it now so Home's deviceAddress-gated UI reflects reality.
                  _deviceName = _pendingDeviceName ?? _deviceName;
                  _deviceAddress = _pendingDeviceAddress!;
                  SharedPreferences.getInstance().then((prefs) {
                    prefs.setString('device_name', _deviceName);
                    prefs.setString('device_address', _deviceAddress);
                  });
                }
                _bindReadyCompleter = Completer<void>();
                _onConnected(delay: _connectDelaySeconds);
              } else {
                // Retain last known battery level on temporary connection drops
              }
              notifyListeners();
              break;
            case 'bindReady':
              final completer = _bindReadyCompleter;
              if (completer != null && !completer.isCompleted) {
                completer.complete();
              }
              break;
            case 'scanResult':
              final dev = ScannedDevice(
                name: data['name'] as String? ?? '',
                address: data['address'] as String? ?? '',
                rssi: (data['rssi'] as num?)?.toInt() ?? -100,
              );
              final idx = _scannedDevices.indexWhere(
                (d) => d.address == dev.address,
              );
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
            case 'cameraShutter':
              if (!_cameraShutterController.isClosed) {
                _cameraShutterController.add(data['action'] as String? ?? '');
              }
              break;
            case 'batteryPush':
              _onBatteryPushEvent(data);
              break;
          }
        } catch (e, st) {
          debugPrint('[BleProvider] event handler error: $e\n$st');
        }
      },
      onError: (Object e, StackTrace st) {
        debugPrint('[BleProvider] event stream error: $e\n$st');
      },
    );
  }

  // ── Ring camera / photo control ───────────────────────────────────────────
  //
  // Enters the ring's camera UI (and starts native's keep-screen-on loop).
  // Listen on [cameraShutterEvents] for "capture" (ring's shutter button/gesture
  // was used — trigger the phone's own camera capture) or "exit" (the ring left
  // camera mode on its own — close the phone's camera screen).
  Future<bool> enterRingCameraMode() => _ble.takePicture();

  /// Tells the ring to exit its camera UI and stops the native keep-alive loop.
  /// Always call this when the camera screen is closed/disposed.
  Future<bool> exitRingCameraMode() => _ble.exitCameraMode();

  // ── Gesture Controls (PalmScreenReq) ──────────────────────────────────────

  Future<void> loadGestureSetting() async {
    try {
      final json = await _ble.getGestureSetting();
      final decoded = jsonDecode(json);
      if (decoded is Map) {
        _gestureEnabled = decoded['enabled'] == true;
        notifyListeners();
      }
    } catch (e, st) {
      _recordError(e, st);
    }
  }

  /// Writes to the ring (PalmScreenReq.getWriteInstance). [isLeft] mirrors
  /// whichever hand the ring is worn on if you have that elsewhere; defaults
  /// to true (left) to match the SDK sample.
  Future<void> setGestureEnabled(bool enabled, {bool isLeft = true}) async {
    try {
      final ok = await _ble.setGestureSetting(enable: enabled, isLeft: isLeft);
      if (ok) {
        _gestureEnabled = enabled;
        notifyListeners();
      }
    } catch (e, st) {
      _recordError(e, st);
    }
  }

  /// Sends factory reset command to the ring and disconnects upon success.
  Future<bool> factoryReset() async {
    try {
      final ok = await _ble.factoryReset();
      if (ok) {
        await disconnect();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Sends power off command to shut down the ring and disconnects upon success.
  Future<bool> shutDownRing() async {
    try {
      final ok = await _ble.shutDownRing();
      if (ok) {
        await disconnect();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  // ── Low battery prompt (phone-side notification) ──────────────────────────
  //
  // Purely local — no ring-side command involved. Driven by the ring's own
  // proactive battery push (dataType 0x0c, forwarded here as "batteryPush"),
  // so it fires immediately when the ring reports its level rather than
  // waiting on the next getBattery() poll.

  Future<void> loadLowBatteryPromptSetting() async {
    final prefs = await SharedPreferences.getInstance();
    _lowBatteryPromptEnabled = prefs.getBool(_kLowBatteryPromptKey) ?? false;
    notifyListeners();
  }

  Future<void> setLowBatteryPromptEnabled(bool enabled) async {
    _lowBatteryPromptEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLowBatteryPromptKey, enabled);

    if (enabled && _battery > 0 && _battery <= _kLowBatteryThreshold) {
      _maybeAlert(
        'Low Battery Prompt',
        true,
        title: 'Ring Battery Low',
        message: 'Your ring is at $_battery% battery.',
        vital: 'heart_rate',
      );
    } else if (!enabled) {
      _activeAlerts.remove('Low Battery Prompt');
    }
    notifyListeners();
  }

  void _onBatteryPushEvent(Map<String, dynamic> data) {
    final percent = (data['batteryPercent'] as num?)?.toInt() ?? -1;
    final charging = data['charging'] as bool? ?? false;
    if (percent < 0) return;
    _battery = percent;
    SharedPreferences.getInstance().then((prefs) => prefs.setInt('last_battery', percent));
    notifyListeners();
    if (!charging) {
      _maybeAlert(
        'Low Battery Prompt',
        _lowBatteryPromptEnabled && percent <= _kLowBatteryThreshold,
        title: 'Ring Battery Low',
        message: 'Your ring is at $percent% battery.',
        vital: 'heart_rate',
      );
    } else {
      // Charging again — clear the edge so the prompt can fire once more
      // next time the ring drops below the threshold.
      _activeAlerts.remove('Low Battery Prompt');
    }
  }

  // ── Local-DB-backed vitals (continuous background measurement loop) ──────
  //
  // HR/SpO2/Stress/BP/Steps are now acquired continuously by the native
  // MeasurementLoopManager and stored in local Room, independent of whether
  // this screen/provider is alive. These helpers read that local DB (the
  // single source of truth) rather than re-triggering ring measurements.

  void _onNewReadingEvent(Map<String, dynamic> data) {
    switch (data['vital'] as String?) {
      case 'HEART_RATE':
        _refreshHrFromLocal();
        unawaited(_pushToHealthConnect('heart_rate'));
        break;
      case 'SPO2':
        _refreshSpo2FromLocal();
        unawaited(_pushToHealthConnect('spo2'));
        break;
      case 'STRESS':
        _refreshStressFromLocal();
        break;
      case 'BLOOD_PRESSURE':
        _refreshBpFromLocal();
        unawaited(_pushToHealthConnect('blood_pressure'));
        break;
      case 'STEPS':
        _refreshStepsFromLocal();
        unawaited(_pushToHealthConnect('steps'));
        break;
      case 'TEMPERATURE':
        _refreshTempFromLocal();
        unawaited(_pushToHealthConnect('temperature'));
        break;
      case 'HRV':
      case 'hrv':
        _refreshHrvFromLocal();
        break;
    }
  }

  /// Best-effort two-way sync: forwards the latest Room reading of [vital] to
  /// Google Health Connect (silently no-ops when not connected/authorized).
  Future<void> _pushToHealthConnect(String vital) async {
    try {
      final hc = HealthConnectService.instance;
      final m = jsonDecode(await _ble.getLatestReading(vital));
      if (m is! Map<String, dynamic>) return;
      final at = DateTime.fromMillisecondsSinceEpoch(
        (m['measuredAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      );
      switch (vital) {
        case 'heart_rate':
          final v = (m['valueBpm'] as num?)?.toInt() ?? 0;
          if (v > 0) await hc.tryWriteHeartRate(v, at);
        case 'spo2':
          final v = (m['valuePct'] as num?)?.toInt() ?? 0;
          if (v > 0) await hc.tryWriteBloodOxygen(v, at);
        case 'blood_pressure':
          final s = (m['systolic'] as num?)?.toInt() ?? 0;
          final d = (m['diastolic'] as num?)?.toInt() ?? 0;
          if (s > 0 && d > 0) await hc.tryWriteBloodPressure(s, d, at);
        case 'temperature':
          final v = (m['valueC'] as num?)?.toDouble() ?? 0.0;
          if (v > 0) await hc.tryWriteTemperature(v, at);
        case 'steps':
          final v = (m['steps'] as num?)?.toInt() ?? 0;
          if (v > 0) await hc.tryWriteSteps(v, at);
      }
    } catch (e, st) {
      _recordError(e, st);
    }
  }

  // ── Health-event alerts (Select Notifications screen) ────────────────────
  //
  // Edge-triggered: fires at most once per episode (condition transitioning
  // from not-crossed to crossed), gated by whether the user enabled that
  // specific alert key. See NotificationPrefs / postHealthAlert (BlePlugin.kt
  // -> AlertNotifier.notifyAnomaly).

  Future<void> _maybeAlert(
    String key,
    bool condition, {
    required String title,
    required String message,
    required String vital,
  }) async {
    final wasActive = _activeAlerts.contains(key);
    if (!condition) {
      _activeAlerts.remove(key);
      return;
    }
    if (wasActive) return; // already alerted for this episode
    _activeAlerts.add(key);
    if (await NotificationPrefs.isEnabled(key)) {
      try {
        await _ble.postHealthAlert(
          title: title,
          message: message,
          vital: vital,
        );
      } catch (e, st) {
        _recordError(e, st);
      }
    }
  }

  /// Refreshes latest vitals readings from local Room DB on demand.
  Future<void> refreshVitalsFromLocal() => _loadTodayVitalsFromLocal();

  /// Dev/testing only — seeds the local DB with [hoursBack] hours of plausible
  /// readings (no ring connection needed) and refreshes the vitals shown in the
  /// app, so data survives a reinstall's data wipe without needing to re-pair.
  Future<void> seedDemoData({int hoursBack = 3}) async {
    await _ble.seedDemoData(hoursBack: hoursBack);
    await _loadTodayVitalsFromLocal();
  }

  /// Dev/testing only — fires the real fall-alert notification pipeline on demand.
  Future<void> simulateFallEvent() => _ble.simulateFallEvent();

  /// Latest score computed by the native FallRiskAnalyzer, or null if it hasn't
  /// logged anything yet (e.g. no vital reading has been saved since install).
  Future<Map<String, dynamic>?> getFallRiskScore() async {
    final json = await _ble.getFallRiskScore();
    final decoded = jsonDecode(json);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  /// Focus/Prayer sessions overlapping today (local midnight to now) — each entry has
  /// `mode`, `startedAt` (ms), and `endedAt` (ms, or null if the mode is still active).
  Future<List<Map<String, dynamic>>> getPhoneModeSessionsToday() async {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final json = await _ble.getPhoneModeSessions(
      fromMs: dayStart.millisecondsSinceEpoch,
      toMs: now.millisecondsSinceEpoch,
    );
    final decoded = jsonDecode(json);
    if (decoded is! List) return [];
    return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Recent candidate fall events logged by the native FallMotionDetector.
  Future<List<Map<String, dynamic>>> getFallEvents({int limit = 20}) async {
    final json = await _ble.getFallEvents(limit: limit);
    final decoded = jsonDecode(json);
    if (decoded is! List) return [];
    return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Dev/testing only — posts a real vital reading through the exact same event path a
  /// genuine ring reading takes, so FallRiskAnalyzer can be verified end-to-end.
  Future<void> clearMockVitals() => _ble.clearMockVitals();

  Future<void> simulateFallRiskTrigger() => _ble.simulateFallRiskTrigger();

  /// Client-demo only — see FallPredictionNotifier.kt / BlePlugin.simulateFallPrediction.
  Future<void> simulateFallPrediction() => _ble.simulateFallPrediction();

  /// Call on cold start (Home initState) and on app resume — picks up a pending
  /// fall prediction whether the app was opened via the notification or directly
  /// from the launcher. Pending is persisted natively until [dismissFallPredictionBanner].
  Future<void> checkPendingFallPrediction() async {
    final json = await _ble.consumeFallPredictionFlag();
    final decoded = jsonDecode(json);
    if (decoded is! Map || decoded['pending'] != true) {
      // Prediction was cleared (or never fired) — hide banner if still showing.
      if (_showFallPredictionBanner) {
        _showFallPredictionBanner = false;
        _fallPredictionTier = 'low';
        notifyListeners();
      }
      return;
    }
    // Already showing with same state — avoid redundant rebuilds on every resume.
    final hr = (decoded['hr'] as num?)?.toInt() ?? 122;
    if (_showFallPredictionBanner && _fallPredictionHr == hr) return;

    _showFallPredictionBanner = true;
    _fallPredictionHr = hr;

    // Check latest risk log score to determine tier matching the existing _tierFromScore logic
    final risk = await getFallRiskScore();
    if (risk != null) {
      final score = (risk['score'] as num?)?.toInt() ?? 0;
      if (score >= 55) {
        _fallPredictionTier = 'high';
      } else if (score >= 25) {
        _fallPredictionTier = 'medium';
      } else {
        _fallPredictionTier = 'low';
      }
    } else {
      _fallPredictionTier = 'high'; // fallback
    }

    notifyListeners();
  }

  Future<void> dismissFallPredictionBanner() async {
    _showFallPredictionBanner = false;
    _fallPredictionTier = 'low';
    notifyListeners();
    // Clear native SharedPreferences so reopening the app does not resurrect the alert.
    // Also cancel any pending auto-SMS — user tapped ignore / I'm okay.
    await Future.wait([
      _ble.clearFallPredictionFlag(),
      _ble.cancelEmergencySms(),
    ]);
    await refreshEmergencySmsStatus();
  }

  /// Poll native countdown state. Starts a 1s timer while a countdown is active.
  Future<void> refreshEmergencySmsStatus() async {
    try {
      final json = await _ble.getEmergencySmsStatus();
      final decoded = jsonDecode(json);
      if (decoded is! Map) return;
      final active = decoded['active'] == true;
      final remaining = (decoded['secondsRemaining'] as num?)?.toInt() ?? 0;
      final reason = decoded['reason'] as String? ?? '';
      final hasPerm = decoded['hasPermission'] != false;
      final lastCount = (decoded['lastSentCount'] as num?)?.toInt() ?? 0;
      final lastError = decoded['lastError'] as String?;

      final changed =
          active != _emergencySmsActive ||
          remaining != _emergencySmsSecondsRemaining ||
          reason != _emergencySmsReason ||
          hasPerm != _emergencySmsHasPermission ||
          lastCount != _emergencySmsLastSentCount ||
          lastError != _emergencySmsLastError;

      _emergencySmsActive = active;
      _emergencySmsSecondsRemaining = remaining;
      _emergencySmsReason = reason;
      _emergencySmsHasPermission = hasPerm;
      _emergencySmsLastSentCount = lastCount;
      _emergencySmsLastError = lastError;

      if (active) {
        _ensureEmergencySmsPoll();
      } else {
        _stopEmergencySmsPoll();
      }
      if (changed) notifyListeners();
    } catch (e) {
      debugPrint('[FallDetection] SMS status failed: $e');
    }
  }

  void _ensureEmergencySmsPoll() {
    if (_emergencySmsPollTimer?.isActive == true) return;
    _emergencySmsPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      refreshEmergencySmsStatus();
    });
  }

  void _stopEmergencySmsPoll() {
    _emergencySmsPollTimer?.cancel();
    _emergencySmsPollTimer = null;
  }

  /// Cancel auto-SMS countdown and clear the fall-prediction banner.
  Future<void> cancelEmergencySms() async {
    await _ble.cancelEmergencySms();
    _showFallPredictionBanner = false;
    _fallPredictionTier = 'low';
    await refreshEmergencySmsStatus();
    notifyListeners();
  }

  /// Immediate SmsManager send to **all** emergency contacts (manual Message action).
  Future<Map<String, dynamic>> sendEmergencySms({String? message}) async {
    final json = await _ble.sendEmergencySms(message: message);
    final decoded = jsonDecode(json);
    await refreshEmergencySmsStatus();
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return {'ok': false, 'sentCount': 0, 'error': 'invalid response'};
  }

  Future<bool> placeEmergencyCall(String phone) async {
    try {
      final ok = await _ble.placeEmergencyCall(phone);
      return ok;
    } catch (e) {
      debugPrint('[FallDetection] Auto-call failed: $e');
      return false;
    }
  }

  Future<void> loadAutoCallOnFallSetting() async {
    try {
      final json = await _ble.getAutoCallOnFallEnabled();
      final decoded = jsonDecode(json);
      if (decoded is! Map) return;
      _autoCallOnFallEnabled = decoded['enabled'] == true;
      _autoCallOnFallHasPermission = decoded['hasPermission'] == true;
      final prefs = await SharedPreferences.getInstance();
      _autoCallOnFallPredictionEnabled =
          prefs.getBool('autoCallOnFallPrediction') ?? false;
      notifyListeners();
    } catch (e) {
      debugPrint('[FallDetection] load auto-call setting failed: $e');
    }
  }

  /// Persist toggle natively so the background fall detector can read it.
  Future<void> setAutoCallOnFallEnabled(bool enabled) async {
    try {
      final json = await _ble.setAutoCallOnFallEnabled(enabled);
      final decoded = jsonDecode(json);
      if (decoded is Map) {
        _autoCallOnFallEnabled = decoded['enabled'] == true;
        _autoCallOnFallHasPermission = decoded['hasPermission'] == true;
      } else {
        _autoCallOnFallEnabled = enabled;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[FallDetection] set auto-call setting failed: $e');
    }
  }

  Future<void> setAutoCallOnFallPredictionEnabled(bool enabled) async {
    _autoCallOnFallPredictionEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoCallOnFallPrediction', enabled);
    notifyListeners();
  }

  /// Emergency contacts — persisted natively (Room), not Flutter widget state.
  Future<List<Map<String, dynamic>>> getEmergencyContacts() async {
    final json = await _ble.getEmergencyContacts();
    final decoded = jsonDecode(json);
    if (decoded is! List) return [];
    return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // Local Room stays the source of truth (works with no network/no login); every
  // write is mirrored to Supabase afterward on a best-effort basis via
  // _syncContactsToCloud()/_deleteContactFromCloud() so the same contacts show up
  // on the Profile screen (and any other signed-in device later) too.

  Future<void> addEmergencyContact(String name, String phone) async {
    await _ble.addEmergencyContact(name, phone);
    await _syncContactsToCloud();
  }

  Future<void> updateEmergencyContact(int id, String name, String phone) async {
    await _ble.updateEmergencyContact(id, name, phone);
    await _syncContactsToCloud();
  }

  Future<void> deleteEmergencyContact(int id) async {
    await _ble.deleteEmergencyContact(id);
    await _deleteContactFromCloud(id);
  }

  Future<void> syncEmergencyContactsFromCloud() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      final cloudContacts = await SupabaseService.getEmergencyContactsCloud(user.id);
      if (cloudContacts.isEmpty) return;

      final localRows = await getEmergencyContacts();
      final localKeys = localRows.map((r) => '${r['name']}_${r['phone']}').toSet();

      for (final c in cloudContacts) {
        final name = c['name'] as String? ?? '';
        final phone = c['phone'] as String? ?? '';
        if (name.isNotEmpty && phone.isNotEmpty) {
          final key = '${name}_$phone';
          if (!localKeys.contains(key)) {
            await _ble.addEmergencyContact(name, phone);
            localKeys.add(key);
          }
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[BleProvider] emergency contact cloud restore failed: $e');
    }
  }

  Future<void> _syncContactsToCloud() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      final rows = await getEmergencyContacts();
      for (final r in rows) {
        final id = (r['id'] as num?)?.toInt();
        if (id == null) continue;
        await SupabaseService.upsertEmergencyContact(
          userId: user.id,
          localId: id,
          name: r['name'] as String? ?? '',
          phone: r['phone'] as String? ?? '',
        );
      }
    } catch (e) {
      debugPrint('[BleProvider] emergency contact cloud sync failed: $e');
    }
  }

  Future<void> _deleteContactFromCloud(int localId) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.deleteEmergencyContactByLocalId(
        userId: user.id,
        localId: localId,
      );
    } catch (e) {
      debugPrint('[BleProvider] emergency contact cloud delete failed: $e');
    }
  }

  bool _notifyBatching = false;
  bool _notifyQueued = false;

  bool _microtaskNotifyScheduled = false;

  @override
  void notifyListeners() {
    if (!hasListeners) return;
    if (_notifyBatching) {
      _notifyQueued = true;
      return;
    }
    if (_microtaskNotifyScheduled) return;
    _microtaskNotifyScheduled = true;
    scheduleMicrotask(() {
      _microtaskNotifyScheduled = false;
      if (!hasListeners) return;
      if (_notifyBatching) {
        _notifyQueued = true;
        return;
      }
      try {
        super.notifyListeners();
      } catch (e) {
        debugPrint('[BleProvider] notifyListeners failed: $e');
      }
    });
  }

  void _beginNotifyBatch() {
    _notifyBatching = true;
    _notifyQueued = false;
  }

  void _endNotifyBatch() {
    _notifyBatching = false;
    if (_notifyQueued) {
      _notifyQueued = false;
      if (_microtaskNotifyScheduled) return;
      _microtaskNotifyScheduled = true;
      scheduleMicrotask(() {
        _microtaskNotifyScheduled = false;
        if (!hasListeners) return;
        try {
          super.notifyListeners();
        } catch (e) {
          debugPrint('[BleProvider] notifyListeners failed: $e');
        }
      });
    }
  }

  Future<void> _loadTodayVitalsFromLocal() async {
    _beginNotifyBatch();
    try {
      await Future.wait([
        _refreshHrFromLocal().then(
          (ok) => ok ? null : _loadTodayHrFromSupabase(),
        ),
        _refreshSpo2FromLocal().then(
          (ok) => ok ? null : _loadTodaySpo2FromSupabase(),
        ),
        _refreshStressFromLocal().then(
          (ok) => ok ? null : _loadTodayStressFromSupabase(),
        ),
        _refreshBpFromLocal().then(
          (ok) => ok ? null : _loadTodayBpFromSupabase(),
        ),
        _refreshStepsFromLocal().then(
          (ok) => ok ? null : _loadTodayFromSupabase(),
        ),
        _refreshTempFromLocal().then(
          (ok) => ok ? null : _loadTodayTempFromSupabase(),
        ),
        _refreshHrvFromLocal().then(
          (ok) => ok ? null : _loadTodayHrvFromSupabase(),
        ),
      ]);
    } finally {
      _endNotifyBatch();
    }
  }

  static const _goalCacheTtl = Duration(seconds: 30);
  GoalTargets? _cachedGoalTargets;
  DateTime? _cachedGoalAt;

  /// Steps/calories goal with a short TTL — avoids a SharedPreferences disk
  /// read inside the steps measurement handler (hot path).
  Future<GoalTargets> _loadCachedGoal() async {
    final now = DateTime.now();
    if (_cachedGoalTargets == null ||
        now.difference(_cachedGoalAt!) > _goalCacheTtl) {
      _cachedGoalTargets = await GoalPrefs.load();
      _cachedGoalAt = now;
    }
    return _cachedGoalTargets!;
  }

  Future<bool> _refreshHrFromLocal() async {
    try {
      final m =
          jsonDecode(await _ble.getTodaySummary('heart_rate'))
              as Map<String, dynamic>;
      if ((m['count'] as num? ?? 0) <= 0) return false;
      _todayAvgHr = (m['avg'] as num?)?.round() ?? 0;
      _todayMinHr = (m['min'] as num?)?.toInt() ?? 0;
      _todayMaxHr = (m['max'] as num?)?.toInt() ?? 0;
      notifyListeners();
      final last = (m['lastValue'] as num?)?.toInt() ?? 0;
      if (last > 0) {
        _maybeAlert(
          'High Heart Rate',
          last >= 100,
          title: 'High Heart Rate',
          message: 'Your heart rate just read $last bpm.',
          vital: 'heart_rate',
        );
        _maybeAlert(
          'Low Heart Rate',
          last < 50,
          title: 'Low Heart Rate',
          message: 'Your heart rate just read $last bpm.',
          vital: 'heart_rate',
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _refreshSpo2FromLocal() async {
    try {
      final m =
          jsonDecode(await _ble.getTodaySummary('spo2'))
              as Map<String, dynamic>;
      if ((m['count'] as num? ?? 0) <= 0) return false;
      _todayAvgSpo2 = (m['avg'] as num?)?.round() ?? 0;
      _todayMinSpo2 = (m['min'] as num?)?.toInt() ?? 0;
      _todayMaxSpo2 = (m['max'] as num?)?.toInt() ?? 0;
      notifyListeners();
      final last = (m['lastValue'] as num?)?.toInt() ?? 0;
      if (last > 0) {
        _maybeAlert(
          'High SpO2',
          last >= 99,
          title: 'High Blood Oxygen',
          message: 'Your SpO2 just read $last%.',
          vital: 'spo2',
        );
        _maybeAlert(
          'Low SpO2',
          last < 90,
          title: 'Low Blood Oxygen',
          message: 'Your SpO2 just read $last%.',
          vital: 'spo2',
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _isTodayTimestamp(dynamic msOrIso) {
    if (msOrIso == null) return false;
    DateTime dt;
    if (msOrIso is num) {
      dt = DateTime.fromMillisecondsSinceEpoch(msOrIso.toInt()).toLocal();
    } else if (msOrIso is String) {
      final parsed = DateTime.tryParse(msOrIso);
      if (parsed == null) return false;
      dt = parsed.toLocal();
    } else {
      return false;
    }
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  Future<bool> _refreshStressFromLocal() async {
    try {
      final m = jsonDecode(await _ble.getLatestReading('stress'));
      if (m is! Map<String, dynamic>) return false;
      final ts = m['measuredAt'] ?? m['timestamp'] ?? m['mTime'];
      if (!_isTodayTimestamp(ts)) {
        _latestStressValue = 0;
        _todayAvgStress = 0;
        notifyListeners();
        return false;
      }
      _latestStressValue = (m['value'] as num?)?.toInt() ?? 0;
      try {
        final summary =
            jsonDecode(await _ble.getTodaySummary('stress'))
                as Map<String, dynamic>;
        if ((summary['count'] as num? ?? 0) > 0) {
          _todayAvgStress = (summary['avg'] as num?)?.round() ?? 0;
          _todayMinStress = (summary['min'] as num?)?.toInt() ?? 0;
          _todayMaxStress = (summary['max'] as num?)?.toInt() ?? 0;
        }
      } catch (e, st) {
        _recordError(e, st);
      }
      if (_todayAvgStress <= 0 && _latestStressValue > 0) {
        _todayAvgStress = _latestStressValue;
        _todayMinStress = _latestStressValue;
        _todayMaxStress = _latestStressValue;
      }
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _refreshBpFromLocal() async {
    try {
      final m = jsonDecode(await _ble.getLatestReading('blood_pressure'));
      if (m is! Map<String, dynamic>) return false;
      final ts = m['measuredAt'] ?? m['timestamp'] ?? m['mTime'];
      if (!_isTodayTimestamp(ts)) {
        _latestBpSbp = 0;
        _latestBpDbp = 0;
        notifyListeners();
        return false;
      }
      _latestBpSbp = (m['systolic'] as num?)?.toInt() ?? 0;
      _latestBpDbp = (m['diastolic'] as num?)?.toInt() ?? 0;
      notifyListeners();
      if (_latestBpSbp > 0 && _latestBpDbp > 0) {
        _maybeAlert(
          'High BP',
          _latestBpSbp >= 140 || _latestBpDbp >= 90,
          title: 'High Blood Pressure',
          message: 'Your blood pressure just read $_latestBpSbp/$_latestBpDbp.',
          vital: 'blood_pressure',
        );
        _maybeAlert(
          'Low BP',
          _latestBpSbp < 90 || _latestBpDbp < 60,
          title: 'Low Blood Pressure',
          message: 'Your blood pressure just read $_latestBpSbp/$_latestBpDbp.',
          vital: 'blood_pressure',
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _refreshStepsFromLocal() async {
    try {
      Map<String, dynamic>? m;
      try {
        final summaryJson = await _ble.getTodaySummary('steps');
        final decoded = jsonDecode(summaryJson);
        if (decoded is Map<String, dynamic> &&
            ((decoded['steps'] as num? ?? 0) > 0 ||
                (decoded['count'] as num? ?? 0) > 0)) {
          final ts = decoded['date'] ?? decoded['measuredAt'] ?? decoded['timestamp'];
          if (ts == null || _isTodayTimestamp(ts)) {
            m = decoded;
          }
        }
      } catch (_) {}

      if (m == null) {
        final rawJson = await _ble.getStepsToday();
        final decoded = jsonDecode(rawJson);
        if (decoded is Map<String, dynamic>) {
          final ts = decoded['date'] ?? decoded['measuredAt'] ?? decoded['timestamp'];
          if (ts == null || _isTodayTimestamp(ts)) {
            m = decoded;
          }
        }
      }

      if (m == null) {
        _todaySteps = 0;
        _todayCalories = 0;
        _todayDistanceM = 0.0;
        notifyListeners();
        return false;
      }
      final steps = (m['steps'] as num?)?.toInt() ?? 0;
      final calories = (m['caloriesKcal'] as num?)?.toInt() ?? 0;
      final distanceM = (m['distanceM'] as num?)?.toDouble() ?? 0.0;
      if (steps <= 0 && calories <= 0) {
        _todaySteps = 0;
        _todayCalories = 0;
        _todayDistanceM = 0.0;
        notifyListeners();
        return false;
      }

      _todaySteps = steps;
      _todayCalories = calories;
      _todayDistanceM = distanceM;
      notifyListeners();
      _saveStepsToDb(_todaySteps, _todayCalories, _todayDistanceM);
      final goal = await _loadCachedGoal();
      _maybeAlert(
        'Step count achieved',
        _todaySteps >= goal.steps,
        title: 'Step Goal Reached',
        message: 'You hit your goal of ${goal.steps} steps today!',
        vital: 'steps',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _refreshTempFromLocal() async {
    try {
      final m = jsonDecode(await _ble.getLatestReading('temperature'));
      if (m is! Map<String, dynamic>) return false;
      final ts = m['measuredAt'] ?? m['timestamp'] ?? m['mTime'];
      if (!_isTodayTimestamp(ts)) {
        _latestTempC = 0.0;
        notifyListeners();
        return false;
      }
      final v = (m['valueC'] as num?)?.toDouble() ?? 0.0;
      if (v > 0) {
        _latestTempC = v;
        notifyListeners();
        _maybeAlert(
          'High temperature notification',
          v > 38.0,
          title: 'High Temperature',
          message: 'Your skin temperature just read ${v.toStringAsFixed(1)}°C.',
          vital: 'temperature',
        );
        final user = SupabaseService.currentUser;
        if (user != null) {
          SupabaseService.insertTemp(
            userId: user.id,
            measuredAt: DateTime.fromMillisecondsSinceEpoch(
              (m['measuredAt'] as num?)?.toInt() ??
                  DateTime.now().millisecondsSinceEpoch,
            ),
            valueC: v,
            source: 'auto',
          ).catchError((_) {});
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _refreshHrvFromLocal() async {
    try {
      final m =
          jsonDecode(await _ble.getTodaySummary('hrv'))
              as Map<String, dynamic>;
      if ((m['count'] as num? ?? 0) <= 0) return false;
      _todayAvgHrv = (m['avg'] as num?)?.round() ?? 0;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Device management ─────────────────────────────────────────────────────

  Future<void> _loadSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceName = prefs.getString('device_name') ?? '';
    _deviceAddress = prefs.getString('device_address') ?? '';
    _battery = prefs.getInt('last_battery') ?? -1;
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
    } catch (e, st) {
      _recordError(e, st);
    }
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
    try {
      await _ble.setTime();
    } catch (e, st) {
      _recordError(e, st);
    }
    await refreshBattery();
    await refreshFirmwareVersion();
    await loadGestureSetting();
    // Wait for native's bind handshake to finish before the sleep large-data sync
    // below (syncAllFromRing) — see BlePlugin.kt's "bindReady" event. A 15s timeout
    // is a safety net only (mirrors BlePlugin's own bind-retry budget of
    // INIT_MAX_ATTEMPTS × INIT_RETRY_TIMEOUT_MS = 12s); if bindReady never arrives
    // for some reason, proceed anyway rather than hang sync forever.
    await _waitForBindReady();
    if (_isConnected) syncAllFromRing();
  }

  Future<void> _waitForBindReady() async {
    final completer = _bindReadyCompleter;
    if (completer == null) return;
    try {
      await completer.future.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      debugPrint(
        '[BleProvider] bindReady timed out — proceeding with sync anyway',
      );
    }
  }

  // ── Sync cancellation ─────────────────────────────────────────────────────

  void _cancelSync() {
    if (!_isSyncing) return;
    _syncGen++;
    _isSyncing = false;
    _syncStep = '';
    _syncProgress = 0.0;
    notifyListeners();
  }

  // ── Background ring sync (all metrics sequentially) ───────────────────────

  // HR/SpO2/Steps/Stress/BP are no longer acquired here — the native background
  // MeasurementLoopManager now continuously owns those (see _refresh*FromLocal above).
  // This only covers the vitals still fetched via passive "ask the ring what it already
  // recorded" calls: HRV and Temperature (loop-measured readings are backed by these
  // ring-stored series too, so pulling them keeps gaps filled), plus Sleep (out of
  // scope for this pipeline).
  Future<void> syncAllFromRing() async {
    if (_isSyncing || !_isConnected) return;
    final myGen = ++_syncGen;
    bool alive() => _syncGen == myGen;

    _isSyncing = true;
    _syncProgress = 0.0;
    _syncStep = 'HRV';
    notifyListeners();

    const kTimeout = Duration(seconds: 8);

    try {
      // 1. HRV (0% → 33%)
      try {
        final json = await _ble.getTodayHrv().timeout(kTimeout);
        _parseAndSaveHrv(json);
      } catch (e, st) {
        _recordError(e, st);
      }
      if (!alive()) return;
      _syncProgress = 0.33;
      _syncStep = 'Sleep';
      notifyListeners();

      // 2. Sleep (33% → 66%)
      try {
        final json = await _ble.getTodaySleep().timeout(kTimeout);
        _parseAndSaveSleep(json);
      } catch (e, st) {
        _recordError(e, st);
      }
      if (!alive()) return;
      _syncProgress = 0.66;
      _syncStep = 'Temperature';
      notifyListeners();

      // 3. Temperature (66% → 100%) — use syncAutoTemperature to fetch from ring
      try {
        final json = await _ble.syncAutoTemperature().timeout(
          const Duration(seconds: 15),
        );
        _parseAndSaveTemp(json);
      } catch (e, st) {
        _recordError(e, st);
      }
      if (!alive()) return;
      _syncProgress = 1.0;
      notifyListeners();

      // Brief pause so user sees 100% before overlay hides
      await Future.delayed(const Duration(milliseconds: 700));
    } finally {
      if (alive()) {
        _isSyncing = false;
        _syncStep = '';
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
      final raw = (decoded['d'] as List<dynamic>? ?? [])
          .map((v) => (v as num).toInt())
          .toList();
      final readings = raw.where((v) => v > 0).toList();
      if (readings.isEmpty) return;
      final avg = (readings.reduce((a, b) => a + b) / readings.length).round();
      final min = readings.reduce((a, b) => a < b ? a : b);
      final max = readings.reduce((a, b) => a > b ? a : b);
      _todayAvgHrv = avg;
      notifyListeners();
      _saveHrvToDb(avg, min, max, readings.length);
    } catch (e, st) {
      _recordError(e, st);
    }
  }

  void _parseAndSaveSleep(String jsonStr) {
    try {
      final d = jsonDecode(jsonStr) as Map<String, dynamic>;
      final total = (d['totalSleepDuration'] as num? ?? 0).toInt();
      final deep = (d['deepDuration'] as num? ?? 0).toInt();
      final light = (d['lightDuration'] as num? ?? 0).toInt();
      final rem = (d['remDuration'] as num? ?? 0).toInt();
      final awake = (d['awakeDuration'] as num? ?? 0).toInt();
      final st = (d['sleepTime'] as num? ?? 0).toInt();
      final et = (d['wakeTime'] as num? ?? 0).toInt();
      if (total <= 0) return;
      final window = (st > 0 && et > 0) ? (et - st) : total;
      final efficiency = window > 0
          ? (total / window * 100).clamp(0.0, 100.0)
          : 0.0;
      final deepPct = total > 0 ? (deep / total * 100).clamp(0.0, 40.0) : 0.0;
      final remPct = total > 0 ? (rem / total * 100).clamp(0.0, 30.0) : 0.0;
      final score = (efficiency * 0.4 + deepPct * 1.0 + remPct * 0.5)
          .round()
          .clamp(0, 100);
      _todaySleepDuration = total;
      _todaySleepScore = score;
      _todaySleepDeepSecs = deep;
      _todaySleepLightSecs = light;
      _todaySleepRemSecs = rem;
      notifyListeners();
      _saveSleepToDb(total, deep, light, rem, awake, score, st, et);
      // Two-way sync: push last night's sleep into Health Connect.
      unawaited(_pushSleepToHealthConnect(st, et, deep, light, rem, awake));
    } catch (e, st) {
      _recordError(e, st);
    }
  }

  Future<void> _pushSleepToHealthConnect(
    int stSecs,
    int etSecs,
    int deepSecs,
    int lightSecs,
    int remSecs,
    int awakeSecs,
  ) async {
    if (stSecs <= 0) return;
    final sleepTime = DateTime.fromMillisecondsSinceEpoch(stSecs * 1000);
    final wakeTime = DateTime.fromMillisecondsSinceEpoch(
      (etSecs > 0 ? etSecs : stSecs + 3600) * 1000,
    );
    await HealthConnectService.instance.tryWriteSleep(
      sleepTime: sleepTime,
      wakeTime: wakeTime,
      lightMinutes: lightSecs ~/ 60,
      deepMinutes: deepSecs ~/ 60,
      remMinutes: remSecs ~/ 60,
      awakeMinutes: awakeSecs ~/ 60,
    );
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
          var val =
              (m['mValue'] as num?)?.toDouble() ?? (m['b'] as num?)?.toDouble();
          if (ts == null || val == null || val <= 0) continue;
          if (val > 100) val /= 10;
          final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000).toLocal();
          if (latestTime == null || dt.isAfter(latestTime)) {
            latestTime = dt;
            latestVal = val;
          }
        }
      } else if (decoded is Map<String, dynamic>) {
        // TemperatureEntity: interval array — only trust this for today's data
        // (mIndex 0). Native's startObtainTemperatureSeries(2) requests 3 days
        // (today/yesterday/day-before), and callbacks can arrive for any of them —
        // without this check, an older day's data was being saved and shown as
        // "today's" reading.
        final mIndex = (decoded['mIndex'] as num?)?.toInt();
        final rawVals =
            (decoded['mValues'] as List<dynamic>?) ??
            (decoded['d'] as List<dynamic>?);
        if (mIndex == 0 && rawVals != null) {
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
    } catch (e, st) {
      _recordError(e, st);
    }
  }

  // ── DB save helpers ───────────────────────────────────────────────────────

  Future<void> _saveHrvToDb(int avg, int min, int max, int count) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.upsertHrv(
        userId: user.id,
        date: DateTime.now(),
        avgHrv: avg,
        minHrv: min,
        maxHrv: max,
        sampleCount: count,
      );
    } catch (e, st) {
      _recordError(e, st);
    }
  }

  Future<void> _saveSleepToDb(
    int total,
    int deep,
    int light,
    int rem,
    int awake,
    int score,
    int st,
    int et,
  ) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.upsertSleep(
        userId: user.id,
        date: DateTime.now(),
        totalDuration: total,
        deepDuration: deep,
        lightDuration: light,
        remDuration: rem,
        awakeDuration: awake,
        sleepScore: score,
        sleepTime: st,
        wakeTime: et,
      );
    } catch (e, st) {
      _recordError(e, st);
    }
  }

  Future<void> _saveStepsToDb(int steps, int calories, double distanceM) async {
    if (steps <= 0 && calories <= 0) return;

    // 1. Direct Supabase upsert
    final user = SupabaseService.currentUser;
    if (user != null) {
      try {
        await SupabaseService.upsertSteps(
          userId: user.id,
          date: DateTime.now(),
          steps: steps,
          calories: calories,
          distanceM: distanceM,
        );
      } catch (e) {
        debugPrint('_saveStepsToDb Supabase error: $e');
      }
    }

    // 2. Room DB insert + native SupabaseSyncManager trigger
    try {
      await _ble.saveStepsSnapshot(
        steps: steps,
        calories: calories,
        distanceM: distanceM,
      );
    } catch (e) {
      debugPrint('_saveStepsToDb native error: $e');
    }
  }

  // ── Supabase load-on-startup ──────────────────────────────────────────────

  Future<void> _loadTodayFromSupabase() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return;
      final now = DateTime.now();
      final ds =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final data = await SupabaseService.client
          .from('user_steps')
          .select()
          .eq('user_id', user.id)
          .eq('date', ds)
          .maybeSingle();
      if (data != null) {
        _todaySteps = (data['steps'] as num? ?? 0).toInt();
        final rawCal = (data['calories'] as num? ?? 0).toInt();
        _todayCalories = (rawCal >= 500 && _todaySteps < 4000)
            ? rawCal ~/ 1000
            : rawCal;
        _todayDistanceM = (data['distance_m'] as num? ?? 0).toDouble();
        notifyListeners();
      }
    } catch (e, st) {
      _recordError(e, st);
    }
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
    } catch (e, st) {
      _recordError(e, st);
    }
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
    } catch (e, st) {
      _recordError(e, st);
    }
  }

  Future<void> _loadTodayBpFromSupabase() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return;
      final data = await SupabaseService.getTodayBp(user.id);
      if (data != null) {
        _latestBpSbp = (data['systolic'] as num? ?? 0).toInt();
        _latestBpDbp = (data['diastolic'] as num? ?? 0).toInt();
      } else {
        _latestBpSbp = 0;
        _latestBpDbp = 0;
      }
      notifyListeners();
    } catch (e, st) {
      _recordError(e, st);
    }
  }

  Future<void> _loadTodayStressFromSupabase() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return;
      final data = await SupabaseService.getTodayStress(user.id);
      if (data != null) {
        final val = (data['stress_value'] as num? ?? 0).toInt();
        _latestStressValue = val;
        _todayAvgStress = (data['avg_stress'] as num?)?.round() ?? val;
        _todayMinStress = (data['min_stress'] as num?)?.toInt() ?? val;
        _todayMaxStress = (data['max_stress'] as num?)?.toInt() ?? val;
      } else {
        _latestStressValue = 0;
        _todayAvgStress = 0;
        _todayMinStress = 0;
        _todayMaxStress = 0;
      }
      notifyListeners();
    } catch (e, st) {
      _recordError(e, st);
    }
  }

  Future<void> _loadTodayTempFromSupabase() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return;
      final data = await SupabaseService.getTodayTemp(user.id);
      if (data != null) {
        final v = (data['value_c'] as num? ?? 0).toDouble();
        _latestTempC = v > 0 ? v : 0.0;
      } else {
        _latestTempC = 0.0;
      }
      notifyListeners();
    } catch (e, st) {
      _recordError(e, st);
    }
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
    } catch (e, st) {
      _recordError(e, st);
    }
  }

  Future<void> _loadTodaySleepFromSupabase() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return;
      final data = await SupabaseService.getSleepForDate(
        user.id,
        DateTime.now(),
      );
      if (data != null) {
        _todaySleepDuration = (data['total_duration'] as num? ?? 0).toInt();
        _todaySleepScore = (data['sleep_score'] as num? ?? 0).toInt();
        _todaySleepDeepSecs = (data['deep_duration'] as num? ?? 0).toInt();
        _todaySleepLightSecs = (data['light_duration'] as num? ?? 0).toInt();
        _todaySleepRemSecs = (data['rem_duration'] as num? ?? 0).toInt();
        notifyListeners();
      }
    } catch (e, st) {
      _recordError(e, st);
    }
  }

  void _parseAndSaveTodaySteps(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      final list = decoded is List ? decoded : <dynamic>[];
      if (list.isEmpty) return;

      final stepSlots = List<int>.filled(96, 0);
      int totalSteps = 0;
      int totalCalRaw = 0;
      double totalDist = 0.0;

      for (final item in list) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final slot =
            (m['d'] as num?)?.toInt() ??
            (m['timeIndex'] as num?)?.toInt() ??
            -1;
        final steps =
            (m['f'] as num?)?.toInt() ?? (m['walkSteps'] as num?)?.toInt() ?? 0;
        final runSteps = (m['runSteps'] as num?)?.toInt() ?? 0;
        final stepTotal = steps + runSteps;
        final calRaw =
            (m['e'] as num?)?.toInt() ?? (m['calorie'] as num?)?.toInt() ?? 0;
        final dist =
            (m['g'] as num?)?.toDouble() ??
            (m['distance'] as num?)?.toDouble() ??
            0.0;

        totalSteps += stepTotal;
        totalCalRaw += calRaw;
        totalDist += dist;
        if (slot >= 0 && slot < 96) {
          stepSlots[slot] += stepTotal;
        }
      }

      final totalCal = totalCalRaw >= 1000 ? totalCalRaw ~/ 1000 : (totalCalRaw > 0 ? 1 : 0);

      if (totalSteps > 0 || totalCal > 0 || totalDist > 0) {
        _todaySteps = totalSteps;
        _todayCalories = totalCal;
        _todayDistanceM = totalDist;
        _todayStepsByInterval = stepSlots;
        notifyListeners();
        _saveStepsToDb(totalSteps, totalCal, totalDist);
      }
    } catch (e, st) {
      _recordError(e, st);
    }
  }

  Future<void> syncTodayStepsFromRing() async {
    if (_syncingSteps) return;
    _syncingSteps = true;
    notifyListeners();
    try {
      final jsonStr = await _ble.getTodaySteps();
      _parseAndSaveTodaySteps(jsonStr);
    } catch (e, st) {
      _recordError(e, st);
    }
    if (_todaySteps <= 0) {
      await _refreshStepsFromLocal();
    }
    _syncingSteps = false;
    notifyListeners();
  }

  // ── Device info ───────────────────────────────────────────────────────────

  Future<void> refreshBattery() async {
    try {
      final b = await _ble.getBattery();
      if (b > 0) {
        _battery = b;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('last_battery', b);
      }
      notifyListeners();
      if (_battery > 0) {
        _maybeAlert(
          'Low Battery Prompt',
          _lowBatteryPromptEnabled && _battery <= _kLowBatteryThreshold,
          title: 'Ring Battery Low',
          message: 'Your ring is at $_battery% battery.',
          vital: 'heart_rate',
        );
      }
    } catch (e, st) {
      _recordError(e, st);
    }
  }

  Future<bool> findDevice({bool enable = true}) async {
    try {
      return await _ble.findDevice(enable: enable);
    } catch (e) {
      debugPrint('BleProvider.findDevice error: $e');
      return false;
    }
  }

  Future<void> refreshFirmwareVersion() async {
    try {
      final v = await _ble.getFirmwareVersion();
      _firmwareVersion = v.map((k, val) => MapEntry(k, val.toString()));
      notifyListeners();
    } catch (e, st) {
      _recordError(e, st);
    }
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
      _isConnected = false;
      _isReconnecting = false;
      _connectDelaySeconds = 2;
      _pendingDeviceName = device.name;
      _pendingDeviceAddress = device.address;
      notifyListeners();

      final ok = await _ble.connect(device.address);
      if (ok) {
        _deviceName = device.name;
        _deviceAddress = device.address;
        _isConnected = true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('device_name', device.name);
        await prefs.setString('device_address', device.address);
        // _onConnected() is triggered by the connectionState event from the SDK,
        // which fires when the ring is fully ready (green light). Calling it here
        // (on raw GATT connect) is too early and causes sync to hang.
        notifyListeners();
      }
      // On timeout/failure here, _pendingDeviceName/_pendingDeviceAddress are
      // deliberately left set — see the field's doc comment and the
      // 'connectionState' handler in _listenEvents().
      return ok;
    } catch (e) {
      debugPrint('[BleProvider] connect() failed: $e');
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
    _bindReadyCompleter = null;
    await _ble.disconnect();
    _isConnected = false;
    _battery = -1;
    _deviceName = '';
    _deviceAddress = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('device_name');
    await prefs.remove('device_address');
    await prefs.remove('last_battery');
    notifyListeners();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _stopEmergencySmsPoll();
    _cameraShutterController.close();
    super.dispose();
  }
}
