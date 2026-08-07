import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/data_card.dart';

/// Sugar & Lipids wellness panel.
///
/// Reads the ring's sugar/lipid auto-measure state (temperature / RRI /
/// emotion channels) via `getHealthSettings` and lets the user toggle them.
/// Values shown come from the ring (real SDK reads); nothing is faked.
class SugarLipidsScreen extends StatefulWidget {
  const SugarLipidsScreen({super.key});
  @override
  State<SugarLipidsScreen> createState() => _SugarLipidsScreenState();
}

class _SugarLipidsScreenState extends State<SugarLipidsScreen> {
  final _ble = BleService();
  bool _loading = false;
  bool _loaded = false;
  Map<String, dynamic> _settings = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!context.read<BleProvider>().isConnected) return;
    setState(() => _loading = true);
    try {
      final json = await _ble.getHealthSettings();
      final m = (jsonDecode(json) ?? const {})['sugarLipids'] ?? const {};
      setState(() {
        _settings = Map<String, dynamic>.from(m);
        _loaded = true;
      });
    } catch (e) {
      debugPrint('SugarLipidsScreen._load: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    try {
      await _ble.setHealthSettings(jsonEncode({'sugarLipids': _settings}));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sugar & lipid monitor settings saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _set(String kind, bool v) {
    setState(() {
      final cur = Map<String, dynamic>.from(
        _settings[kind] as Map? ?? const {},
      );
      cur['enabled'] = v;
      _settings[kind] = cur;
    });
  }

  dynamic _field(String kind, String key) {
    final sub = _settings[kind];
    if (sub is Map) return sub[key];
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sugar & Lipids'),
        actions: [
          TextButton(
            onPressed: connected && _loaded ? _save : null,
            child: const Text(
              'Save',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: DataCard(
                  label: 'Blood Sugar',
                  value: _valueLabel('temperature'),
                  unit: 'mmol/L',
                  icon: Icons.science,
                  color: AppTheme.gold,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DataCard(
                  label: 'Blood Lipids',
                  value: _valueLabel('rri'),
                  unit: 'mmol/L',
                  icon: Icons.water_drop,
                  color: AppTheme.gold,
                ),
              ),
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
                  const Text(
                    'Ring Monitoring',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Auto-measurement channels the ring uses to estimate sugar & lipid wellness. Values and intervals come from the ring.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Temperature channel'),
                    subtitle: Text(_interval('temperature')),
                    value: _field('temperature', 'enabled') == true,
                    onChanged: connected ? (v) => _set('temperature', v) : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('RRI channel'),
                    subtitle: Text(_interval('rri')),
                    value: _field('rri', 'enabled') == true,
                    onChanged: connected ? (v) => _set('rri', v) : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Emotion channel'),
                    subtitle: Text(_interval('emotion')),
                    value: _field('emotion', 'enabled') == true,
                    onChanged: connected ? (v) => _set('emotion', v) : null,
                  ),
                ],
              ),
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (!_loading && connected && !_loaded)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'Ring did not report sugar & lipid monitor state. Make sure the ring is connected and try again.',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          if (!connected)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'Connect your ring to view and change monitor settings.',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  String _valueLabel(String kind) {
    final read = _field(kind, 'read');
    final value = _field(kind, 'value');
    if (read == true && value != null) return value.toString();
    return '--';
  }

  String _interval(String kind) {
    final enabled = _field(kind, 'enabled');
    final start = _field(kind, 'startInterval');
    final interval = _field(kind, 'interval');
    if (enabled == null && start == null && interval == null) return 'Unknown';
    final parts = <String>[];
    if (enabled != null) parts.add(enabled == true ? 'On' : 'Off');
    if (interval != null) parts.add('every ${interval}s');
    return parts.join(' · ');
  }
}