import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vital_widgets.dart';

class BloodPressureScreen extends StatefulWidget {
  const BloodPressureScreen({super.key});
  @override
  State<BloodPressureScreen> createState() => _BloodPressureScreenState();
}

class _BloodPressureScreenState extends State<BloodPressureScreen> {
  final _ble = BleService();
  bool _loading = false;
  String _result = '';
  bool _settingEnabled = true;
  int _settingInterval = 30;
  bool _measuring = false;
  String _sbp = '--';
  String _dbp = '--';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    if (!context.read<BleProvider>().isConnected) return;
    try {
      final json = await _ble.getBloodPressureSetting();
      final m = jsonDecode(json);
      setState(() {
        _settingEnabled = m['enable'] ?? true;
        _settingInterval = m['interval'] ?? 30;
      });
    } catch (_) {}
  }

  Future<void> _fetchToday() async {
    setState(() { _loading = true; _result = ''; });
    try {
      final data = await _ble.getTodayBloodPressure();
      setState(() { _result = _pretty(data); _updateFromList(data); });
    } catch (e) {
      setState(() => _result = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _updateFromList(String jsonStr) {
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      for (final item in list.reversed) {
        final m = item as Map<String, dynamic>;
        final sbp = m['sbp'] ?? m['mSbp'] ?? m['systolic'] ?? 0;
        final dbp = m['dbp'] ?? m['mDbp'] ?? m['diastolic'] ?? 0;
        final s = (sbp as num).toInt(); final d = (dbp as num).toInt();
        if (s > 0 && d > 0) { _sbp = '$s'; _dbp = '$d'; return; }
      }
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      await _ble.setBloodPressureSetting(enable: _settingEnabled, interval: _settingInterval);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _toggleManual() async {
    final start = !_measuring;
    setState(() => _measuring = start);
    try {
      final result = await _ble.manualModeBP(start: start);
      setState(() {
        _result = _pretty(result);
        if (start) _updateFromSingle(result);
        else _measuring = false;
      });
    } catch (e) {
      setState(() { _measuring = !start; _result = 'Error: $e'; });
    }
  }

  void _updateFromSingle(String jsonStr) {
    try {
      final m = jsonDecode(jsonStr) as Map<String, dynamic>;
      final sbp = m['sbp'] ?? m['mSbp'] ?? m['systolic'] ?? 0;
      final dbp = m['dbp'] ?? m['mDbp'] ?? m['diastolic'] ?? 0;
      final s = (sbp as num).toInt(); final d = (dbp as num).toInt();
      if (s > 0 && d > 0) { _sbp = '$s'; _dbp = '$d'; }
    } catch (_) {}
    _measuring = false;
  }

  String _pretty(String raw) {
    try { return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw)); } catch (_) { return raw; }
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _darkBar('Blood Pressure'),
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
            _bpCard(),
            const SizedBox(height: 16),
            _chartCard(),
            const SizedBox(height: 16),
            const VitalStatsRow(avg: '--', min: '--', max: '--', unit: 'mmHg'),
            const SizedBox(height: 24),
            VitalOneClickButton(
              label: _measuring ? 'Stop Measurement' : 'One Click Measurement',
              isStop: _measuring,
              loading: _loading && _measuring,
              enabled: connected,
              onPressed: _toggleManual,
            ),
            const SizedBox(height: 12),
            _secondaryBtn("Today's Data", Icons.today_rounded, connected, _fetchToday),
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

  Widget _bpCard() {
    final isActive = _measuring || (_sbp != '--' && _dbp != '--');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.bpColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppTheme.bpColor.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: const Icon(Icons.water_drop_rounded, color: AppTheme.bpColor, size: 22),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('BLOOD PRESSURE', style: TextStyle(color: AppTheme.bpColor, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                  Text(_measuring ? 'Measuring…' : (isActive ? 'Latest reading' : 'Tap to measure'),
                      style: const TextStyle(color: AppTheme.textSec, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _BPValue(label: 'Systolic', value: _measuring ? '···' : _sbp, unit: 'mmHg')),
              Container(width: 1, height: 50, color: AppTheme.div),
              Expanded(child: _BPValue(label: 'Diastolic', value: _measuring ? '···' : _dbp, unit: 'mmHg')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chartCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('TODAY', style: TextStyle(color: AppTheme.textSec, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 12),
          SizedBox(height: 100, width: double.infinity, child: CustomPaint(painter: _BPChart())),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(children: [
                CircleAvatar(radius: 4, backgroundColor: AppTheme.bpColor),
                SizedBox(width: 4),
                Text('SBP', style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
              ]),
              const Row(children: [
                CircleAvatar(radius: 4, backgroundColor: Color(0xFF818CF8)),
                SizedBox(width: 4),
                Text('DBP', style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
              ]),
              ...const ['12am', '6am', '12pm', '6pm'].map((l) =>
                  Text(l, style: const TextStyle(color: Color(0xFF555555), fontSize: 10))),
            ],
          ),
        ],
      ),
    );
  }

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
                    Text('Monitors blood pressure automatically', style: TextStyle(color: AppTheme.textSec, fontSize: 12)),
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
                    items: [5, 10, 15, 30, 60].map((e) => DropdownMenuItem(value: e, child: Text('$e min'))).toList(),
                    onChanged: (v) => setState(() => _settingInterval = v ?? 30),
                  ),
                  const SizedBox(width: 8),
                  TextButton(onPressed: _saveSettings, child: const Text('Save', style: TextStyle(color: AppTheme.gold))),
                ],
              ),
            ],
          ],
        ),
      );

  Widget _secondaryBtn(String label, IconData icon, bool enabled, VoidCallback fn) =>
      _Btn(label: label, icon: icon, enabled: enabled, onTap: fn);

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

class _BPValue extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  const _BPValue({required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textSec, fontSize: 11)),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w700)),
        Text(unit, style: const TextStyle(color: AppTheme.textSec, fontSize: 11)),
      ],
    );
  }
}

class _BPChart extends CustomPainter {
  static const _sbp = [0.62,0.60,0.64,0.62,0.65,0.60,0.62,0.64,0.60,0.65,0.62,0.60];
  static const _dbp = [0.40,0.38,0.42,0.40,0.43,0.39,0.41,0.42,0.39,0.43,0.40,0.38];

  @override
  void paint(Canvas canvas, Size size) {
    _sparkLine(canvas, size, AppTheme.bpColor, _sbp);
    _sparkLine(canvas, size, const Color(0xFFA78BFA), _dbp);
  }

  void _sparkLine(Canvas canvas, Size size, Color color, List<double> d) {
    final step = size.width / (d.length - 1);
    final path = Path();
    for (int i = 0; i < d.length; i++) {
      final x = i * step;
      final y = size.height - d[i] * size.height * 0.82 - size.height * 0.05;
      if (i == 0) { path.moveTo(x, y); }
      else {
        final px = (i - 1) * step;
        final py = size.height - d[i - 1] * size.height * 0.82 - size.height * 0.05;
        path.cubicTo((px + x) / 2, py, (px + x) / 2, y, x, y);
      }
    }
    canvas.drawPath(path, Paint()..color = color..strokeWidth = 2..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
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
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;
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
