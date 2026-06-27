import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';

// ── Design tokens ──────────────────────────────────────────────────────────────
const _kBg   = Color(0xFF000000);
const _kCard = Color(0xFF111111);
const _kDiv  = Color(0xFF1E1E1E);
const _kSec  = Color(0xFF444444);
const _kSec2 = Color(0xFF777777);

const _kStepsColor = Color(0xFF4ADE80);
const _kDistColor  = Color(0xFF60A5FA);
const _kCalColor   = Color(0xFFFB923C);

TextStyle _t(double s,
    {FontWeight w = FontWeight.w400,
    Color c = Colors.white,
    double? ls,
    double? h}) =>
    GoogleFonts.inter(
        fontSize: s, fontWeight: w, color: c, letterSpacing: ls, height: h);

// ══════════════════════════════════════════════════════════════════════════════

class StepsScreen extends StatefulWidget {
  const StepsScreen({super.key});
  @override
  State<StepsScreen> createState() => _StepsScreenState();
}

class _StepsScreenState extends State<StepsScreen> {
  final _ble = BleService();

  int  _period      = 0; // 0=Day, 1=Week, 2=Month
  bool _syncingRing = false;
  bool _loadingHist = false;

  // Today's raw totals (from ring)
  int    _totalSteps = 0;
  int    _totalCal   = 0;
  double _totalDistM = 0.0;

  // Today's 15-min interval slots (96 slots = 24h) for day charts
  List<int>    _stepsSlots = List.filled(96, 0);
  List<int>    _calSlots   = List.filled(96, 0);
  List<double> _distSlots  = List.filled(96, 0.0);

  // Weekly history (7 days)
  List<int>    _weekSteps = [];
  List<int>    _weekCal   = [];
  List<double> _weekDist  = [];

