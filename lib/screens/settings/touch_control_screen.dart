import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../theme/app_theme.dart';

class TouchControlScreen extends StatefulWidget {
  const TouchControlScreen({super.key});
  @override
  State<TouchControlScreen> createState() => _TouchControlScreenState();
}

class _TouchControlScreenState extends State<TouchControlScreen> {
  static const _encoder = JsonEncoder.withIndent('  ');

  // Ring-reported gesture codes (loadData[1] when dataType == 0x2d).
  static const _customButtonDataType = 0x2d;
  static const _gestureNames = {0: 'none', 1: 'decline', 2: 'slideUp', 3: 'single', 4: 'longPress'};
  static const _singleTapCode = 3;

  // The SDK only reports single taps — double tap is synthesized here from
  // two single-tap events arriving within this window.
  static const _doubleTapWindow = Duration(milliseconds: 400);

  final _ble = BleService();
  bool _loading = false;
  bool _touchEnabled = false;
  StreamSubscription<Map<String, dynamic>>? _sub;
  final List<Map<String, dynamic>> _events = [];
  DateTime? _lastSingleTapAt;

  @override
  void initState() {
    super.initState();
    _loadSetting();
    _sub = _ble.events.listen(_onDeviceEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onDeviceEvent(Map<String, dynamic> event) {
    if (event['type'] != 'deviceNotification') return;
    final data = Map<String, dynamic>.from(event['data'] as Map);
    final dataType = data['dataType'] as int?;
    final loadData = (data['loadData'] as List?)?.cast<int>() ?? const <int>[];

    final enriched = <String, dynamic>{
      'receivedAt': DateTime.now().toIso8601String(),
      ...data,
    };

    if (dataType == _customButtonDataType && loadData.length > 1) {
      final code = loadData[1];
      enriched['gesture'] = _gestureNames[code] ?? 'unknown($code)';

      if (code == _singleTapCode) {
        final now = DateTime.now();
        if (_lastSingleTapAt != null && now.difference(_lastSingleTapAt!) <= _doubleTapWindow) {
          enriched['gesture'] = 'doubleTap';
          _lastSingleTapAt = null; // both taps consumed, don't chain into a triple
        } else {
          _lastSingleTapAt = now;
        }
      }
    }

    setState(() {
      _events.insert(0, enriched);
      if (_events.length > 50) _events.removeLast();
    });
  }

  Future<void> _loadSetting() async {
    if (!context.read<BleProvider>().isConnected) return;
    setState(() => _loading = true);
    try {
      final json = await _ble.getTouchControlSetting();
      final map = jsonDecode(json) as Map<String, dynamic>? ?? {};
      setState(() => _touchEnabled = (map['appType'] as int? ?? 0) != 0);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setTouchEnabled(bool enabled) async {
    setState(() => _touchEnabled = enabled);
    try {
      await _ble.setTouchControlSetting(enable: enabled, strength: 5);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Touch Control'),
        actions: [
          IconButton(
            tooltip: 'Clear log',
            icon: const Icon(Icons.delete_outline),
            onPressed: _events.isEmpty ? null : () => setState(() => _events.clear()),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                SwitchListTile(
                  title: const Text('Touch Sensor'),
                  subtitle: Text(
                    connected
                        ? "Enable the ring's touch sensor and report touch events below"
                        : 'Connect to a ring to change this setting',
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: _touchEnabled,
                  onChanged: connected ? _setTouchEnabled : null,
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'Touch Events',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                ),
                if (_events.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'No events yet. Tap the ring to test the touch sensor.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ..._events.map((e) {
                    final isDoubleTap = e['gesture'] == 'doubleTap';
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDoubleTap
                            ? AppTheme.gold.withValues(alpha: 0.15)
                            : Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: isDoubleTap
                            ? Border.all(color: AppTheme.gold, width: 1)
                            : null,
                      ),
                      child: Text(
                        _encoder.convert(e),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: isDoubleTap ? AppTheme.gold : Colors.greenAccent,
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
