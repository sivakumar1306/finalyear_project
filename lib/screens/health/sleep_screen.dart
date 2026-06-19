import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vital_widgets.dart';

class SleepScreen extends StatefulWidget {
  const SleepScreen({super.key});
  @override
  State<SleepScreen> createState() => _SleepScreenState();
}

class _SleepScreenState extends State<SleepScreen> {
  final _ble = BleService();
  bool _loading = false;
  String _result = '';

  Future<void> _fetchToday() async {
    setState(() { _loading = true; _result = ''; });
    try {
      final data = await _ble.getTodaySleep();
      setState(() => _result = _pretty(data));
    } catch (e) {
      setState(() => _result = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _syncSleep() async {
    setState(() { _loading = true; _result = ''; });
    try {
      final data = await _ble.syncSleep();
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
      appBar: _darkBar('Sleep'),
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
            _scoreCard(),
            const SizedBox(height: 16),
            _stagesCard(),
            const SizedBox(height: 16),
            _qualityRow(),
            const SizedBox(height: 24),
            _Btn(label: "Load Sleep Data", icon: Icons.bedtime_rounded, enabled: connected, onTap: _fetchToday),
            const SizedBox(height: 10),
            _Btn(label: 'Sync Sleep', icon: Icons.sync_rounded, enabled: connected, onTap: _syncSleep),
            if (_loading) _loader(),
            if (_result.isNotEmpty) _dataCard(),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _scoreCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.sleepColor.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            // Score circle
            SizedBox(
              width: 90,
              height: 90,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 90,
                    height: 90,
                    child: CircularProgressIndicator(
                      value: 0.0,
                      strokeWidth: 8,
                      backgroundColor: AppTheme.card2,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.sleepColor),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('--', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
                      Text('Score', style: TextStyle(color: AppTheme.sleepColor, fontSize: 10, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TOTAL DURATION', style: TextStyle(color: AppTheme.textSec, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1)),
                  const SizedBox(height: 4),
                  const Text('-h --m', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Wear device to monitor sleep',
                      style: TextStyle(color: AppTheme.textSec.withValues(alpha: 0.7), fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _stagesCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('SLEEP STAGES', style: TextStyle(color: AppTheme.textSec, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
            const SizedBox(height: 16),
            _Stage(label: 'Awake', value: '--m', progress: 0.0, color: const Color(0xFFFBBF24)),
            const SizedBox(height: 12),
            _Stage(label: 'Light Sleep', value: '-h --m', progress: 0.0, color: const Color(0xFF60A5FA)),
            const SizedBox(height: 12),
            _Stage(label: 'Deep Sleep', value: '-h --m', progress: 0.0, color: AppTheme.sleepColor),
            const SizedBox(height: 16),
            // Sleep timeline bar
            const Text('SLEEP TIMELINE', style: TextStyle(color: AppTheme.textSec, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 24,
                child: CustomPaint(painter: _SleepTimeline()),
              ),
            ),
            const SizedBox(height: 6),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('10pm', style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
                Text('12am', style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
                Text('2am',  style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
                Text('4am',  style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
                Text('6am',  style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
              ],
            ),
          ],
        ),
      );

  Widget _qualityRow() => Row(
        children: [
          Expanded(
            child: _QualityBox(label: 'SLEEP EFFICIENCY', value: '--%', description: 'Time asleep vs in bed'),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QualityBox(label: 'SLEEP QUALITY', value: '--', description: 'Based on stages'),
          ),
        ],
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

class _Stage extends StatelessWidget {
  final String label; final String value; final double progress; final Color color;
  const _Stage({required this.label, required this.value, required this.progress, required this.color});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                    Text(value, style: const TextStyle(color: AppTheme.textSec, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: AppTheme.card2,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  borderRadius: BorderRadius.circular(4),
                  minHeight: 6,
                ),
              ],
            ),
          ),
        ],
      );
}

class _QualityBox extends StatelessWidget {
  final String label; final String value; final String description;
  const _QualityBox({required this.label, required this.value, required this.description});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.div)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppTheme.textSec, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1)),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(description, style: const TextStyle(color: AppTheme.textSec, fontSize: 10)),
          ],
        ),
      );
}

class _SleepTimeline extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Demo: show approximate sleep stages as color bands
    final segments = [
      (0.0, 0.05, const Color(0xFFFBBF24)),   // awake
      (0.05, 0.25, const Color(0xFF60A5FA)),   // light
      (0.25, 0.50, AppTheme.sleepColor),       // deep
      (0.50, 0.70, const Color(0xFF60A5FA)),   // light
      (0.70, 0.85, AppTheme.sleepColor),       // deep
      (0.85, 0.95, const Color(0xFF60A5FA)),   // light
      (0.95, 1.0, const Color(0xFFFBBF24)),    // awake
    ];
    for (final seg in segments) {
      canvas.drawRect(
        Rect.fromLTRB(seg.$1 * size.width, 0, seg.$2 * size.width, size.height),
        Paint()..color = seg.$3,
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
