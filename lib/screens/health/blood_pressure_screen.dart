import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../widgets/data_card.dart';

class BloodPressureScreen extends StatefulWidget {
  const BloodPressureScreen({super.key});
  @override
  State<BloodPressureScreen> createState() => _BloodPressureScreenState();
}

class _BloodPressureScreenState extends State<BloodPressureScreen> {
  final _ble = BleService();
  bool _loading = false;
  String _result = '';
  bool _settingEnabled = true;
  int _settingInterval = 30;
  bool _measuring = false;
  String _sbp = '--';
  String _dbp = '--';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    if (!context.read<BleProvider>().isConnected) return;
    try {
      final json = await _ble.getBloodPressureSetting();
      final m = jsonDecode(json);
      setState(() {
        _settingEnabled = m['enable'] ?? true;
        _settingInterval = m['interval'] ?? 30;
      });
    } catch (_) {}
  }

  Future<void> _fetchToday() async {
    setState(() { _loading = true; _result = ''; });
    try {
      final data = await _ble.getTodayBloodPressure();
      setState(() {
        _result = _prettyJson(data);
        _updateCardsFromList(data);
      });
    } catch (e) {
      setState(() => _result = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _updateCardsFromList(String jsonStr) {
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      // find last entry with non-zero values
      for (final item in list.reversed) {
        final m = item as Map<String, dynamic>;
        final sbp = m['sbp'] ?? m['mSbp'] ?? m['systolic'] ?? 0;
        final dbp = m['dbp'] ?? m['mDbp'] ?? m['diastolic'] ?? 0;
        final s = (sbp as num).toInt();
        final d = (dbp as num).toInt();
        if (s > 0 && d > 0) {
          _sbp = '$s';
          _dbp = '$d';
          return;
        }
      }
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      await _ble.setBloodPressureSetting(enable: _settingEnabled, interval: _settingInterval);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _toggleManual() async {
    final start = !_measuring;
    setState(() => _measuring = start);
    try {
      final result = await _ble.manualModeBP(start: start);
      setState(() {
        _result = _prettyJson(result);
        if (start) _updateCardsFromSingle(result);
        else _measuring = false;
      });
    } catch (e) {
      setState(() { _measuring = !start; _result = 'Error: $e'; });
    }
  }

  void _updateCardsFromSingle(String jsonStr) {
    try {
      final m = jsonDecode(jsonStr) as Map<String, dynamic>;
      final sbp = m['sbp'] ?? m['mSbp'] ?? m['systolic'] ?? 0;
      final dbp = m['dbp'] ?? m['mDbp'] ?? m['diastolic'] ?? 0;
      final s = (sbp as num).toInt();
      final d = (dbp as num).toInt();
      if (s > 0 && d > 0) {
        _sbp = '$s';
        _dbp = '$d';
      }
    } catch (_) {}
    _measuring = false;
  }

  String _prettyJson(String raw) {
    try { return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw)); } catch (_) { return raw; }
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;
    return Scaffold(
      appBar: AppBar(title: const Text('Blood Pressure')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: DataCard(label: 'Systolic (SBP)', value: _sbp, unit: 'mmHg', icon: Icons.arrow_upward, color: Colors.indigo)),
              const SizedBox(width: 8),
              Expanded(child: DataCard(label: 'Diastolic (DBP)', value: _dbp, unit: 'mmHg', icon: Icons.arrow_downward, color: Colors.indigo.shade300)),
            ],
          ),
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
                        items: [5, 10, 15, 30, 60]
                            .map((e) => DropdownMenuItem(value: e, child: Text('$e min')))
                            .toList(),
                        onChanged: (v) => setState(() => _settingInterval = v ?? 30),
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
                      ElevatedButton.icon(
                        onPressed: connected ? _fetchToday : null,
                        icon: const Icon(Icons.today),
                        label: const Text('Today\'s Data'),
                      ),
                      ElevatedButton.icon(
                        onPressed: connected ? _toggleManual : null,
                        icon: Icon(_measuring ? Icons.stop : Icons.play_arrow),
                        label: Text(_measuring ? 'Stop' : 'Manual Measure'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _measuring ? Colors.red : null,
                          foregroundColor: _measuring ? Colors.white : null,
                        ),
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
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Result', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text(_result, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
