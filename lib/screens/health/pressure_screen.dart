import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vital_widgets.dart';

class PressureScreen extends StatefulWidget {
  const PressureScreen({super.key});
  @override
  State<PressureScreen> createState() => _PressureScreenState();
}

class _PressureScreenState extends State<PressureScreen> {
  final _ble = BleService();

  int _period = 0; // 0=Day, 1=Week, 2=Month
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _readings = [];
  bool _loadingData = false;
  bool _measuring = false;

  int _stressValue = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String stressLabel(int v) {
    if (v <= 0) return 'No data';
    if (v < 40) return 'Relaxed';
    if (v < 60) return 'Normal';
    if (v < 80) return 'Elevated';
    return 'High';
  }

  static Color stressColor(int v) {
    if (v <= 0) return AppTheme.textSec;
    if (v < 40) return AppTheme.success;
    if (v < 60) return const Color(0xFFFBBF24);
    if (v < 80) return AppTheme.stressColor;
    return AppTheme.danger;
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = h < 12 ? 'AM' : 'PM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$m $ampm';
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() => _loadingData = true);
    try {
      final now = DateTime.now();
      late DateTime from, to;
      switch (_period) {
        case 1:
          from = DateTime(now.year, now.month, now.day)
              .subtract(const Duration(days: 6));
          to = DateTime(now.year, now.month, now.day, 23, 59, 59);
        case 2:
          from = DateTime(now.year, now.month, now.day)
              .subtract(const Duration(days: 29));
          to = DateTime(now.year, now.month, now.day, 23, 59, 59);
        default:
          from = DateTime(
              _selectedDate.year, _selectedDate.month, _selectedDate.day);
          to = DateTime(_selectedDate.year, _selectedDate.month,
              _selectedDate.day, 23, 59, 59);
      }
      final data = await SupabaseService.getStressReadings(
          userId: user.id, from: from, to: to);
      if (mounted) {
        setState(() {
          _readings = data;
          // Show latest reading in the card
          if (data.isNotEmpty) {
            final sorted = [...data]
              ..sort((a, b) => (b['measured_at'] as String)
                  .compareTo(a['measured_at'] as String));
            _stressValue =
                (sorted.first['stress_value'] as num? ?? 0).toInt();
          } else {
            // Fall back to BleProvider cached value when no data for this period
            _stressValue = 0;
          }
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  // ── Manual measurement ────────────────────────────────────────────────────

  Future<void> _toggleManual() async {
    final start = !_measuring;
    setState(() => _measuring = start);
    try {
      final result = await _ble.manualModePressure(start: start);
      if (start) {
        final m = jsonDecode(result) as Map<String, dynamic>;
        final v = (m['value'] as num? ?? 0).toInt();
        setState(() {
          _measuring = false;
          if (v > 0) _stressValue = v;
        });
        if (v > 0) await _saveMeasurement(v);
      } else {
        setState(() => _measuring = false);
      }
    } catch (e) {
      setState(() => _measuring = false);
      if (mounted) {
        final msg = e.toString().contains('TIMEOUT')
            ? 'Timed out — make sure ring is worn snugly.'
            : 'Error: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _saveMeasurement(int value) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.insertStress(
        userId: user.id,
        stressValue: value,
        measuredAt: DateTime.now(),
      );
      if (mounted) context.read<BleProvider>().updateStressLatest(value);
      await _loadData();
    } catch (_) {}
  }

  // ── Derived stats ─────────────────────────────────────────────────────────

  ({String avg, String min, String max}) _stats() {
    final vals = _readings
        .map((r) => (r['stress_value'] as num? ?? 0).toInt())
        .where((v) => v > 0)
        .toList();
    if (vals.isEmpty) return (avg: '--', min: '--', max: '--');
    final avg = (vals.reduce((a, b) => a + b) / vals.length).round();
    return (
      avg: '$avg',
      min: '${vals.reduce((a, b) => a < b ? a : b)}',
      max: '${vals.reduce((a, b) => a > b ? a : b)}',
    );
  }

  Map<String, int> _dayAverages() {
    final sums = <String, int>{};
    final counts = <String, int>{};
    for (final r in _readings) {
      final dt = DateTime.parse(r['measured_at'] as String).toLocal();
      final key =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      final v = (r['stress_value'] as num? ?? 0).toInt();
      if (v <= 0) continue;
      sums[key] = (sums[key] ?? 0) + v;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return {
      for (final k in sums.keys)
        k: (sums[k]! / counts[k]!).round(),
    };
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;
    final s = _stats();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _darkBar('Stress'),
      body: RefreshIndicator(
        color: AppTheme.gold,
        backgroundColor: AppTheme.card,
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              if (_period == 0)
                VitalDateSelector(
                  selectedDate: _selectedDate,
                  onDateSelected: (d) {
                    setState(() => _selectedDate = d);
                    _loadData();
                  },
                ),
              const SizedBox(height: 12),
              VitalPeriodTabs(onChanged: (i) {
                setState(() {
                  _period = i;
                  if (i == 0) _selectedDate = DateTime.now();
                });
                _loadData();
              }),
              const SizedBox(height: 24),
              _metricCard(),
              const SizedBox(height: 16),
              _chartCard(),
              const SizedBox(height: 16),
              VitalStatsRow(avg: s.avg, min: s.min, max: s.max),
              const SizedBox(height: 16),
              if (_period == 0) ...[
                _dayReadingsList(),
                const SizedBox(height: 16),
              ],
              VitalOneClickButton(
                label: _measuring ? 'Stop Measurement' : 'One Click Measurement',
                isStop: _measuring,
                loading: _measuring,
                enabled: connected,
                onPressed: _toggleManual,
              ),
              if (_loadingData && !_measuring)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.gold, strokeWidth: 2)),
                ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _metricCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: AppTheme.stressColor.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
                color: AppTheme.stressColor.withValues(alpha: 0.15),
                shape: BoxShape.circle),
            child: const Icon(Icons.psychology_rounded,
                color: AppTheme.stressColor, size: 30),
          ),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('STRESS LEVEL',
                style: TextStyle(
                    color: AppTheme.stressColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5)),
            const SizedBox(height: 4),
            Text(
              _measuring ? '···' : (_stressValue > 0 ? '$_stressValue' : '--'),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 52,
                  fontWeight: FontWeight.w700,
                  height: 1.0),
            ),
            Text(
              _measuring ? 'Measuring…' : stressLabel(_stressValue),
              style: TextStyle(
                  color: stressColor(_stressValue),
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ]),
        ]),
      );

  Widget _chartCard() {
    final label = _period == 0
        ? 'TODAY\'S READINGS'
        : (_period == 1 ? 'LAST 7 DAYS' : 'LAST 30 DAYS');

    Widget chart;
    if (_readings.isEmpty) {
      chart = const Center(
          child: Text('No data for this period',
              style: TextStyle(color: AppTheme.textSec, fontSize: 12)));
    } else if (_period == 0) {
      chart = CustomPaint(painter: _StressDayChartPainter(_readings));
    } else {
      chart = CustomPaint(
          painter: _StressRangeChartPainter(
              _dayAverages(), _period == 1 ? 7 : 30));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                color: AppTheme.textSec,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: const [
                Text('100',
                    style: TextStyle(
                        color: Color(0xFF555555), fontSize: 9)),
                SizedBox(height: 24),
                Text('60',
                    style: TextStyle(
                        color: Color(0xFF555555), fontSize: 9)),
                SizedBox(height: 24),
                Text('40',
                    style: TextStyle(
                        color: Color(0xFF555555), fontSize: 9)),
              ]),
          const SizedBox(width: 8),
          Expanded(
              child: SizedBox(height: 120, child: chart)),
        ]),
        const SizedBox(height: 8),
        Row(children: const [
          _LegendDot(color: AppTheme.success, label: 'Relaxed'),
          SizedBox(width: 10),
          _LegendDot(color: Color(0xFFFBBF24), label: 'Normal'),
          SizedBox(width: 10),
          _LegendDot(color: AppTheme.stressColor, label: 'Elevated'),
          SizedBox(width: 10),
          _LegendDot(color: AppTheme.danger, label: 'High'),
        ]),
      ]),
    );
  }

  Widget _dayReadingsList() {
    if (_readings.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(16)),
        child: const Center(
            child: Text('No readings for this day',
                style: TextStyle(color: AppTheme.textSec))),
      );
    }
    final sorted = [..._readings]
      ..sort((a, b) =>
          (b['measured_at'] as String).compareTo(a['measured_at'] as String));

    return Container(
      decoration: BoxDecoration(
          color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text('READINGS',
              style: TextStyle(
                  color: AppTheme.textSec,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
        ),
        ...sorted.asMap().entries.map((e) {
          final r = e.value;
          final dt = DateTime.parse(r['measured_at'] as String).toLocal();
          final v = (r['stress_value'] as num? ?? 0).toInt();
          final label = r['label'] as String? ?? stressLabel(v);
          final color = stressColor(v);
          final isLast = e.key == sorted.length - 1;
          return Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.psychology_rounded,
                      color: color, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(_fmtTime(dt),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                      Text(label,
                          style: TextStyle(
                              color: color, fontSize: 11)),
                    ])),
                Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                  Text('$v',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 22)),
                  const Text('/100',
                      style: TextStyle(
                          color: AppTheme.textSec, fontSize: 10)),
                ]),
              ]),
            ),
            if (!isLast)
              const Divider(
                  color: AppTheme.div, height: 0.5, indent: 66),
          ]);
        }),
      ]),
    );
  }
}

