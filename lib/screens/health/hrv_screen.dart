import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../widgets/data_card.dart';

class HrvScreen extends StatefulWidget {
  const HrvScreen({super.key});
  @override
  State<HrvScreen> createState() => _HrvScreenState();
}

class _HrvScreenState extends State<HrvScreen> {
  final _ble = BleService();
  bool _loading = false;
  String _result = '';

  Future<void> _fetchToday() async {
    setState(() { _loading = true; _result = ''; });
    try {
      final data = await _ble.getTodayHrv();
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
      appBar: AppBar(title: const Text('HRV (Heart Rate Variability)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DataCard(label: 'HRV', value: '--', unit: 'ms', icon: Icons.monitor_heart, color: Colors.teal),
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
                      ElevatedButton.icon(onPressed: connected ? _fetchToday : null, icon: const Icon(Icons.today), label: const Text('Today\'s HRV')),
                      ElevatedButton.icon(
                        onPressed: connected ? () async {
                          setState(() { _loading = true; _result = ''; });
                          try {
                            final data = await _ble.getHrv(0);
                            setState(() => _result = _prettyJson(data));
                          } catch (e) {
                            setState(() => _result = 'Error: $e');
                          } finally {
                            setState(() => _loading = false);
                          }
                        } : null,
                        icon: const Icon(Icons.history),
                        label: const Text('Yesterday'),
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
