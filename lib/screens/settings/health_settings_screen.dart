import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';

class HealthSettingsScreen extends StatefulWidget {
  const HealthSettingsScreen({super.key});
  @override
  State<HealthSettingsScreen> createState() => _HealthSettingsScreenState();
}

class _HealthSettingsScreenState extends State<HealthSettingsScreen> {
  final _ble = BleService();
  bool _loading = false;
  Map<String, dynamic> _settings = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    if (!context.read<BleProvider>().isConnected) return;
    setState(() => _loading = true);
    try {
      final json = await _ble.getHealthSettings();
      setState(() => _settings = jsonDecode(json) ?? {});
    } catch (_) {} finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    try {
      await _ble.setHealthSettings(jsonEncode(_settings));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Health settings saved')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Widget _buildBoolTile(String key, String title, [String? subtitle]) {
    final val = _settings[key] as bool? ?? false;
    return SwitchListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      value: val,
      onChanged: (v) => setState(() => _settings[key] = v),
    );
  }

  Widget _buildIntervalTile(String key, String title, List<int> options) {
    final val = _settings[key] as int? ?? options.first;
    return ListTile(
      title: Text(title),
      trailing: DropdownButton<int>(
        value: options.contains(val) ? val : options.first,
        items: options.map((e) => DropdownMenuItem(value: e, child: Text('$e min'))).toList(),
        onChanged: (v) => setState(() => _settings[key] = v),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Settings'),
        actions: [
          TextButton(
            onPressed: connected ? _save : null,
            child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _sectionHeader('Heart Rate'),
                _buildBoolTile('hrEnable', 'Heart Rate Monitoring'),
                _buildIntervalTile('hrInterval', 'Measurement Interval', [1, 5, 10, 15, 30]),
                const Divider(),
                _sectionHeader('Blood Pressure'),
                _buildBoolTile('bpEnable', 'Blood Pressure Monitoring'),
                _buildIntervalTile('bpInterval', 'Measurement Interval', [5, 10, 15, 30, 60]),
                const Divider(),
                _sectionHeader('Blood Oxygen'),
                _buildBoolTile('spo2Enable', 'SpO2 Monitoring'),
                _buildIntervalTile('spo2Interval', 'Measurement Interval', [1, 5, 10, 15, 30]),
                const Divider(),
                _sectionHeader('HRV'),
                _buildBoolTile('hrvEnable', 'HRV Monitoring'),
                const Divider(),
                _sectionHeader('Stress'),
                _buildBoolTile('pressureEnable', 'Stress Monitoring'),
                const Divider(),
                _sectionHeader('Temperature'),
                _buildBoolTile('tempEnable', 'Temperature Monitoring'),
                const SizedBox(height: 80),
              ],
            ),
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
      );
}
