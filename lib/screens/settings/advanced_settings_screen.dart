import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';

class AdvancedSettingsScreen extends StatefulWidget {
  const AdvancedSettingsScreen({super.key});
  @override
  State<AdvancedSettingsScreen> createState() => _AdvancedSettingsScreenState();
}

class _AdvancedSettingsScreenState extends State<AdvancedSettingsScreen> {
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
      final json = await _ble.getAdvancedSettings();
      setState(() => _settings = jsonDecode(json) ?? {});
    } catch (_) {} finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    try {
      await _ble.setAdvancedSetting(jsonEncode(_settings));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Advanced settings saved')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Widget _switchTile(String key, String title, {String? subtitle}) {
    final val = _settings[key] as bool? ?? false;
    return SwitchListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(fontSize: 12)) : null,
      value: val,
      onChanged: (v) => setState(() => _settings[key] = v),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Advanced Settings'),
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
                _header('Power'),
                _switchTile('batterySaving', 'Battery Saving Mode'),
                const Divider(),
                _header('Location'),
                _switchTile('agpsEnable', 'AGPS', subtitle: 'Assisted GPS for faster location fix'),
                const Divider(),
                _header('Interface'),
                _switchTile('touchControl', 'Touch Control'),
                _switchTile('intellSettings', 'Intelligent Settings'),
                const Divider(),
                _header('Religious'),
                _switchTile('muslimMode', 'Muslim Prayer Reminder Mode'),
                const SizedBox(height: 80),
              ],
            ),
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
      );
}
