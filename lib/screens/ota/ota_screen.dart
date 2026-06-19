import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';

class OtaScreen extends StatefulWidget {
  const OtaScreen({super.key});
  @override
  State<OtaScreen> createState() => _OtaScreenState();
}

class _OtaScreenState extends State<OtaScreen> {
  final _ble = BleService();
  String? _selectedFilePath;
  String? _selectedFileName;
  bool _updating = false;
  int _progress = 0;
  String _status = '';
  StreamSubscription? _eventSub;

  @override
  void initState() {
    super.initState();
    _eventSub = _ble.events.listen((event) {
      if (event['type'] == 'otaProgress') {
        final data = event['data'] as Map;
        setState(() => _progress = data['progress'] as int? ?? 0);
      }
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['bin'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedFilePath = result.files.single.path;
        _selectedFileName = result.files.single.name;
        _status = '';
      });
    }
  }

  Future<void> _startUpdate() async {
    if (_selectedFilePath == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start OTA Update?'),
        content: Text('File: $_selectedFileName\n\nDo not disconnect during the update.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Update')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() { _updating = true; _progress = 0; _status = 'Starting update...'; });
    try {
      await _ble.startOta(_selectedFilePath!);
      setState(() { _status = 'Update complete!'; _updating = false; });
    } catch (e) {
      setState(() { _status = 'Update failed: $e'; _updating = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;
    final ble = context.watch<BleProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('OTA Firmware Update')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Device Info', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    _infoRow('Connection', connected ? 'Connected' : 'Disconnected'),
                    _infoRow('Device', ble.deviceName.isEmpty ? '--' : ble.deviceName),
                    _infoRow('Firmware', ble.firmwareVersion['firmware'] ?? '--'),
                    _infoRow('Hardware', ble.firmwareVersion['hardware'] ?? '--'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Firmware File', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    if (_selectedFileName != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.file_present, color: Colors.blue),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_selectedFileName!, style: const TextStyle(fontWeight: FontWeight.w500)),
                            ),
                          ],
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: _updating ? null : _pickFile,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Select .bin File'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_updating || _progress > 0) ...[
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Progress', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text('$_progress%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _progress / 100,
                          minHeight: 12,
                          backgroundColor: Colors.grey.shade200,
                        ),
                      ),
                      if (_status.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(_status, style: TextStyle(
                          color: _status.contains('failed') ? Colors.red : Colors.green,
                          fontWeight: FontWeight.w500,
                        )),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            FilledButton.icon(
              onPressed: connected && _selectedFilePath != null && !_updating ? _startUpdate : null,
              icon: _updating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.system_update),
              label: Text(_updating ? 'Updating...' : 'Start Update'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            if (!connected)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Connect to a device before starting OTA update.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: Colors.grey.shade600)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      );
}