// ── Chart painters ────────────────────────────────────────────────────────────

Color _barColor(int v) {
  if (v < 40) return AppTheme.success;
  if (v < 60) return const Color(0xFFFBBF24);
  if (v < 80) return AppTheme.stressColor;
  return AppTheme.danger;
}

/// Day: scatter bars positioned by time of day
class _StressDayChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> readings;
  const _StressDayChartPainter(this.readings);

  @override
  void paint(Canvas canvas, Size size) {
    // Distribute bars across 24h; cluster nearby readings
    const slots = 24;
    final slotW = size.width / slots;
    final barW = slotW * 0.65;

    for (final r in readings) {
      final dt = DateTime.parse(r['measured_at'] as String).toLocal();
      final v = (r['stress_value'] as num? ?? 0).toInt();
      if (v <= 0) continue;
      final slot = dt.hour.clamp(0, slots - 1);
      final x = slot * slotW + (slotW - barW) / 2;
      final barH = (v / 100.0 * size.height * 0.9).clamp(3.0, size.height);
      canvas.drawRRect(
        RRect.fromLTRBR(
            x, size.height - barH, x + barW, size.height,
            const Radius.circular(4)),
        Paint()..color = _barColor(v),
      );
    }
  }

  @override
  bool shouldRepaint(_StressDayChartPainter old) =>
      old.readings != readings;
}

