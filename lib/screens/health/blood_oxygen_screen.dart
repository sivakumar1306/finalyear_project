import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vital_widgets.dart';

class BloodOxygenScreen extends StatefulWidget {
  const BloodOxygenScreen({super.key});
  @override
  State<BloodOxygenScreen> createState() => _BloodOxygenScreenState();
}

class _BloodOxygenScreenState extends State<BloodOxygenScreen> {
  final _ble = BleService();
  bool _loading = false;
  String _result = '';
  bool _settingEnabled = true;
  int _settingInterval = 5;
  bool _measuring = false;
  String _spo2 = '--';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    if (!context.read<BleProvider>().isConnected) return;
    try {
      final json = await _ble.getBloodOxygenSetting();
      final m = jsonDecode(json);
      setState(() {
        _settingEnabled = m['enable'] ?? true;
        _settingInterval = m['interval'] ?? 5;
      });
    } catch (_) {}
  }

  Future<void> _fetchToday() async {
    setState(() { _loading = true; _result = ''; });
    try {
      final data = await _ble.getTodayBloodOxygen();
      setState(() => _result = _pretty(data));
    } catch (e) {
      setState(() => _result = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _syncInterval() async {
    setState(() { _loading = true; _result = ''; });
    try {
      final data = await _ble.syncIntervalBloodOxygen();
      setState(() => _result = _pretty(data));
    } catch (e) {
      setState(() => _result = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveSettings() async {
    try {
      await _ble.setBloodOxygenSetting(enable: _settingEnabled, interval: _settingInterval);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _toggleManual() async {
    final start = !_measuring;
    setState(() => _measuring = start);
    try {
      final result = await _ble.manualModeBloodOxygen(start: start);
      setState(() {
        _result = _pretty(result);
        if (start) {
          try {
            final m = jsonDecode(result) as Map<String, dynamic>;
            final v = (m['spo2'] as num?)?.toInt() ?? 0;
            if (v > 0) _spo2 = '$v';
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

  String _pretty(String raw) {
    try { return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw)); } catch (_) { return raw; }
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _darkBar('Blood Oxygen'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            const VitalDateSelector(),
            const SizedBox(height: 12),
            const VitalPeriodTabs(),
            const SizedBox(height: 24),
            _metricCard(),
            const SizedBox(height: 16),
            _chartCard(),
            const SizedBox(height: 16),
            const VitalStatsRow(avg: '--', min: '--', max: '--', unit: '%'),
            const SizedBox(height: 24),
            VitalOneClickButton(
              label: _measuring ? 'Stop Measurement' : 'One Click Measurement',
              isStop: _measuring,
              loading: _loading && _measuring,
              enabled: connected,
              onPressed: _toggleManual,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _Btn(label: "Today's Data", icon: Icons.today_rounded, enabled: connected, onTap: _fetchToday)),
              const SizedBox(width: 10),
              Expanded(child: _Btn(label: 'Sync Interval', icon: Icons.sync_rounded, enabled: connected, onTap: _syncInterval)),
            ]),
            const SizedBox(height: 16),
            _monitorCard(),
            if (_loading && !_measuring) _loader(),
            if (_result.isNotEmpty) _dataCard(),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _metricCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.spo2Color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(color: AppTheme.spo2Color.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: const Icon(Icons.bloodtype_rounded, color: AppTheme.spo2Color, size: 30),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('BLOOD OXYGEN (SpO2)',
                    style: TextStyle(color: AppTheme.spo2Color, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(_measuring ? '···' : _spo2,
                        style: const TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w700, height: 1.0)),
                    const SizedBox(width: 8),
                    const Text('%', style: TextStyle(color: AppTheme.textSec, fontSize: 16)),
                  ],
                ),
                Text(_measuring ? 'Measuring…' : 'Oxygen saturation',
                    style: const TextStyle(color: AppTheme.textSec, fontSize: 12)),
              ],
            ),
          ],
        ),
      );

  Widget _chartCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TODAY', style: TextStyle(color: AppTheme.textSec, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
            const SizedBox(height: 12),
            SizedBox(height: 100, width: double.infinity, child: CustomPaint(painter: _SpO2Chart())),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('95%', style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
                Text('97%', style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
                Text('99%', style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
                Text('100%', style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
              ],
            ),
          ],
        ),
      );

  Widget _monitorCard() => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.div)),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Auto Monitoring', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    SizedBox(height: 2),
                    Text('Monitors SpO2 automatically', style: TextStyle(color: AppTheme.textSec, fontSize: 12)),
                  ],
                )),
                Switch.adaptive(value: _settingEnabled, onChanged: (v) { setState(() => _settingEnabled = v); _saveSettings(); }),
              ],
            ),
            if (_settingEnabled) ...[
              const Divider(color: AppTheme.div, height: 16),
              Row(
                children: [
                  const Text('Interval', style: TextStyle(color: Colors.white, fontSize: 14)),
                  const Spacer(),
                  DropdownButton<int>(
                    value: _settingInterval,
                    dropdownColor: AppTheme.card2,
                    style: const TextStyle(color: Colors.white),
                    underline: const SizedBox(),
                    items: [1, 5, 10, 15, 30].map((e) => DropdownMenuItem(value: e, child: Text('$e min'))).toList(),
                    onChanged: (v) => setState(() => _settingInterval = v ?? 5),
                  ),
                  const SizedBox(width: 8),
                  TextButton(onPressed: _saveSettings, child: const Text('Save', style: TextStyle(color: AppTheme.gold))),
                ],
              ),
            ],
          ],
        ),
      );

  Widget _loader() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(color: AppTheme.gold, strokeWidth: 2)),
      );

  Widget _dataCard() => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppTheme.card2, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.div)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('DATA', style: TextStyle(color: AppTheme.textSec, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(_result, style: const TextStyle(fontFamily: 'monospace', color: AppTheme.textSec, fontSize: 11)),
            ),
          ],
        ),
      );
}

class _SpO2Chart extends CustomPainter {
  static const _d = [0.95,0.97,0.96,0.98,0.97,0.99,0.98,0.97,0.96,0.98,0.97,0.99,0.98,0.96,0.97,0.99];

  @override
  void paint(Canvas canvas, Size size) {
    final n = _d.length;
    final barW = size.width / n * 0.6;
    final gap = size.width / n * 0.4;
    for (int i = 0; i < n; i++) {
      final x = i * (barW + gap) + gap / 2;
      final barH = (_d[i] * size.height).clamp(4.0, size.height);
      canvas.drawRRect(
        RRect.fromLTRBR(x, size.height - barH, x + barW, size.height, const Radius.circular(3)),
        Paint()..color = AppTheme.spo2Color.withValues(alpha: 0.7 + _d[i] * 0.3),
      );
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

AppBar _darkBar(String title) => AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      actions: [IconButton(icon: const Icon(Icons.more_vert, color: Colors.white), onPressed: () {})],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Container(color: AppTheme.div, height: 0.5),
      ),
    );

class _Btn extends StatelessWidget {
  final String label; final IconData icon; final bool enabled; final VoidCallback? onTap;
  const _Btn({required this.label, required this.icon, required this.enabled, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.div)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: enabled ? AppTheme.gold : AppTheme.textSec, size: 18),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: enabled ? Colors.white : AppTheme.textSec, fontWeight: FontWeight.w500, fontSize: 14)),
            ],
          ),
        ),
      );
}
