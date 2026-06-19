import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vital_widgets.dart';

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
      setState(() => _result = _pretty(data));
    } catch (e) {
      setState(() => _result = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _fetchYesterday() async {
    setState(() { _loading = true; _result = ''; });
    try {
      final data = await _ble.getHrv(0);
      setState(() => _result = _pretty(data));
    } catch (e) {
      setState(() => _result = 'Error: $e');
    } finally {
      setState(() => _loading = false);
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
      appBar: _darkBar('HRV'),
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
            const VitalStatsRow(avg: '--', min: '--', max: '--', unit: 'ms'),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: _Btn(label: "Today's HRV", icon: Icons.today_rounded, enabled: connected, onTap: _fetchToday)),
              const SizedBox(width: 10),
              Expanded(child: _Btn(label: 'Yesterday', icon: Icons.history_rounded, enabled: connected, onTap: _fetchYesterday)),
            ]),
            if (_loading) _loader(),
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
          border: Border.all(color: AppTheme.hrvColor.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(color: AppTheme.hrvColor.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: const Icon(Icons.monitor_heart_rounded, color: AppTheme.hrvColor, size: 30),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('HEART RATE VARIABILITY',
                    style: TextStyle(color: AppTheme.hrvColor, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const Text('--', style: TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w700, height: 1.0)),
                    const SizedBox(width: 8),
                    const Text('ms', style: TextStyle(color: AppTheme.textSec, fontSize: 16)),
                  ],
                ),
                const Text('Load data to see readings', style: TextStyle(color: AppTheme.textSec, fontSize: 12)),
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
            SizedBox(height: 100, width: double.infinity, child: CustomPaint(painter: _HRVChart())),
            const SizedBox(height: 8),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('12am', style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
                Text('6am',  style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
                Text('12pm', style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
                Text('6pm',  style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
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

class _HRVChart extends CustomPainter {
  static const _d = [0.50,0.55,0.48,0.62,0.58,0.45,0.52,0.60,0.55,0.50,0.58,0.52,0.65,0.60,0.55,0.50,0.58,0.62,0.56,0.50];

  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / (_d.length - 1);
    final path = Path();
    for (int i = 0; i < _d.length; i++) {
      final x = i * step;
      final y = size.height - _d[i] * size.height * 0.82 - size.height * 0.05;
      if (i == 0) { path.moveTo(x, y); }
      else {
        final px = (i - 1) * step;
        final py = size.height - _d[i - 1] * size.height * 0.82 - size.height * 0.05;
        path.cubicTo((px + x) / 2, py, (px + x) / 2, y, x, y);
      }
    }
    canvas.drawPath(path, Paint()..color = AppTheme.hrvColor..strokeWidth = 2..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
    canvas.drawPath(
      Path()..addPath(path, Offset.zero)..lineTo(size.width, size.height)..lineTo(0, size.height)..close(),
      Paint()..shader = LinearGradient(
        colors: [AppTheme.hrvColor.withValues(alpha: 0.28), AppTheme.hrvColor.withValues(alpha: 0.0)],
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
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
