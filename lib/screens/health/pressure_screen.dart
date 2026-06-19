import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vital_widgets.dart';

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
      setState(() => _result = _pretty(data));
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
        _result = _pretty(result);
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

  String _pretty(String raw) {
    try { return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw)); } catch (_) { return raw; }
  }

  String get _stressLabel {
    final v = int.tryParse(_stressLevel) ?? 0;
    if (v == 0) return 'Tap to measure';
    if (v < 40) return 'Relaxed';
    if (v < 60) return 'Normal';
    if (v < 80) return 'Elevated';
    return 'High';
  }

  Color get _stressColor {
    final v = int.tryParse(_stressLevel) ?? 0;
    if (v == 0) return AppTheme.textSec;
    if (v < 40) return AppTheme.success;
    if (v < 60) return AppTheme.stepsColor;
    if (v < 80) return AppTheme.stressColor;
    return AppTheme.danger;
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _darkBar('Stress / Pressure'),
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
            const VitalStatsRow(avg: '--', min: '--', max: '--'),
            const SizedBox(height: 24),
            VitalOneClickButton(
              label: _measuring ? 'Stop Measurement' : 'One Click Measurement',
              isStop: _measuring,
              loading: _loading && _measuring,
              enabled: connected,
              onPressed: _toggleManual,
            ),
            const SizedBox(height: 12),
            _Btn(label: "Today's Data", icon: Icons.today_rounded, enabled: connected, onTap: _fetchToday),
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
          border: Border.all(color: AppTheme.stressColor.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(color: AppTheme.stressColor.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: const Icon(Icons.psychology_rounded, color: AppTheme.stressColor, size: 30),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('STRESS LEVEL', style: TextStyle(color: AppTheme.stressColor, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                const SizedBox(height: 4),
                Text(_measuring ? '···' : _stressLevel,
                    style: const TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w700, height: 1.0)),
                Text(_measuring ? 'Measuring…' : _stressLabel,
                    style: TextStyle(color: _stressColor, fontSize: 12, fontWeight: FontWeight.w600)),
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
            // Y-axis labels
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: const [
                    Text('100', style: TextStyle(color: Color(0xFF555555), fontSize: 9)),
                    SizedBox(height: 24),
                    Text('80', style: TextStyle(color: Color(0xFF555555), fontSize: 9)),
                    SizedBox(height: 24),
                    Text('60', style: TextStyle(color: Color(0xFF555555), fontSize: 9)),
                    SizedBox(height: 24),
                    Text('40', style: TextStyle(color: Color(0xFF555555), fontSize: 9)),
                  ],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 120,
                    child: CustomPaint(painter: _StressChart()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('9pm',  style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
                Text('11pm', style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
                Text('1am',  style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
                Text('3am',  style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
                Text('5am',  style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
              ],
            ),
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

class _StressChart extends CustomPainter {
  static const _d = [0.35,0.42,0.38,0.50,0.55,0.42,0.38,0.45,0.58,0.48,0.40,0.35,0.42,0.50,0.38,0.32];
  static const _colors = [
    Color(0xFF34D399), Color(0xFF34D399), Color(0xFF6EE7B7),
    Color(0xFFFBBF24), Color(0xFFF97316), Color(0xFFFBBF24),
    Color(0xFF6EE7B7), Color(0xFFFBBF24), Color(0xFFEF4444),
    Color(0xFFF97316), Color(0xFFFBBF24), Color(0xFF34D399),
    Color(0xFF34D399), Color(0xFFFBBF24), Color(0xFF6EE7B7),
    Color(0xFF34D399),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final n = _d.length;
    final barW = size.width / n * 0.6;
    final gap = size.width / n * 0.4;
    for (int i = 0; i < n; i++) {
      final x = i * (barW + gap) + gap / 2;
      final barH = (_d[i] * size.height * 0.9).clamp(3.0, size.height);
      canvas.drawRRect(
        RRect.fromLTRBR(x, size.height - barH, x + barW, size.height, const Radius.circular(3)),
        Paint()..color = i < _colors.length ? _colors[i] : AppTheme.stressColor,
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