  // Monthly history (30 days)
  List<int>    _monthSteps = [];
  List<int>    _monthCal   = [];
  List<double> _monthDist  = [];

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final ble = context.read<BleProvider>();
    if (ble.todaySteps > 0) {
      setState(() {
        _totalSteps = ble.todaySteps;
        _totalCal   = ble.todayCalories;
        _totalDistM = ble.todayDistanceM;
        _stepsSlots = List<int>.from(ble.todayStepsByInterval);
      });
    }
    await _syncFromRing();
    await _loadHistory();
  }

  // ── Ring sync (Day) ─────────────────────────────────────────────────────────

  Future<void> _syncFromRing() async {
    if (_syncingRing || !mounted) return;
    setState(() => _syncingRing = true);
    try {
      final json = await _ble.getTodaySteps();
      if (mounted) _parseAndApply(json);
    } catch (_) {}
    if (mounted) setState(() => _syncingRing = false);
  }

  void _parseAndApply(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      final list    = decoded is List ? decoded : <dynamic>[];

      final stepSlots = List<int>.filled(96, 0);
      final calSlots  = List<int>.filled(96, 0);
      final distSlots = List<double>.filled(96, 0.0);
      int totalSteps = 0, totalCal = 0;
      double totalDist = 0.0;

      for (final item in list) {
        final m     = item as Map<String, dynamic>;
        final d     = (m['d'] as num? ?? 0).toInt();
        final steps = (m['f'] as num? ?? 0).toInt();
        final cal   = (m['e'] as num? ?? 0).toInt() ~/ 1000;
        final dist  = (m['g'] as num? ?? 0).toDouble();
        totalSteps += steps;
        totalCal   += cal;
        totalDist  += dist;
        if (d >= 0 && d < 96) {
          stepSlots[d] += steps;
          calSlots[d]  += cal;
          distSlots[d] += dist;
        }
      }

      if (!mounted) return;
      setState(() {
        _totalSteps = totalSteps;
        _totalCal   = totalCal;
        _totalDistM = totalDist;
        _stepsSlots = stepSlots;
        _calSlots   = calSlots;
        _distSlots  = distSlots;
      });
      context.read<BleProvider>().updateStepsData(
          totalSteps, totalCal, totalDist, stepSlots);
      _saveToDb(totalSteps, totalCal, totalDist);
    } catch (_) {}
  }

  Future<void> _saveToDb(int steps, int cal, double dist) async {
    if (steps <= 0 && cal <= 0) return;
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.upsertSteps(
          userId: user.id,
          date: DateTime.now(),
          steps: steps,
          calories: cal,
          distanceM: dist);
    } catch (_) {}
  }

  // ── Supabase history (Week / Month) ────────────────────────────────────────

  Future<void> _loadHistory() async {
    final user = SupabaseService.currentUser;
    if (user == null || !mounted) return;
    setState(() => _loadingHist = true);
    try {
      final now  = DateTime.now();
      final rows = await SupabaseService.getStepsHistory(
          userId: user.id,
          from: now.subtract(const Duration(days: 29)),
          to: now);
      if (!mounted) return;
      setState(() {
        _weekSteps  = _buildInt(rows, now, 7,  'steps');
        _weekCal    = _buildInt(rows, now, 7,  'calories');
        _weekDist   = _buildDbl(rows, now, 7,  'distance_m');
        _monthSteps = _buildInt(rows, now, 30, 'steps');
        _monthCal   = _buildInt(rows, now, 30, 'calories');
        _monthDist  = _buildDbl(rows, now, 30, 'distance_m');
      });
    } catch (_) {}
    if (mounted) setState(() => _loadingHist = false);
  }

  List<int> _buildInt(List rows, DateTime now, int n, String key) =>
      List.generate(n, (i) {
        final d   = now.subtract(Duration(days: n - 1 - i));
        final row = rows.firstWhere(
            (r) => r['date'] == _fmt(d), orElse: () => {});
        return (row[key] as num? ?? 0).toInt();
      });

  List<double> _buildDbl(List rows, DateTime now, int n, String key) =>
      List.generate(n, (i) {
        final d   = now.subtract(Duration(days: n - 1 - i));
        final row = rows.firstWhere(
            (r) => r['date'] == _fmt(d), orElse: () => {});
        return (row[key] as num? ?? 0.0).toDouble();
      });

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Period-resolved display values ──────────────────────────────────────────

  int get _dispSteps {
    if (_period == 1) return _weekSteps.fold(0, (a, b) => a + b);
    if (_period == 2) return _monthSteps.fold(0, (a, b) => a + b);
    return _totalSteps;
  }

  int get _dispCal {
    if (_period == 1) return _weekCal.fold(0, (a, b) => a + b);
    if (_period == 2) return _monthCal.fold(0, (a, b) => a + b);
    return _totalCal;
  }

  double get _dispDistM {
    if (_period == 1) return _weekDist.fold(0.0, (a, b) => a + b);
    if (_period == 2) return _monthDist.fold(0.0, (a, b) => a + b);
    return _totalDistM;
  }

  String get _periodLabel =>
      _period == 2 ? 'This Month' : _period == 1 ? 'This Week' : 'Today';

  // ── Activity score (daily average for the period) ───────────────────────────

  int get _activityScore {
    final days     = _period == 2 ? 30.0 : _period == 1 ? 7.0 : 1.0;
    final avgSteps = _dispSteps / days;
    final avgCal   = _dispCal   / days;
    final avgDistM = _dispDistM / days;
    final s = (avgSteps / 8000 * 60).clamp(0.0, 60.0);
    final c = (avgCal   / 250   * 25).clamp(0.0, 25.0);
    final d = (avgDistM / 5000  * 15).clamp(0.0, 15.0);
    return (s + c + d).round().clamp(0, 100);
  }

  String get _scoreLabel {
    final s = _activityScore;
    if (s == 0)  return 'Lack of exercise';
    if (s < 25)  return 'Sedentary';
    if (s < 50)  return 'Lightly active';
    if (s < 75)  return 'Moderately active';
    return 'Highly active';
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final now     = DateTime.now();
    final loading = _period == 0 ? _syncingRing : _loadingHist;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text('Activity', style: _t(17, w: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 22),
            onPressed: () {},
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.gold,
        backgroundColor: const Color(0xFF1C1C1C),
        onRefresh: () async {
          await _syncFromRing();
          await _loadHistory();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Date strip ──────────────────────────────────────────────────
              _DateStrip(now: now),
              const Divider(color: _kDiv, height: 0.5, thickness: 0.5),

              // ── Period tabs ─────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: _PeriodTabs(
                    selected: _period,
                    onChanged: (i) => setState(() => _period = i)),
              ),

              // ── Activity Score ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                child: _ActivityScore(
                    score: _activityScore,
                    label: _scoreLabel,
                    syncing: loading),
              ),

              // ── Data Details ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: const _DataDetailsRow(),
              ),

              // ── Summary cards (always shown) ────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(children: [
                  Expanded(child: _MetricCard(
                      label: 'Total Steps',
                      sublabel: _periodLabel,
                      value: _dispSteps > 0 ? '$_dispSteps' : '--',
                      color: _kStepsColor)),
                  const SizedBox(width: 10),
                  Expanded(child: _MetricCard(
                      label: 'Distance',
                      sublabel: _periodLabel,
                      value: _dispDistM > 0
                          ? '${_dispDistM.toStringAsFixed(0)} m'
                          : '--',
                      color: _kDistColor)),
                  const SizedBox(width: 10),
                  Expanded(child: _MetricCard(
                      label: 'Calories',
                      sublabel: _periodLabel,
                      value: _dispCal > 0 ? '$_dispCal' : '--',
                      color: _kCalColor)),
                ]),
              ),

              // ── Day charts (Steps / Distance / Calories) ────────────────────
              if (_period == 0) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _SingleChart(
                    title: 'STEPS · TODAY',
                    legendValue: '$_totalSteps steps',
                    peakSuffix: 'steps',
                    color: _kStepsColor,
                    values: _toHourlyInt(_stepsSlots),
                    xLabels: _hourXLabels,
                    loading: _syncingRing,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _SingleChart(
                    title: 'DISTANCE · TODAY',
                    legendValue: '${_totalDistM.toStringAsFixed(0)} m',
                    peakSuffix: 'm',
                    color: _kDistColor,
                    values: _toHourlyDbl(_distSlots),
                    xLabels: _hourXLabels,
                    loading: _syncingRing,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _SingleChart(
                    title: 'CALORIES · TODAY',
                    legendValue: '$_totalCal kcal',
                    peakSuffix: 'kcal',
                    color: _kCalColor,
                    values: _toHourlyInt(_calSlots),
                    xLabels: _hourXLabels,
                    loading: _syncingRing,
                  ),
                ),
              ],

              // ── Week chart ──────────────────────────────────────────────────
              if (_period == 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _SingleChart(
                    title: 'STEPS · LAST 7 DAYS',
                    legendValue: '$_dispSteps steps total',
                    color: _kStepsColor,
                    values: _weekSteps
                        .map((v) => v.toDouble())
                        .toList(),
                    xLabels: _weekXLabels(now),
                    loading: _loadingHist,
                  ),
                ),

              // ── Month chart ─────────────────────────────────────────────────
              if (_period == 2)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _SingleChart(
                    title: 'STEPS · LAST 30 DAYS',
                    legendValue: '$_dispSteps steps total',
                    color: _kStepsColor,
                    values: _monthSteps
                        .map((v) => v.toDouble())
                        .toList(),
                    xLabels: const ['1','5','10','15','20','25','30'],
                    loading: _loadingHist,
                  ),
                ),

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _weekXLabels(DateTime now) {
    const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return List.generate(
        7, (i) => days[now.subtract(Duration(days: 6 - i)).weekday - 1]);
  }

  // Collapse 96 × 15-min slots into 24 hourly buckets for day charts
  List<double> _toHourlyInt(List<int> slots) =>
      List.generate(24, (h) =>
          slots.sublist(h * 4, h * 4 + 4).fold(0, (a, b) => a + b).toDouble());

  List<double> _toHourlyDbl(List<double> slots) =>
      List.generate(24, (h) =>
          slots.sublist(h * 4, h * 4 + 4).fold(0.0, (a, b) => a + b));

  static const _hourXLabels = ['12am', '6am', '12pm', '6pm', '12am'];
}

