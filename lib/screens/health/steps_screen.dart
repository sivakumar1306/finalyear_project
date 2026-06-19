import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vital_widgets.dart';

class StepsScreen extends StatefulWidget {
  const StepsScreen({super.key});
  @override
  State<StepsScreen> createState() => _StepsScreenState();
}

class _StepsScreenState extends State<StepsScreen> {
  final _ble = BleService();
  bool _loading = false;
  String _result = '';
  String _steps = '--';
  String _calories = '--';
  String _distance = '--';

  Future<void> _fetchToday() async {
    setState(() { _loading = true; _result = ''; });
    try {
      final data = await _ble.getTodaySteps();
      setState(() { _result = _pretty(data); _updateCards(data); });
    } catch (e) {
      setState(() => _result = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _updateCards(String jsonStr) {
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      int totalSteps = 0, totalCal = 0;
      double totalDist = 0;
      for (final item in list) {
        final m = item as Map<String, dynamic>;
        totalSteps += ((m['walkSteps'] as num? ?? 0) + (m['runSteps'] as num? ?? 0)).toInt();
        totalCal += ((m['calorie'] ?? m['calories'] ?? 0) as num).toInt();
        totalDist += ((m['distance'] ?? 0) as num).toDouble();
      }
      if (totalSteps > 0 || totalCal > 0 || totalDist > 0) {
        _steps = '$totalSteps';
        _calories = '$totalCal';
        _distance = totalDist >= 1000
            ? '${(totalDist / 1000).toStringAsFixed(2)} km'
            : '${totalDist.toStringAsFixed(0)} m';
      }
    } catch (_) {}
  }

  Future<void> _syncDetails() async {
    setState(() { _loading = true; _result = ''; });
    try {
      final data = await _ble.syncStepDetails();
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
      appBar: _darkBar('Steps & Activity'),
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
            _summaryRow(),
            const SizedBox(height: 16),
            _chartCard(),
            const SizedBox(height: 16),
            _distanceCard(),
            const SizedBox(height: 24),
            _Btn(label: "Load Today's Steps", icon: Icons.directions_walk_rounded, enabled: connected, onTap: _fetchToday),
            const SizedBox(height: 10),
            _Btn(label: 'Sync Step Details', icon: Icons.sync_rounded, enabled: connected, onTap: _syncDetails),
            if (_loading) _loader(),
            if (_result.isNotEmpty) _dataCard(),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow() => Row(
        children: [
          Expanded(child: _StatBox(label: 'STEPS', value: _steps, icon: Icons.directions_walk_rounded, color: AppTheme.stepsColor)),
          const SizedBox(width: 10),
          Expanded(child: _StatBox(label: 'CALORIES', value: _calories, icon: Icons.local_fire_department_rounded, color: AppTheme.hrColor)),
          const SizedBox(width: 10),
          Expanded(child: _StatBox(label: 'DISTANCE', value: _distance, icon: Icons.straighten_rounded, color: AppTheme.hrvColor)),
        ],
      );

  Widget _chartCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('STEPS BY HOUR', style: TextStyle(color: AppTheme.textSec, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
                Text('Total: $_steps', style: const TextStyle(color: AppTheme.stepsColor, fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(height: 100, width: double.infinity, child: CustomPaint(painter: _StepsChart())),
            const SizedBox(height: 8),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('6am', style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
                Text('9am', style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
                Text('12pm', style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
                Text('3pm', style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
                Text('6pm', style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
                Text('9pm', style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
              ],
            ),
          ],
        ),
      );

  Widget _distanceCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.div),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: AppTheme.hrvColor.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: const Icon(Icons.route_rounded, color: AppTheme.hrvColor, size: 22),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TOTAL DISTANCE', style: TextStyle(color: AppTheme.textSec, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1)),
                Text(_distance, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
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

class _StatBox extends StatelessWidget {
  final String label; final String value; final IconData icon; final Color color;
  const _StatBox({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.card, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: AppTheme.textSec, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      );
}

class _StepsChart extends CustomPainter {
  static const _d = [0.1,0.15,0.3,0.5,0.4,0.6,0.8,0.7,0.5,0.3,0.4,0.6,0.5,0.3,0.2,0.3,0.4,0.2,0.1,0.05];

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
        Paint()..color = AppTheme.stepsColor.withValues(alpha: 0.5 + _d[i] * 0.5),
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
