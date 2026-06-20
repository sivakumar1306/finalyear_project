import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';

class StepsScreen extends StatefulWidget {
  const StepsScreen({super.key});
  @override
  State<StepsScreen> createState() => _StepsScreenState();
}

class _StepsScreenState extends State<StepsScreen> {
  final _ble = BleService();

  int _period = 0;
  bool _syncingRing = false;
  bool _loadingHistory = false;

  String _steps = '--';
  String _calories = '--';
  String _distance = '--';
  String _rawJson = '';  // always shown so you can see exactly what the ring returns
  String _syncStatus = '';

  List<int> _dayValues = [];
  List<int> _weekValues = [];
  List<int> _monthValues = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    // Pre-fill from Supabase cache (fast, no ring needed)
    final ble = context.read<BleProvider>();
    if (ble.todaySteps > 0) _applyProviderSnapshot(ble);

    // Auto-sync from ring on open
    await _syncFromRing();
    // Load Supabase history for Week/Month charts
    await _loadHistory();
  }

  void _applyProviderSnapshot(BleProvider ble) {
    if (!mounted) return;
    setState(() {
      _steps = '${ble.todaySteps}';
      _calories = '${ble.todayCalories}';
      final d = ble.todayDistanceM;
      _distance = d > 0
          ? (d >= 1000 ? '${(d / 1000).toStringAsFixed(1)} km' : '${d.toStringAsFixed(0)} m')
          : '--';
    });
  }

  // ── The exact same single call the old "Load Today's Steps" button used ──
  Future<void> _syncFromRing() async {
    if (_syncingRing || !mounted) return;
    setState(() {
      _syncingRing = true;
      _syncStatus = 'Loading...';
      _rawJson = '';
    });
    try {
      final json = await _ble.getTodaySteps();
      if (!mounted) return;
      setState(() {
        _rawJson = _pretty(json);
        _syncStatus = 'Ring responded ✓';
      });
      _parseAndApply(json);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rawJson = 'Error: $e';
        _syncStatus = 'Error — see below';
      });
    } finally {
      if (mounted) setState(() => _syncingRing = false);
    }
  }

  String _pretty(String raw) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
    } catch (_) {
      return raw;
    }
  }

  void _parseAndApply(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      final list = decoded is List ? decoded : <dynamic>[];

      int totalSteps = 0, totalCal = 0;
      double totalDist = 0.0;

      // SDK ProGuard obfuscates BleStepDetails fields to single letters:
      //   d = 15-min slot of the day (0–95 covers 24 h)
      //   e = steps,  f = calories,  g = distance
      // 96 slots = 24 h × 4 quarter-hours — correct time position on Day chart.
      final slots = List<int>.filled(96, 0);

      for (final item in list) {
        final m = item as Map<String, dynamic>;
        final d     = (m['d'] as num? ?? 0).toInt(); // timeIndex: 15-min slot 0–95
        // ProGuard field order: e=calorie(小卡), f=walkSteps, g=distance(m), h=runSteps
        final steps = (m['f'] as num? ?? 0).toInt();            // walkSteps — raw count
        final cal   = (m['e'] as num? ?? 0).toInt() ~/ 1000;   // 小卡 → kcal
        final dist  = (m['g'] as num? ?? 0).toDouble();          // meters

        totalSteps += steps;
        totalCal   += cal;
        totalDist  += dist;
        if (d >= 0 && d < 96) slots[d] += steps;
      }

      if (!mounted) return;
      setState(() {
        _steps    = totalSteps > 0 ? '$totalSteps' : '--';
        _calories = totalCal   > 0 ? '$totalCal'   : '--';
        _distance = totalDist  > 0
            ? (totalDist >= 1000
                ? '${(totalDist / 1000).toStringAsFixed(1)} km'
                : '${totalDist.toStringAsFixed(0)} m')
            : '--';
        _dayValues = slots;
      });
      context.read<BleProvider>().updateStepsData(totalSteps, totalCal, totalDist, slots);
      _saveToSupabase(totalSteps, totalCal, totalDist);
    } catch (e) {
      if (mounted) setState(() => _syncStatus = 'Parse error: $e');
    }
  }

  Future<void> _saveToSupabase(int steps, int cal, double dist) async {
    if (steps <= 0 && cal <= 0) return;
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.upsertSteps(
        userId: user.id,
        date: DateTime.now(),
        steps: steps,
        calories: cal,
        distanceM: dist,
      );
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    final user = SupabaseService.currentUser;
    if (user == null || !mounted) return;
    setState(() => _loadingHistory = true);
    try {
      final now = DateTime.now();
      final rows = await SupabaseService.getStepsHistory(
        userId: user.id,
        from: now.subtract(const Duration(days: 29)),
        to: now,
      );
      if (!mounted) return;
      setState(() {
        _weekValues = _buildWeek(rows, now);
        _monthValues = _buildMonth(rows, now);
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  List<int> _buildWeek(List<Map<String, dynamic>> rows, DateTime now) =>
      List.generate(7, (i) {
        final day = now.subtract(Duration(days: 6 - i));
        final row = rows.firstWhere(
            (r) => r['date'] == _fmt(day), orElse: () => {});
        return (row['steps'] as num? ?? 0).toInt();
      });

  List<int> _buildMonth(List<Map<String, dynamic>> rows, DateTime now) =>
      List.generate(30, (i) {
        final day = now.subtract(Duration(days: 29 - i));
        final row = rows.firstWhere(
            (r) => r['date'] == _fmt(day), orElse: () => {});
        return (row['steps'] as num? ?? 0).toInt();
      });

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final now = DateTime.now();

    final values = switch (_period) {
      1 => _weekValues,
      2 => _monthValues,
      _ => _dayValues,
    };

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Steps & Activity',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(color: AppTheme.div, height: 0.5),
        ),
      ),
      body: RefreshIndicator(
        color: AppTheme.gold,
        backgroundColor: AppTheme.card,
        onRefresh: () async {
          await _syncFromRing();
          await _loadHistory();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              _PeriodTabs(
                  selected: _period,
                  onChanged: (i) => setState(() => _period = i)),
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 12),
                child: Text(
                  _periodLabel(_period, now),
                  style: const TextStyle(
                      color: AppTheme.textSec, fontSize: 11, letterSpacing: 0.4),
                ),
              ),
              _SummaryRow(
                steps: _steps,
                calories: _calories,
                distance: _distance,
                syncing: _syncingRing,
              ),
              const SizedBox(height: 16),
              _ChartCard(
                period: _period,
                values: values,
                loading: _period == 0 ? _syncingRing : _loadingHistory,
                now: now,
              ),
              const SizedBox(height: 20),

              // ── Manual sync button ──────────────────────────────────
              _SyncButton(
                connected: ble.isConnected,
                syncing: _syncingRing,
                onTap: _syncFromRing,
              ),

              // ── Raw JSON from ring (always shown after a sync attempt) ──
              if (_rawJson.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.card2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.div),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('RING RESPONSE',
                              style: TextStyle(
                                  color: AppTheme.textSec,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1)),
                          Text(_syncStatus,
                              style: const TextStyle(
                                  color: AppTheme.gold, fontSize: 10)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Text(
                          _rawJson,
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              color: AppTheme.textSec,
                              fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  String _periodLabel(int p, DateTime now) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    if (p == 0) return '${m[now.month - 1]} ${now.day}, ${now.year}  ·  TODAY';
    final from = now.subtract(Duration(days: p == 1 ? 6 : 29));
    return '${m[from.month - 1]} ${from.day} – ${m[now.month - 1]} ${now.day}';
  }
}

// ─── Period tabs ──────────────────────────────────────────────────────────────

class _PeriodTabs extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  const _PeriodTabs({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const tabs = ['Day', 'Week', 'Month'];
    return Row(
      children: tabs.asMap().entries.map((e) {
        final active = e.key == selected;
        return GestureDetector(
          onTap: () => onChanged(e.key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                    color: active ? AppTheme.gold : Colors.transparent,
                    width: 2),
              ),
            ),
            child: Text(e.value,
                style: TextStyle(
                    color: active ? AppTheme.gold : AppTheme.textSec,
                    fontWeight:
                        active ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 14)),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Summary row ─────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final String steps, calories, distance;
  final bool syncing;
  const _SummaryRow(
      {required this.steps,
      required this.calories,
      required this.distance,
      required this.syncing});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
              child: _StatBox(
                  label: 'STEPS',
                  value: steps,
                  icon: Icons.directions_walk_rounded,
                  color: AppTheme.stepsColor,
                  loading: syncing)),
          const SizedBox(width: 10),
          Expanded(
              child: _StatBox(
                  label: 'CALORIES',
                  value: calories,
                  unit: 'kcal',
                  icon: Icons.local_fire_department_rounded,
                  color: AppTheme.hrColor)),
          const SizedBox(width: 10),
          Expanded(
              child: _StatBox(
                  label: 'DISTANCE',
                  value: distance,
                  icon: Icons.straighten_rounded,
                  color: AppTheme.hrvColor)),
        ],
      );
}

class _StatBox extends StatelessWidget {
  final String label, value;
  final String unit;
  final IconData icon;
  final Color color;
  final bool loading;
  const _StatBox(
      {required this.label,
      required this.value,
      this.unit = '',
      required this.icon,
      required this.color,
      this.loading = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 20),
            if (loading) ...[
              const Spacer(),
              const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                      color: AppTheme.gold, strokeWidth: 1.5)),
            ],
          ]),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSec,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          if (unit.isNotEmpty)
            Text(unit,
                style:
                    const TextStyle(color: AppTheme.textSec, fontSize: 9)),
        ]),
      );
}