// ── Date strip ────────────────────────────────────────────────────────────────

class _DateStrip extends StatelessWidget {
  final DateTime now;
  const _DateStrip({required this.now});

  static const _dayAbbr  = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
  static const _monthAbbr = ['Jan','Feb','Mar','Apr','May','Jun',
                              'Jul','Aug','Sep','Oct','Nov','Dec'];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: 7,
        itemBuilder: (_, i) {
          final offset  = i - 3;
          final date    = now.add(Duration(days: offset));
          final isToday = offset == 0;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: isToday ? 94 : 40,
            margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 10),
            decoration: BoxDecoration(
              color: isToday
                  ? AppTheme.gold.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isToday
                  ? Border.all(
                      color: AppTheme.gold.withValues(alpha: 0.35))
                  : null,
            ),
            child: isToday
                ? Center(
                    child: Text(
                      'Today, ${date.day} ${_monthAbbr[date.month - 1]}',
                      style: _t(10, w: FontWeight.w600, c: AppTheme.gold),
                      maxLines: 1,
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${date.day}', style: _t(13, c: _kSec2)),
                      const SizedBox(height: 1),
                      Text(_dayAbbr[date.weekday - 1],
                          style: _t(9, c: _kSec)),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

// ── Period tabs ───────────────────────────────────────────────────────────────

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
            margin: const EdgeInsets.only(right: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: active
                  ? AppTheme.gold.withValues(alpha: 0.10)
                  : _kCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: active
                      ? AppTheme.gold.withValues(alpha: 0.45)
                      : _kDiv),
            ),
            child: Text(
              e.value,
              style: _t(13,
                  w: active ? FontWeight.w600 : FontWeight.w400,
                  c: active ? AppTheme.gold : _kSec2),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Activity score ────────────────────────────────────────────────────────────

class _ActivityScore extends StatelessWidget {
  final int score;
  final String label;
  final bool syncing;
  const _ActivityScore(
      {required this.score, required this.label, required this.syncing});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ACTIVITY SCORE',
            style: _t(10, w: FontWeight.w700, c: _kSec2, ls: 1.6)),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            syncing
                ? const SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                        color: AppTheme.gold, strokeWidth: 2))
                : Text('$score',
                    style: _t(60, w: FontWeight.w700, h: 1.0)),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('/100', style: _t(16, c: _kSec2)),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(label, style: _t(13, c: _kSec2)),
      ],
    );
  }
}

