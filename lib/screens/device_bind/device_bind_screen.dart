import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';

class DeviceBindScreen extends StatefulWidget {
  const DeviceBindScreen({super.key});
  @override
  State<DeviceBindScreen> createState() => _DeviceBindScreenState();
}

class _DeviceBindScreenState extends State<DeviceBindScreen> {
  final _filterController = TextEditingController();
  Timer? _scanTimer;
  String? _connectingAddress;
  String? _permissionError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _filterController.dispose();
    context.read<BleProvider>().stopScan();
    super.dispose();
  }

  Future<bool> _requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final denied = statuses.entries
        .where((e) => e.value.isDenied || e.value.isPermanentlyDenied)
        .map((e) => e.key.toString().split('.').last)
        .toList();

    if (denied.isNotEmpty) {
      setState(() => _permissionError =
          'Missing permissions: ${denied.join(', ')}.\nPlease grant them in Settings.');
      return false;
    }
    setState(() => _permissionError = null);
    return true;
  }

  Future<void> _startScan() async {
    if (!await _requestPermissions()) return;
    if (!mounted) return;
    final ble = context.read<BleProvider>();
    await ble.startScan(filterName: _filterController.text.trim());
    _scanTimer?.cancel();
    _scanTimer = Timer(const Duration(seconds: 20), () {
      if (mounted) ble.stopScan();
    });
  }

  Future<void> _connect(ScannedDevice device) async {
    setState(() => _connectingAddress = device.address);
    final ble = context.read<BleProvider>();
    final ok = await ble.connect(device);
    if (!mounted) return;
    setState(() => _connectingAddress = null);
    if (ok) {
      ble.syncAllFromRing();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Connected to ${device.name}'),
        backgroundColor: Colors.green,
      ));
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Connection failed. Make sure ring is nearby and awake.'),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Scan & Bind Device')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _filterController,
                    decoration: InputDecoration(
                      hintText: 'Filter by name (optional)',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: ble.isScanning ? null : _startScan,
                  icon: ble.isScanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.bluetooth_searching),
                  label: Text(ble.isScanning ? 'Scanning...' : 'Scan'),
                ),
              ],
            ),
          ),
          if (_permissionError != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _permissionError!,
                      style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: openAppSettings,
                    child: const Text('Open Settings'),
                  ),
                ],
              ),
            ),
          if (ble.isScanning) const LinearProgressIndicator(),
          Expanded(
            child: ble.scannedDevices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bluetooth, size: 60, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          ble.isScanning
                              ? 'Scanning for devices...'
                              : 'No devices found.\nTap Scan to search again.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        if (!ble.isScanning) ...[
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _startScan,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Try Again'),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Make sure your ring is worn or charging\nand Bluetooth + Location are on.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: ble.scannedDevices.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final dev = ble.scannedDevices[i];
                      final isConnecting = _connectingAddress == dev.address;
                      return ListTile(
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.watch, color: Colors.blue.shade700),
                        ),
                        title: Text(dev.name.isNotEmpty ? dev.name : 'Unknown Device'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(dev.address, style: const TextStyle(fontSize: 12)),
                            Row(
                              children: [
                                Icon(Icons.signal_cellular_alt,
                                    size: 12, color: _rssiColor(dev.rssi)),
                                const SizedBox(width: 2),
                                Text(
                                  '${dev.rssi} dBm',
                                  style: TextStyle(
                                      fontSize: 11, color: _rssiColor(dev.rssi)),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: isConnecting
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : ElevatedButton(
                                onPressed: () => _connect(dev),
                                child: const Text('Connect'),
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color _rssiColor(int rssi) {
    if (rssi >= -60) return Colors.green;
    if (rssi >= -80) return Colors.orange;
    return Colors.red;
  }
}
