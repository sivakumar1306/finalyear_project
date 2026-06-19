import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../widgets/data_card.dart';

class StepsScreen extends StatefulWidget {
  const StepsScreen({super.key});
  @override
  State<StepsScreen> createState() => _StepsScreenState();
}

class _StepsScreenState extends State<StepsScreen> {
  final _ble = BleService();
  bool _loading = false;
  String _result = '';
  String _steps = '--';
  String _calories = '--';
  String _distance = '--';

  Future<void> _fetchToday() async {
    setState(() { _loading = true; _result = ''; });
    try {
      final data = await _ble.getTodaySteps();
      setState(() {
        _result = _prettyJson(data);
        _updateCardsFromSteps(data);
      });
    } catch (e) {
      setState(() => _result = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _updateCardsFromSteps(String jsonStr) {
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      int totalSteps = 0;
      int totalCalories = 0;
      double totalDistance = 0;
      for (final item in list) {
        final m = item as Map<String, dynamic>;
        final walk = (m['walkSteps'] as num? ?? 0).toInt();
        final run  = (m['runSteps']  as num? ?? 0).toInt();
        final c = m['calorie'] ?? m['calories'] ?? 0;
        final d = m['distance'] ?? 0;
        totalSteps += walk + run;
        totalCalories += (c as num).toInt();
        totalDistance += (d as num).toDouble();
      }
      if (totalSteps > 0 || totalCalories > 0 || totalDistance > 0) {
        _steps = '$totalSteps';
        _calories = '$totalCalories';
        _distance = totalDistance >= 1000
            ? '${(totalDistance / 1000).toStringAsFixed(2)}'
            : '${totalDistance.toStringAsFixed(0)}m';
      }
    } catch (_) {}
  }

  Future<void> _syncDetails() async {
    setState(() { _loading = true; _result = ''; });
    try {
      final data = await _ble.syncStepDetails();
      setState(() => _result = _prettyJson(data));
    } catch (e) {
      setState(() => _result = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  String _prettyJson(String raw) {
    try { return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw)); } catch (_) { return raw; }
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;
    return Scaffold(
      appBar: AppBar(title: const Text('Steps')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: DataCard(label: 'Steps', value: _steps, icon: Icons.directions_walk, color: Colors.green)),
              const SizedBox(width: 8),
              Expanded(child: DataCard(label: 'Calories', value: _calories, unit: 'kcal', icon: Icons.local_fire_department, color: Colors.orange)),
            ],
          ),
          const SizedBox(height: 8),
          DataCard(label: 'Distance', value: _distance, icon: Icons.straighten, color: Colors.teal),
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
                      ElevatedButton.icon(onPressed: connected ? _fetchToday : null, icon: const Icon(Icons.today), label: const Text('Today\'s Steps')),
                      ElevatedButton.icon(onPressed: connected ? _syncDetails : null, icon: const Icon(Icons.sync), label: const Text('Sync Details')),
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