// ── Data Details row ──────────────────────────────────────────────────────────

class _DataDetailsRow extends StatelessWidget {
  const _DataDetailsRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kDiv),
      ),
      child: Row(
        children: [
          Text('Data Details', style: _t(14, w: FontWeight.w500)),
          const Spacer(),
          const Icon(Icons.chevron_right_rounded, color: _kSec2, size: 20),
        ],
      ),
    );
  }
}

// ── Metric summary card ───────────────────────────────────────────────────────

class _MetricCard extends StatelessWidget {
  final String label, sublabel, value;
  final Color color;
  const _MetricCard({
    required this.label,
    required this.sublabel,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kDiv),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _t(10, c: _kSec2, w: FontWeight.w500)),
          Text(sublabel, style: _t(9, c: _kSec)),
          const SizedBox(height: 7),
          Text(value,
              style: _t(15, w: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 7),
          Text('know more >', style: _t(10, c: color, w: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ── Single chart card (week / month) ─────────────────────────────────────────

class _SingleChart extends StatelessWidget {
  final String title;
  final String legendValue;
  final String peakSuffix;
  final Color color;
  final List<double> values;
  final List<String> xLabels;
  final bool loading;

  const _SingleChart({
    required this.title,
    required this.legendValue,
    required this.color,
    required this.values,
    required this.xLabels,
    required this.loading,
    this.peakSuffix = 'steps',
  });

  List<double> get _normalised {
    if (values.isEmpty) return [];
    final mx = values.reduce((a, b) => a > b ? a : b);
    if (mx <= 0) return List.filled(values.length, 0.0);
    return values.map((v) => v / mx).toList();
  }

  @override
  Widget build(BuildContext context) {
    final norm    = _normalised;
    final hasData = norm.isNotEmpty && norm.any((v) => v > 0);
    final maxVal  = values.isEmpty
        ? 0
        : values.reduce((a, b) => a > b ? a : b).toInt();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kDiv),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            Text(title,
                style: _t(10, w: FontWeight.w700, c: _kSec2, ls: 0.8)),
            const Spacer(),
            Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                    color: color, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(legendValue,
                style: _t(11, w: FontWeight.w600, c: _kSec2)),
          ]),

          // Peak label
          if (!loading && hasData) ...[
            const SizedBox(height: 4),
            Text('Peak: $maxVal $peakSuffix',
                style: _t(10, c: color.withValues(alpha: 0.8))),
          ],

          const SizedBox(height: 14),

          // Chart
          SizedBox(
            height: 120,
            width: double.infinity,
            child: loading
                ? Center(
                    child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: color, strokeWidth: 1.5)))
                : !hasData
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bar_chart_rounded,
                                color: _kSec.withValues(alpha: 0.5),
                                size: 32),
                            const SizedBox(height: 6),
                            Text('No data yet',
                                style: _t(12, c: _kSec2)),
                          ],
                        ))
                    : CustomPaint(
                        painter: _BarPainter(values: norm, color: color)),
          ),

          // X-axis
          if (!loading) ...[
            const SizedBox(height: 8),
            _XAxisRow(labels: xLabels, count: values.length),
          ],
        ],
      ),
    );
  }
}

