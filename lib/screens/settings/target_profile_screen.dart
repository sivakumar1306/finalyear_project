import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/incident_service.dart';

class TargetProfileScreen extends StatefulWidget {
  const TargetProfileScreen({super.key});
  @override
  State<TargetProfileScreen> createState() => _TargetProfileScreenState();
}

class _TargetProfileScreenState extends State<TargetProfileScreen> {
  final _ble = BleService();
  bool _loading = false;

  final _stepsCtrl = TextEditingController(text: '8000');
  final _caloriesCtrl = TextEditingController(text: '500');
  final _sleepCtrl = TextEditingController(text: '8');
  final _distanceCtrl = TextEditingController(text: '5');
  final _ageCtrl = TextEditingController(text: '30');
  final _heightCtrl = TextEditingController(text: '170');
  final _weightCtrl = TextEditingController(text: '70');
  int _gender = 1;
  bool _profileSupported = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _stepsCtrl.dispose();
    _caloriesCtrl.dispose();
    _sleepCtrl.dispose();
    _distanceCtrl.dispose();
    _ageCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    if (!context.read<BleProvider>().isConnected) return;
    setState(() => _loading = true);
    try {
      final json = await _ble.getTargetAndProfile();
      final m = jsonDecode(json) ?? {};
      setState(() {
        _stepsCtrl.text = _fmt((m['stepTarget'] ?? 8000) as num);
        _caloriesCtrl.text = _fmt((m['calorieTarget'] ?? 500) as num);
        _sleepCtrl.text = _fmt((((m['sleepTargetMin'] ?? 480) as num).toDouble() / 60).clamp(1, 24));
        _distanceCtrl.text = _fmt((((m['distanceTargetM'] ?? 5000) as num).toDouble() / 1000).clamp(0.1, 1000));
        _profileSupported = m['profileSupported'] == true;
        if (_profileSupported) {
          _ageCtrl.text = _fmt((m['age'] ?? 30) as num);
          _heightCtrl.text = _fmt((m['height'] ?? 170) as num);
          _weightCtrl.text = _fmt((m['weight'] ?? 70) as num);
          _gender = m['gender'] ?? 1;
        }
      });
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'target_profile_screen',
        error: e,
        stackTrace: st,
        customMessage: '_loadSetting failed',
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final data = <String, dynamic>{
      'stepTarget': int.tryParse(_stepsCtrl.text) ?? 8000,
      'calorieTarget': int.tryParse(_caloriesCtrl.text) ?? 500,
      'sleepTarget': (double.tryParse(_sleepCtrl.text) ?? 8) * 60,
      'distanceTarget': (double.tryParse(_distanceCtrl.text) ?? 5) * 1000,
      'sportTargetMin': 60,
    };
    if (_profileSupported) {
      data['age'] = int.tryParse(_ageCtrl.text) ?? 30;
      data['height'] = int.tryParse(_heightCtrl.text) ?? 170;
      data['weight'] = int.tryParse(_weightCtrl.text) ?? 70;
      data['gender'] = _gender;
    }
    try {
      await _ble.setTargetAndProfile(jsonEncode(data));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            _profileSupported
                ? 'Profile saved'
                : 'Targets saved (user profile is read-only on this ring model)',
          ),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  String _fmt(num v) {
    final s = v is double ? v.toStringAsFixed(v % 1 == 0 ? 0 : 1) : v.toString();
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Target & Profile'),
        actions: [
          TextButton(
            onPressed: connected ? _save : null,
            child: const Text(
              'Save',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionCard('Activity Targets', [
                  _inputTile('Daily Steps Target', _stepsCtrl, 'steps'),
                  _inputTile('Calorie Target', _caloriesCtrl, 'kcal'),
                  _inputTile('Sleep Target', _sleepCtrl, 'hrs'),
                  _inputTile('Distance Target', _distanceCtrl, 'km'),
                ]),
                const SizedBox(height: 16),
                _sectionCard('User Profile', [
                  if (!_profileSupported) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        'Not editable — user profile is read-only on this ring model. Targets above are saved.',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ],
                  _inputTile('Age', _ageCtrl, 'years', enabled: _profileSupported),
                  _inputTile('Height', _heightCtrl, 'cm', enabled: _profileSupported),
                  _inputTile('Weight', _weightCtrl, 'kg', enabled: _profileSupported),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        const Text('Gender:'),
                        const SizedBox(width: 16),
                        ChoiceChip(
                          label: const Text('Male'),
                          selected: _gender == 1,
                          onSelected: _profileSupported
                              ? (_) => setState(() => _gender = 1)
                              : null,
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Female'),
                          selected: _gender == 0,
                          onSelected: _profileSupported
                              ? (_) => setState(() => _gender = 0)
                              : null,
                        ),
                      ],
                    ),
                  ),
                ]),
              ],
            ),
    );
  }

  Widget _sectionCard(String title, List<Widget> children) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        ...children,
        const SizedBox(height: 8),
      ],
    ),
  );

  Widget _inputTile(
    String label,
    TextEditingController ctrl,
    String unit, {
    bool enabled = true,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            SizedBox(
              width: 80,
              child: TextField(
                controller: ctrl,
                enabled: enabled,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  suffixText: unit,
                  isDense: true,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}
