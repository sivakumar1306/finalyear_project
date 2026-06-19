import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';

class SportRecordScreen extends StatefulWidget {
  const SportRecordScreen({super.key});
  @override
  State<SportRecordScreen> createState() => _SportRecordScreenState();
}

class _SportRecordScreenState extends State<SportRecordScreen> {
  final _ble = BleService();
  bool _loading = false;
  List<dynamic> _records = [];

  @override
  void initState() {
    super.initState();
    if (context.read<BleProvider>().isConnected) _fetchRecords();
  }

  Future<void> _fetchRecords() async {
    setState(() { _loading = true; _records = []; });
    try {
      final data = await _ble.getSportRecords();
      final parsed = jsonDecode(data);
      setState(() => _records = parsed is List ? parsed : []);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sport Records'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: connected ? _fetchRecords : null,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sports, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text(
                        connected ? 'No sport records found' : 'Device not connected',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      if (connected)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: FilledButton.icon(
                            onPressed: _fetchRecords,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Load Records'),
                          ),
                        ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _records.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final rec = _records[i] as Map<String, dynamic>? ?? {};
                    return Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(10)),
                          child: Icon(Icons.sports, color: Colors.amber.shade700),
                        ),
                        title: Text('Sport #${i + 1}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(rec.toString()),
                      ),
                    );
                  },
                ),
    );
  }
}