// ─── Manual sync button ───────────────────────────────────────────────────────

class _SyncButton extends StatelessWidget {
  final bool connected, syncing;
  final VoidCallback onTap;
  const _SyncButton(
      {required this.connected, required this.syncing, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: (connected && !syncing) ? onTap : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: (connected && !syncing)
                ? const LinearGradient(
                    colors: [Color(0xFFD4A853), Color(0xFF9A7235)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight)
                : null,
            color: (connected && !syncing) ? null : AppTheme.card,
            borderRadius: BorderRadius.circular(14),
            border: (connected && !syncing)
                ? null
                : Border.all(color: AppTheme.div),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (syncing)
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: AppTheme.gold, strokeWidth: 2))
              else
                Icon(Icons.sync_rounded,
                    color: connected ? Colors.black : AppTheme.textSec,
                    size: 20),
              const SizedBox(width: 10),
              Text(
                syncing
                    ? 'Syncing...'
                    : connected
                        ? "Sync Today's Steps"
                        : 'Ring not connected',
                style: TextStyle(
                    color: syncing
                        ? AppTheme.gold
                        : connected
                            ? Colors.black
                            : AppTheme.textSec,
                    fontWeight: FontWeight.w600,
                    fontSize: 15),
              ),
            ],
          ),
        ),
      );
}

