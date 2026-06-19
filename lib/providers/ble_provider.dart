import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ble_service.dart';

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
  int _battery = -1;
  String _deviceName = '';
  String _deviceAddress = '';
  Map<String, String> _firmwareVersion = {};
  final List<ScannedDevice> _scannedDevices = [];
  StreamSubscription? _eventSub;

  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;
  int get battery => _battery;
  String get deviceName => _deviceName;
  String get deviceAddress => _deviceAddress;
  Map<String, String> get firmwareVersion => _firmwareVersion;
  List<ScannedDevice> get scannedDevices => List.unmodifiable(_scannedDevices);

  BleProvider() {
    _loadSavedDevice();
    _listenEvents();
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
      checkConnection();
    }
  }

  Future<void> checkConnection() async {
    _isConnected = await _ble.isConnected();
    if (_isConnected) _onConnected();
    notifyListeners();
  }

  void _onConnected() {
    _ble.setTime();
    refreshBattery();
    refreshFirmwareVersion();
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
