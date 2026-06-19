import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/section_tile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BleProvider>().checkConnection();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('QRing'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ble.checkConnection(),
            tooltip: 'Refresh connection',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ble.checkConnection(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _DeviceHeader(ble: ble),
            const SizedBox(height: 20),
            _sectionLabel('Health Data'),
            _healthTiles(context),
            const SizedBox(height: 12),
            _sectionLabel('Device Settings'),
            _settingsTiles(context),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
      );

  Widget _healthTiles(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            SectionTile(title: 'Heart Rate', icon: Icons.favorite, iconColor: Colors.red, onTap: () => Navigator.pushNamed(context, '/heart-rate')),
            const Divider(height: 1, indent: 56),
            SectionTile(title: 'Blood Pressure', icon: Icons.water_drop, iconColor: Colors.indigo, onTap: () => Navigator.pushNamed(context, '/blood-pressure')),
            const Divider(height: 1, indent: 56),
            SectionTile(title: 'Blood Oxygen (SpO2)', icon: Icons.bloodtype, iconColor: Colors.blue, onTap: () => Navigator.pushNamed(context, '/blood-oxygen')),
            const Divider(height: 1, indent: 56),
            SectionTile(title: 'Steps', icon: Icons.directions_walk, iconColor: Colors.green, onTap: () => Navigator.pushNamed(context, '/steps')),
            const Divider(height: 1, indent: 56),
            SectionTile(title: 'Sleep', icon: Icons.bedtime, iconColor: Colors.purple, onTap: () => Navigator.pushNamed(context, '/sleep')),
            const Divider(height: 1, indent: 56),
            SectionTile(title: 'HRV', icon: Icons.monitor_heart, iconColor: Colors.teal, onTap: () => Navigator.pushNamed(context, '/hrv')),
            const Divider(height: 1, indent: 56),
            SectionTile(title: 'Stress / Pressure', icon: Icons.psychology, iconColor: Colors.orange, onTap: () => Navigator.pushNamed(context, '/pressure')),
            const Divider(height: 1, indent: 56),
            SectionTile(title: 'Temperature', icon: Icons.thermostat, iconColor: Colors.deepOrange, onTap: () => Navigator.pushNamed(context, '/temperature')),
            const Divider(height: 1, indent: 56),
            SectionTile(title: 'Sport Records', icon: Icons.sports, iconColor: Colors.amber.shade700, onTap: () => Navigator.pushNamed(context, '/sport-record')),
          ],
        ),
      );

  Widget _settingsTiles(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            SectionTile(title: 'Device Settings', icon: Icons.settings, onTap: () => Navigator.pushNamed(context, '/device-settings')),
            const Divider(height: 1, indent: 56),
            SectionTile(title: 'Firmware Update (OTA)', icon: Icons.system_update, iconColor: Colors.blue.shade700, onTap: () => Navigator.pushNamed(context, '/ota')),
          ],
        ),
      );
}

class _DeviceHeader extends StatelessWidget {
  final BleProvider ble;
  const _DeviceHeader({required this.ble});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF1976D2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.blue.shade200, blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ble.deviceName.isEmpty ? 'No Device' : ble.deviceName,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    if (ble.deviceAddress.isNotEmpty)
                      Text(ble.deviceAddress, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              StatusBadge(connected: ble.isConnected),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _infoChip(Icons.battery_full, ble.battery >= 0 ? '${ble.battery}%' : '--'),
              const SizedBox(width: 12),
              _infoChip(Icons.memory, ble.firmwareVersion['firmware'] ?? '--'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  context,
                  icon: Icons.bluetooth_searching,
                  label: 'Scan & Bind',
                  onTap: () => Navigator.pushNamed(context, '/device-bind'),
                ),
              ),
              const SizedBox(width: 8),
              if (ble.isConnected)
                Expanded(
                  child: _actionButton(
                    context,
                    icon: Icons.bluetooth_disabled,
                    label: 'Disconnect',
                    onTap: () async {
                      await ble.disconnect();
                    },
                    color: Colors.red.shade300,
                  ),
                ),
              if (!ble.isConnected && ble.deviceAddress.isNotEmpty)
                Expanded(
                  child: _actionButton(
                    context,
                    icon: Icons.bluetooth_connected,
                    label: 'Reconnect',
                    onTap: () => ble.checkConnection(),
                    color: Colors.green.shade300,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) => Row(
        children: [
          Icon(icon, color: Colors.white70, size: 16),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      );

  Widget _actionButton(BuildContext context, {required IconData icon, required String label, required VoidCallback onTap, Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: color ?? Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