// ── X-axis row ────────────────────────────────────────────────────────────────

class _XAxisRow extends StatelessWidget {
  final List<String> labels;
  final int count;
  const _XAxisRow({required this.labels, required this.count});

  static const _style = TextStyle(color: Color(0xFF3A3A3A), fontSize: 9);

  @override
  Widget build(BuildContext context) {
    // For monthly (30 bars), only show 7 evenly-spaced labels
    final toShow = labels.length <= 10 ? labels : _sparse(labels);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: toShow.map((l) => Text(l, style: _style)).toList(),
    );
  }

  List<String> _sparse(List<String> all) {
    // Pick ~7 labels spread across the list
    final step = (all.length / 6).ceil();
    final out  = <String>[];
    for (int i = 0; i < all.length; i += step) { out.add(all[i]); }
    if (out.last != all.last) out.add(all.last);
    return out;
  }
}

// ── Bar chart painter ─────────────────────────────────────────────────────────

class _BarPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  const _BarPainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final n      = values.length;
    final slotW  = size.width / n;
    final barW   = n > 20
        ? (slotW * 0.55).clamp(2.0, 6.0)
        : (slotW * 0.55).clamp(8.0, 30.0);
    final padL   = (slotW - barW) / 2;

    // Subtle top grid line
    canvas.drawLine(
      const Offset(0, 0),
      Offset(size.width, 0),
      Paint()
        ..color = _kDiv
        ..strokeWidth = 0.5,
    );

    for (int i = 0; i < n; i++) {
      if (values[i] <= 0) continue;
      final ratio = values[i];
      final barH  = (ratio * size.height * 0.93).clamp(2.0, size.height);
      final x     = i * slotW + padL;
      canvas.drawRRect(
        RRect.fromLTRBR(
            x, size.height - barH, x + barW, size.height,
            const Radius.circular(3)),
        Paint()
          ..color = color
              .withValues(alpha: (0.35 + ratio * 0.65).clamp(0.35, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.values != values || old.color != color;
}
