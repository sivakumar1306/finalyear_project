import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vital_widgets.dart';

class HeartRateScreen extends StatefulWidget {
  const HeartRateScreen({super.key});
  @override
  State<HeartRateScreen> createState() => _HeartRateScreenState();
}

class _HeartRateScreenState extends State<HeartRateScreen> {
  final _ble = BleService();
  bool _loading = false;
  String _result = '';
  bool _settingEnabled = true;
  int _settingInterval = 5;
  bool _measuring = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    if (!context.read<BleProvider>().isConnected) return;
    try {
      final json = await _ble.getHeartRateSetting();
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
      final data = await _ble.getTodayHeartRate();
      setState(() => _result = _pretty(data));
    } catch (e) {
      setState(() => _result = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveSettings() async {
    try {
      await _ble.setHeartRateSetting(enable: _settingEnabled, interval: _settingInterval);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _toggleManual() async {
    final start = !_measuring;
    setState(() => _measuring = start);
    try {
      final result = await _ble.manualModeHeart(start: start);
      setState(() { _result = _pretty(result); _measuring = false; });
    } catch (e) {
      setState(() { _measuring = false; _result = 'Error: $e'; });
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
      appBar: _darkBar('Heart Rate'),
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
            const VitalStatsRow(avg: '--', min: '--', max: '--', unit: 'bpm'),
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
            _monitoringCard(),
            if (_loading && !_measuring) _loader(),
            if (_result.isNotEmpty) _resultCard(),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _metricCard() => _VitalMetricCard(
        color: AppTheme.hrColor,
        icon: Icons.favorite_rounded,
        label: 'HEART RATE',
        value: _measuring ? '···' : '--',
        unit: 'bpm',
        status: _measuring ? 'Measuring…' : 'Latest reading',
      );

  Widget _chartCard() => _ChartCard(
        title: 'TODAY',
        chart: SizedBox(
          height: 100,
          width: double.infinity,
          child: CustomPaint(painter: _HRPainter()),
        ),
        xLabels: const ['12am', '6am', '12pm', '6pm'],
      );

  Widget _secondaryBtn(String label, IconData icon, bool enabled, VoidCallback fn) =>
      _SecondaryButton(label: label, icon: icon, enabled: enabled, onTap: fn);

  Widget _monitoringCard() => _MonitoringCard(
        title: 'Auto Monitoring',
        subtitle: 'Monitors heart rate automatically',
        enabled: _settingEnabled,
        interval: _settingInterval,
        intervalOptions: const [1, 5, 10, 15, 30, 60],
        onToggle: (v) { setState(() => _settingEnabled = v); _saveSettings(); },
        onIntervalChange: (v) => setState(() => _settingInterval = v ?? 5),
        onSave: _saveSettings,
      );

  Widget _loader() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(color: AppTheme.gold, strokeWidth: 2)),
      );

  Widget _resultCard() => _DataCard(data: _result);
}

// ── Blood Pressure ──────────────────────────────────────────────────────────

class _HRPainter extends CustomPainter {
  static const _d = [0.45,0.48,0.50,0.55,0.52,0.60,0.55,0.50,0.48,0.52,0.58,0.54,0.50,0.56,0.62,0.58,0.52,0.50,0.55,0.60];
  @override
  void paint(Canvas canvas, Size size) => _spark(canvas, size, AppTheme.hrColor, _d);
  @override
  bool shouldRepaint(_) => false;
}

// ── Shared private helpers (file-scope) ─────────────────────────────────────

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

void _spark(Canvas canvas, Size size, Color color, List<double> d) {
  if (d.length < 2) return;
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
  canvas.drawPath(
    Path()..addPath(path, Offset.zero)..lineTo(size.width, size.height)..lineTo(0, size.height)..close(),
    Paint()..shader = LinearGradient(
      colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.0)],
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
  );
}

// ── Reusable private widgets (file-scope) ───────────────────────────────────

class _VitalMetricCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final String status;

  const _VitalMetricCard({
    required this.color, required this.icon, required this.label,
    required this.value, required this.unit, required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value, style: const TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w700, height: 1.0)),
                  const SizedBox(width: 8),
                  Text(unit, style: const TextStyle(color: AppTheme.textSec, fontSize: 16)),
                ],
              ),
              Text(status, style: const TextStyle(color: AppTheme.textSec, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final Widget chart;
  final List<String> xLabels;

  const _ChartCard({required this.title, required this.chart, required this.xLabels});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppTheme.textSec, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 12),
          chart,
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: xLabels.map((l) => Text(l, style: const TextStyle(color: Color(0xFF555555), fontSize: 10))).toList(),
          ),
        ],
      ),
    );
  }
}

class _MonitoringCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool enabled;
  final int interval;
  final List<int> intervalOptions;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int?> onIntervalChange;
  final VoidCallback onSave;

  const _MonitoringCard({
    required this.title, required this.subtitle, required this.enabled,
    required this.interval, required this.intervalOptions,
    required this.onToggle, required this.onIntervalChange, required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.div),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: AppTheme.textSec, fontSize: 12)),
                  ],
                ),
              ),
              Switch.adaptive(value: enabled, onChanged: onToggle),
            ],
          ),
          if (enabled) ...[
            const Divider(color: AppTheme.div, height: 16),
            Row(
              children: [
                const Text('Interval', style: TextStyle(color: Colors.white, fontSize: 14)),
                const Spacer(),
                DropdownButton<int>(
                  value: interval,
                  dropdownColor: AppTheme.card2,
                  style: const TextStyle(color: Colors.white),
                  underline: const SizedBox(),
                  items: intervalOptions.map((e) => DropdownMenuItem(value: e, child: Text('$e min'))).toList(),
                  onChanged: onIntervalChange,
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onSave,
                  child: const Text('Save', style: TextStyle(color: AppTheme.gold)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  const _SecondaryButton({required this.label, required this.icon, required this.enabled, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.div),
        ),
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
}

class _DataCard extends StatelessWidget {
  final String data;
  const _DataCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.div),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('DATA', style: TextStyle(color: AppTheme.textSec, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(data, style: const TextStyle(fontFamily: 'monospace', color: AppTheme.textSec, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