/// Week/Month: one bar per day showing average stress
class _StressRangeChartPainter extends CustomPainter {
  final Map<String, int> dayAvgs;
  final int days;
  const _StressRangeChartPainter(this.dayAvgs, this.days);

  @override
  void paint(Canvas canvas, Size size) {
    final now = DateTime.now();
    final slotW = size.width / days;
    final barW = slotW * 0.6;

    for (int i = 0; i < days; i++) {
      final day = now.subtract(Duration(days: days - 1 - i));
      final key =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      final v = dayAvgs[key];
      if (v == null || v <= 0) continue;
      final x = i * slotW + (slotW - barW) / 2;
      final barH = (v / 100.0 * size.height * 0.9).clamp(3.0, size.height);
      canvas.drawRRect(
        RRect.fromLTRBR(
            x, size.height - barH, x + barW, size.height,
            const Radius.circular(4)),
        Paint()..color = _barColor(v),
      );
    }
  }

  @override
  bool shouldRepaint(_StressRangeChartPainter old) =>
      old.dayAvgs != dayAvgs || old.days != days;
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(radius: 3.5, backgroundColor: color),
          const SizedBox(width: 3),
          Text(label,
              style:
                  const TextStyle(color: AppTheme.textSec, fontSize: 9)),
        ],
      );
}

AppBar _darkBar(String title) => AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600)),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Container(color: AppTheme.div, height: 0.5),
      ),
    );
