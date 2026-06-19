import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../widgets/data_card.dart';

class PressureScreen extends StatefulWidget {
  const PressureScreen({super.key});
  @override
  State<PressureScreen> createState() => _PressureScreenState();
}

class _PressureScreenState extends State<PressureScreen> {
  final _ble = BleService();
  bool _loading = false;
  String _result = '';
  bool _measuring = false;
  String _stressLevel = '--';

  Future<void> _fetchToday() async {
    setState(() { _loading = true; _result = ''; });
    try {
      final data = await _ble.getTodayPressure();
      setState(() => _result = _prettyJson(data));
    } catch (e) {
      setState(() => _result = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleManual() async {
    final start = !_measuring;
    setState(() => _measuring = start);
    try {
      final result = await _ble.manualModePressure(start: start);
      setState(() {
        _result = _prettyJson(result);
        if (start) {
          try {
            final m = jsonDecode(result) as Map<String, dynamic>;
            final v = (m['value'] as num?)?.toInt() ?? 0;
            if (v > 0) _stressLevel = '$v';
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
      appBar: AppBar(title: const Text('Stress / Pressure')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DataCard(label: 'Stress Level', value: _stressLevel, icon: Icons.psychology, color: Colors.orange),
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
