import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/incident_service.dart';

class DisplaySettingsScreen extends StatefulWidget {
  const DisplaySettingsScreen({super.key});
  @override
  State<DisplaySettingsScreen> createState() => _DisplaySettingsScreenState();
}

class _DisplaySettingsScreenState extends State<DisplaySettingsScreen> {
  final _ble = BleService();
  bool _loading = false;
  int _brightness = 3;
  int _clockStyle = 0;
  bool _is24h = true;
  int _orientation = 0;
  int _screenOnDuration = 5;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    if (!context.read<BleProvider>().isConnected) return;
    setState(() => _loading = true);
    try {
      final json = await _ble.getDisplaySettings();
      final m = jsonDecode(json) ?? {};
      if (!mounted) return;
      setState(() {
        _brightness = m['brightness'] ?? 3;
        _clockStyle = m['clockStyle'] ?? 0;
        _is24h = m['is24h'] ?? true;
        _orientation = m['orientation'] ?? 0;
        _screenOnDuration = m['screenOnDuration'] ?? 5;
      });
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'display_settings_screen',
        error: e,
        stackTrace: st,
        customMessage: '_loadSettings failed',
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final data = {
      'brightness': _brightness,
      'clockStyle': _clockStyle,
      'is24h': _is24h,
      'orientation': _orientation,
      'screenOnDuration': _screenOnDuration,
    };
    try {
      await _ble.setDisplaySetting(jsonEncode(data));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Display settings saved')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Display & Device'),
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
                _header('Screen'),
                ListTile(
                  title: const Text('Brightness'),
                  subtitle: Slider(
                    value: _brightness.toDouble(),
                    min: 1, max: 5, divisions: 4,
                    label: '$_brightness',
                    onChanged: (v) => setState(() => _brightness = v.round()),
                  ),
                  trailing: Text('$_brightness', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                ListTile(
                  title: const Text('Screen On Duration'),
                  trailing: DropdownButton<int>(
                    value: _screenOnDuration,
                    items: [3, 5, 8, 10, 15, 20]
                        .map((e) => DropdownMenuItem(value: e, child: Text('$e s')))
                        .toList(),
                    onChanged: (v) => setState(() => _screenOnDuration = v ?? 5),
                  ),
                ),
                const Divider(),
                _header('Clock'),
                ListTile(
                  title: const Text('Clock Style'),
                  trailing: DropdownButton<int>(
                    value: _clockStyle,
                    items: List.generate(8, (i) => DropdownMenuItem(value: i, child: Text('Style ${i + 1}'))),
                    onChanged: (v) => setState(() => _clockStyle = v ?? 0),
                  ),
                ),
                SwitchListTile(
                  title: const Text('24-Hour Format'),
                  value: _is24h,
                  onChanged: (v) => setState(() => _is24h = v),
                ),
                const Divider(),
                _header('Orientation'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Left Hand (Default)'),
                        selected: _orientation == 0,
                        onSelected: (_) => setState(() => _orientation = 0),
                      ),
                      ChoiceChip(
                        label: const Text('Right Hand'),
                        selected: _orientation == 1,
                        onSelected: (_) => setState(() => _orientation = 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
      );
}
