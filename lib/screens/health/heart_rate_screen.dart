import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../widgets/data_card.dart';

class HeartRateScreen extends StatefulWidget {
  const HeartRateScreen({super.key});
  @override
  State<HeartRateScreen> createState() => _HeartRateScreenState();
}

class _HeartRateScreenState extends State<HeartRateScreen> {
  final _ble = BleService();
  bool _loading = false;
  String _result = '';
  bool _settingEnabled = true;
  int _settingInterval = 5;
  bool _measuring = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    if (!context.read<BleProvider>().isConnected) return;
    try {
      final json = await _ble.getHeartRateSetting();
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
      final data = await _ble.getTodayHeartRate();
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
      final data = await _ble.syncIntervalHeartRate();
      setState(() => _result = _prettyJson(data));
    } catch (e) {
      setState(() => _result = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveSettings() async {
    try {
      await _ble.setHeartRateSetting(enable: _settingEnabled, interval: _settingInterval);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _toggleManual() async {
    final start = !_measuring;
    setState(() => _measuring = start);
    try {
      final result = await _ble.manualModeHeart(start: start);
      setState(() => _result = _prettyJson(result));
    } catch (e) {
      setState(() { _measuring = !start; _result = 'Error: $e'; });
    }
  }

  String _prettyJson(String raw) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;
    return Scaffold(
      appBar: AppBar(title: const Text('Heart Rate')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!connected)
            _notConnectedBanner(),
          const SizedBox(height: 8),
          DataCard(label: 'Today\'s Heart Rate', value: '--', unit: 'bpm', icon: Icons.favorite, color: Colors.red),
          const SizedBox(height: 16),
          _settingsCard(),
          const SizedBox(height: 16),
          _actionsCard(connected),
          if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if (_result.isNotEmpty) _resultCard(),
        ],
      ),
    );
  }

  Widget _notConnectedBanner() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange)),
        child: const Row(children: [Icon(Icons.warning, color: Colors.orange), SizedBox(width: 8), Text('Device not connected')]),
      );

  Widget _settingsCard() => Card(
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
                    items: [1, 5, 10, 15, 30, 60]
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
      );

  Widget _actionsCard(bool connected) => Card(
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
                    onPressed: connected ? _syncInterval : null,
                    icon: const Icon(Icons.sync),
                    label: const Text('Sync Interval'),
                  ),
                  ElevatedButton.icon(
                    onPressed: connected ? _toggleManual : null,
                    icon: Icon(_measuring ? Icons.stop : Icons.play_arrow),
                    label: Text(_measuring ? 'Stop Measure' : 'Manual Measure'),
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
      );

  Widget _resultCard() => Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Result', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(_result, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            ],
          ),
        ),
      );
}