// ─── Chart card ───────────────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  final int period;
  final List<int> values;
  final bool loading;
  final DateTime now;
  const _ChartCard(
      {required this.period,
      required this.values,
      required this.loading,
      required this.now});

  @override
  Widget build(BuildContext context) {
    const titles = ['TODAY BY INTERVAL', 'LAST 7 DAYS', 'LAST 30 DAYS'];
    final maxVal =
        values.isEmpty ? 0 : values.reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(titles[period],
                style: const TextStyle(
                    color: AppTheme.textSec,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
            if (loading)
              const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      color: AppTheme.gold, strokeWidth: 1.5))
            else if (maxVal > 0)
              Text('Peak: $maxVal',
                  style: const TextStyle(
                      color: AppTheme.stepsColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: loading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: AppTheme.gold, strokeWidth: 2))
              : maxVal == 0
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.bar_chart_rounded,
                            color: AppTheme.textSec.withValues(alpha: 0.4),
                            size: 32),
                        const SizedBox(height: 6),
                        const Text('No data yet',
                            style: TextStyle(
                                color: AppTheme.textSec, fontSize: 12)),
                      ]))
                  : CustomPaint(
                      size: Size.infinite,
                      painter: _BarPainter(values: values, maxVal: maxVal)),
        ),
        if (!loading && maxVal > 0) ...[
          const SizedBox(height: 8),
          _xAxis(period, now),
        ],
      ]),
    );
  }

  Widget _xAxis(int p, DateTime now) {
    const style = TextStyle(color: Color(0xFF555555), fontSize: 9);
    if (p == 0) {
      return const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('12a', style: style), Text('3a', style: style),
          Text('6a', style: style),  Text('9a', style: style),
          Text('12p', style: style), Text('3p', style: style),
          Text('6p', style: style),  Text('9p', style: style),
        ],
      );
    }
    if (p == 1) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(7, (i) {
          final d = now.subtract(Duration(days: 6 - i));
          return Text(days[d.weekday - 1], style: style);
        }),
      );
    }
    return const Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('1', style: style),  Text('5', style: style),
        Text('10', style: style), Text('15', style: style),
        Text('20', style: style), Text('25', style: style),
        Text('30', style: style),
      ],
    );
  }
}

class _BarPainter extends CustomPainter {
  final List<int> values;
  final int maxVal;
  const _BarPainter({required this.values, required this.maxVal});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || maxVal == 0) return;
    final n = values.length;
    final barW = size.width / n * 0.65;
    final gap = size.width / n * 0.35;
    for (int i = 0; i < n; i++) {
      if (values[i] <= 0) continue;
      final ratio = values[i] / maxVal;
      final barH = (ratio * size.height * 0.92).clamp(2.0, size.height);
      final x = i * (barW + gap) + gap / 2;
      canvas.drawRRect(
        RRect.fromLTRBR(x, size.height - barH, x + barW, size.height,
            const Radius.circular(3)),
        Paint()
          ..color = AppTheme.stepsColor
              .withValues(alpha: (0.35 + ratio * 0.65).clamp(0.35, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.values != values || old.maxVal != maxVal;
}
