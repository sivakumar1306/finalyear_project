import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../widgets/data_card.dart';

class BloodOxygenScreen extends StatefulWidget {
  const BloodOxygenScreen({super.key});
  @override
  State<BloodOxygenScreen> createState() => _BloodOxygenScreenState();
}

class _BloodOxygenScreenState extends State<BloodOxygenScreen> {
  final _ble = BleService();
  bool _loading = false;
  String _result = '';
  bool _settingEnabled = true;
  int _settingInterval = 5;
  bool _measuring = false;
  String _spo2 = '--';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    if (!context.read<BleProvider>().isConnected) return;
    try {
      final json = await _ble.getBloodOxygenSetting();
      final m = jsonDecode(json);
      setState(() {
        _settingEnabled = m['enable'] ?? true;
        _settingInterval = m['interval'] ?? 5;
      });
    } catch (_) {}
  }

  Future<void> _fetchToday() async {
    setState(() { _loading = true; _result = ''; });
    try {
      final data = await _ble.getTodayBloodOxygen();
      setState(() => _result = _prettyJson(data));
    } catch (e) {
      setState(() => _result = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _syncInterval() async {
    setState(() { _loading = true; _result = ''; });
    try {
      final data = await _ble.syncIntervalBloodOxygen();
      setState(() => _result = _prettyJson(data));
    } catch (e) {
      setState(() => _result = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveSettings() async {
    try {
      await _ble.setBloodOxygenSetting(enable: _settingEnabled, interval: _settingInterval);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _toggleManual() async {
    final start = !_measuring;
    setState(() => _measuring = start);
    try {
      final result = await _ble.manualModeBloodOxygen(start: start);
      setState(() {
        _result = _prettyJson(result);
        if (start) {
          try {
            final m = jsonDecode(result) as Map<String, dynamic>;
            final v = (m['spo2'] as num?)?.toInt() ?? 0;
            if (v > 0) _spo2 = '$v';
          } catch (_) {}
        }
        _measuring = false;
      });
    } catch (e) {
      final msg = e.toString().contains('TIMEOUT')
          ? 'Measurement timed out. Make sure the ring is worn properly.'
          : 'Error: $e';
      setState(() { _measuring = false; _result = msg; });
    }
  }

  String _prettyJson(String raw) {
    try { return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw)); } catch (_) { return raw; }
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;
    return Scaffold(
      appBar: AppBar(title: const Text('Blood Oxygen (SpO2)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DataCard(label: 'SpO2', value: _spo2, unit: '%', icon: Icons.bloodtype, color: Colors.blue),
          const SizedBox(height: 16),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  SwitchListTile(
                    title: const Text('Auto Monitoring'),
                    value: _settingEnabled,
                    onChanged: (v) => setState(() => _settingEnabled = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  Row(
                    children: [
                      const Text('Interval (min):'),
                      const SizedBox(width: 12),
                      DropdownButton<int>(
                        value: _settingInterval,
                        items: [1, 5, 10, 15, 30]
                            .map((e) => DropdownMenuItem(value: e, child: Text('$e min')))
                            .toList(),
                        onChanged: (v) => setState(() => _settingInterval = v ?? 5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: _saveSettings, child: const Text('Save Settings')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Actions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(onPressed: connected ? _fetchToday : null, icon: const Icon(Icons.today), label: const Text('Today\'s Data')),
                      ElevatedButton.icon(onPressed: connected ? _syncInterval : null, icon: const Icon(Icons.sync), label: const Text('Sync Interval')),
                      ElevatedButton.icon(
                        onPressed: connected ? _toggleManual : null,
                        icon: Icon(_measuring ? Icons.stop : Icons.play_arrow),
                        label: Text(_measuring ? 'Stop' : 'Manual Measure'),
                        style: ElevatedButton.styleFrom(backgroundColor: _measuring ? Colors.red : null, foregroundColor: _measuring ? Colors.white : null),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if (_result.isNotEmpty)
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(padding: const EdgeInsets.all(16), child: Text(_result, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
            ),
        ],
      ),
    );
  }
}
