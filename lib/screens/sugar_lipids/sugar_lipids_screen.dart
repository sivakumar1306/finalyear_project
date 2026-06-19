import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../widgets/data_card.dart';

class SugarLipidsScreen extends StatefulWidget {
  const SugarLipidsScreen({super.key});
  @override
  State<SugarLipidsScreen> createState() => _SugarLipidsScreenState();
}

class _SugarLipidsScreenState extends State<SugarLipidsScreen> {
  final _ble = BleService();
  bool _loading = false;
  String _result = '';

  Future<void> _fetch() async {
    setState(() { _loading = true; _result = ''; });
    try {
      final json = await _ble.getHealthSettings();
      final m = jsonDecode(json) ?? {};
      final sub = m['sugarLipids'] ?? {};
      setState(() => _result = const JsonEncoder.withIndent('  ').convert(sub));
    } catch (e) {
      setState(() => _result = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;
    return Scaffold(
      appBar: AppBar(title: const Text('Sugar & Lipids')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: DataCard(label: 'Blood Sugar', value: '--', unit: 'mmol/L', icon: Icons.science, color: Colors.teal)),
              const SizedBox(width: 8),
              Expanded(child: DataCard(label: 'Blood Lipids', value: '--', unit: 'mmol/L', icon: Icons.water_drop, color: Colors.cyan)),
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
                  const Text('Actions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: connected ? _fetch : null,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Fetch Data'),
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
