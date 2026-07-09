import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';

// Oudmon SDK sleep stage constants: 0=deep, 1=light, 2=awake, 3=REM
const _kDeep  = 0;
const _kLight = 1;
const _kAwake = 2;
const _kRem   = 3;

const _kAwakeColor = Color(0xFFFBBF24);
const _kLightColor = Color(0xFF60A5FA);
const _kDeepColor  = Color(0xFF6366F1);
const _kRemColor   = Color(0xFF818CF8);

const _stageColors = {
  _kDeep:  _kDeepColor,
  _kLight: _kLightColor,
  _kAwake: _kAwakeColor,
  _kRem:   _kRemColor,
};

// ── Local design tokens — same system as heart_rate_screen.dart / blood_oxygen_screen.dart ──

const _kCard   = Color(0xFF141414);
const _kBorder = Color(0xFF242424);
const _kSec    = Color(0xFF666666);
const _kSec2   = Color(0xFF888888);

TextStyle _inter(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = Colors.white,
  double? letterSpacing,
  double? height,
}) =>
    GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );

// ── Screen ────────────────────────────────────────────────────────────────────

class SleepScreen extends StatefulWidget {
  const SleepScreen({super.key});
  @override
  State<SleepScreen> createState() => _SleepScreenState();
}

class _SleepScreenState extends State<SleepScreen> {
  final _ble = BleService();

  DateTime _selectedDate = DateTime.now();
  bool _loading = false;

  // Day sleep data
  int _totalDuration = 0;
  int _deepDuration  = 0;
  int _lightDuration = 0;
  int _remDuration   = 0;
  int _awakeDuration = 0;
  int _sleepTime     = 0;
  int _wakeTime      = 0;
  int _sleepScore    = 0;
  List<Map<String, int>> _segments = [];

  // Vitals for selected day
  int _avgHr   = 0;
  int _avgSpo2 = 0;
  int _avgHrv  = 0;

  // Last 7 days (always loaded on open, same as HR/SpO2's 7-day trend)
  List<Map<String, dynamic>> _historyRows = [];

  // ── Init ──────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _init();
      _loadHistory();
    });
  }

  Future<void> _init() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final today = DateTime.now();
      final isToday = _selectedDate.year == today.year &&
          _selectedDate.month == today.month &&
          _selectedDate.day == today.day;
      if (isToday && context.read<BleProvider>().isConnected) {
        await _fetchFromRing();
      } else {
        await _loadDayFromDb();
      }
      await _loadVitals();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Date selection ────────────────────────────────────────────────────────────

  void _onDateSelected(DateTime date) {
    setState(() {
      _selectedDate = date;
      _totalDuration = 0;
      _deepDuration  = 0;
      _lightDuration = 0;
      _remDuration   = 0;
      _awakeDuration = 0;
      _sleepTime     = 0;
      _wakeTime      = 0;
      _sleepScore    = 0;
      _segments      = [];
      _avgHr = 0; _avgSpo2 = 0; _avgHrv = 0;
    });
    _init();
  }

  // ── Ring fetch ───────────────────────────────────────────────────────────────

  Future<void> _fetchFromRing() async {
    try {
      final data = await _ble.getTodaySleep();
      _parseSleepData(data);
    } catch (_) {
      await _loadDayFromDb();
    }
  }

  void _parseSleepData(String jsonStr) {
    try {
      final d     = jsonDecode(jsonStr) as Map<String, dynamic>;
      final total = (d['totalSleepDuration'] as num? ?? 0).toInt();
      final deep  = (d['deepDuration']        as num? ?? 0).toInt();
      final light = (d['lightDuration']       as num? ?? 0).toInt();
      final rem   = (d['remDuration']         as num? ?? 0).toInt();
      final awake = (d['awakeDuration']       as num? ?? 0).toInt();
      final st    = (d['sleepTime']           as num? ?? 0).toInt();
      final et    = (d['wakeTime']            as num? ?? 0).toInt();
      if (total <= 0) { _loadDayFromDb(); return; }
      final segs  = _parseSegments(d['list']);
      final score = _calcScore(total, deep, rem, st, et);
      if (!mounted) return;
      setState(() {
        _totalDuration = total;
        _deepDuration  = deep;
        _lightDuration = light;
        _remDuration   = rem;
        _awakeDuration = awake;
        _sleepTime     = st;
        _wakeTime      = et;
        _sleepScore    = score;
        _segments      = segs;
      });
      _saveToDb(total, deep, light, rem, awake, score, st, et);
    } catch (_) {
      _loadDayFromDb();
    }
  }

  List<Map<String, int>> _parseSegments(dynamic rawList) {
    if (rawList == null) return [];
    final segs = <Map<String, int>>[];
    for (final item in rawList as List<dynamic>) {
      final m = item as Map<String, dynamic>;
      final s = (m['sleepStart'] as num? ?? 0).toInt();
      final e = (m['sleepEnd']   as num? ?? 0).toInt();
      final t = (m['type']       as num? ?? _kLight).toInt();
      if (s > 0 && e > s) segs.add({'start': s, 'end': e, 'type': t});
    }
    return segs;
  }

  int _calcScore(int total, int deep, int rem, int st, int et) {
    final window     = (st > 0 && et > 0) ? (et - st) : total;
    final efficiency = window > 0 ? (total / window * 100).clamp(0, 100) : 0;
    final deepPct    = total > 0 ? (deep / total * 100).clamp(0, 40) : 0;
    final remPct     = total > 0 ? (rem  / total * 100).clamp(0, 30) : 0;
    return (efficiency * 0.4 + deepPct * 1.0 + remPct * 0.5).round().clamp(0, 100);
  }

  // ── DB ───────────────────────────────────────────────────────────────────────

  Future<void> _loadDayFromDb() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      final row = await SupabaseService.getSleepForDate(user.id, _selectedDate);
      if (!mounted || row == null) return;
      setState(() {
        _totalDuration = (row['total_duration'] as num? ?? 0).toInt();
        _deepDuration  = (row['deep_duration']  as num? ?? 0).toInt();
        _lightDuration = (row['light_duration'] as num? ?? 0).toInt();
        _remDuration   = (row['rem_duration']   as num? ?? 0).toInt();
        _awakeDuration = (row['awake_duration'] as num? ?? 0).toInt();
        _sleepTime     = (row['sleep_time']     as num? ?? 0).toInt();
        _wakeTime      = (row['wake_time']      as num? ?? 0).toInt();
        _sleepScore    = (row['sleep_score']    as num? ?? 0).toInt();
        _segments      = [];
      });
    } catch (_) {}
  }

  Future<void> _loadVitals() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      final results = await Future.wait([
        SupabaseService.getHrForDate(user.id, _selectedDate),
        SupabaseService.getSpo2ForDate(user.id, _selectedDate),
        SupabaseService.getHrvForDate(user.id, _selectedDate),
      ]);
      if (!mounted) return;
      final hrRow   = results[0];
      final spo2Row = results[1];
      final hrvRow  = results[2];
      setState(() {
        _avgHr   = (hrRow?['avg_hr']    as num? ?? 0).toInt();
        _avgSpo2 = (spo2Row?['avg_spo2'] as num? ?? 0).toInt();
        _avgHrv  = (hrvRow?['avg_hrv']   as num? ?? 0).toInt();
      });
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    final now  = DateTime.now();
    final from = now.subtract(const Duration(days: 6));
    try {
      final rows = await SupabaseService.getSleepHistory(
        userId: user.id,
        from: DateTime(from.year, from.month, from.day),
        to: DateTime(now.year, now.month, now.day),
      );
      if (!mounted) return;
      setState(() => _historyRows = rows);
    } catch (_) {}
  }

  Future<void> _saveToDb(int total, int deep, int light, int rem, int awake,
      int score, int st, int et) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.upsertSleep(
        userId: user.id,
        date: DateTime.now(),
        totalDuration: total,
        deepDuration: deep,
        lightDuration: light,
        remDuration: rem,
        awakeDuration: awake,
        sleepScore: score,
        sleepTime: st,
        wakeTime: et,
      );
      if (mounted) context.read<BleProvider>().updateSleepData(total, score);
    } catch (_) {}
  }

  // ── Computed helpers ─────────────────────────────────────────────────────────

  String _fmt(int secs) {
    if (secs <= 0) return '--';
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m}m';
  }

  String _timeLabel(int ts) {
    if (ts <= 0) return '--';
    final dt     = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final h      = dt.hour;
    final m      = dt.minute.toString().padLeft(2, '0');
    final suffix = h < 12 ? 'am' : 'pm';
    final h12    = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$m$suffix';
  }

  String _efficiency() {
    if (_sleepTime <= 0 || _wakeTime <= 0 || _totalDuration <= 0) return '--';
    final window = _wakeTime - _sleepTime;
    if (window <= 0) return '--';
    return '${(_totalDuration / window * 100).round()}%';
  }

  String _quality() {
    if (_sleepScore >= 85) return 'Excellent';
    if (_sleepScore >= 70) return 'Good';
    if (_sleepScore >= 55) return 'Fair';
    if (_sleepScore > 0)   return 'Poor';
    return '--';
  }

  int _avgHistoryScore() {
    final vals = _historyRows
        .map((r) => (r['sleep_score'] as num? ?? 0).toInt())
        .where((v) => v > 0)
        .toList();
    if (vals.isEmpty) return 0;
    return vals.fold(0, (a, b) => a + b) ~/ vals.length;
  }

  int _avgHistoryDuration() {
    final vals = _historyRows
        .map((r) => (r['total_duration'] as num? ?? 0).toInt())
        .where((v) => v > 0)
        .toList();
    if (vals.isEmpty) return 0;
    return vals.fold(0, (a, b) => a + b) ~/ vals.length;
  }

  List<int> _last7Bars() {
    final now = DateTime.now();
    final bars = <int>[];
    for (int i = 6; i >= 0; i--) {
      final d   = now.subtract(Duration(days: i));
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final row = _historyRows.firstWhere((r) => r['date'] == key, orElse: () => <String, dynamic>{});
      bars.add((row['total_duration'] as num? ?? 0).toInt());
    }
    return bars;
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasData  = _totalDuration > 0;
    final trendVals = _last7Bars();
    final avgDur   = _avgHistoryDuration();
    final avgScore = _avgHistoryScore();

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Sleep', style: _inter(17, weight: FontWeight.w600)),
        actions: [
          IconButton(icon: const Icon(Icons.more_vert, color: Colors.white), onPressed: () {}),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(color: _kBorder, height: 0.5),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),

            // ── 1. Date row ────────────────────────────────────────────────
            _SleepDateRow(
              selectedDate: _selectedDate,
              onDateSelected: _onDateSelected,
            ),
            const SizedBox(height: 22),

            // ── 2. Current reading ───────────────────────────────────────
            Text(
              'TOTAL SLEEP',
              style: _inter(11, weight: FontWeight.w600, color: AppTheme.gold, letterSpacing: 1.2),
            ),
            const SizedBox(height: 2),
            Text(
              hasData ? _fmt(_totalDuration) : '--',
              style: _inter(52, weight: FontWeight.w300, color: Colors.white, height: 1.1),
            ),
            Text(
              hasData ? 'Score $_sleepScore · ${_quality()}' : (_loading ? 'Loading…' : 'No data yet'),
              style: _inter(13, color: _kSec),
            ),
            const SizedBox(height: 16),

            // ── 3. Sleep stages chart ────────────────────────────────────
            _ChartCard(
              headerLabel: hasData ? 'SLEEP STAGES' : 'NO DATA YET',
              rangeLabel: hasData && _sleepTime > 0
                  ? '${_timeLabel(_sleepTime)} – ${_timeLabel(_wakeTime)}'
                  : '-- --',
              height: 100,
              child: !hasData
                  ? Center(
                      child: Text('NO DATA YET',
                          style: _inter(12, color: _kSec, letterSpacing: 1.2)),
                    )
                  : CustomPaint(
                      painter: _HypnogramPainter(
                        segments: _segments,
                        sleepTime: _sleepTime,
                        wakeTime: _wakeTime,
                        totalDuration: _totalDuration,
                        awakeDuration: _awakeDuration,
                        lightDuration: _lightDuration,
                        deepDuration: _deepDuration,
                        remDuration: _remDuration,
                      ),
                      child: const SizedBox.expand(),
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: const [
                _LegendDot(color: _kAwakeColor, label: 'Awake'),
                _LegendDot(color: _kRemColor,   label: 'REM'),
                _LegendDot(color: _kLightColor, label: 'Light'),
                _LegendDot(color: _kDeepColor,  label: 'Deep'),
              ],
            ),
            const SizedBox(height: 10),

            // ── 4. Stats row ─────────────────────────────────────────────
            Row(children: [
              Expanded(
                child: _StatCard(
                  label: 'EFFICIENCY',
                  value: hasData ? _efficiency() : '--',
                  unit: '',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  label: 'DEEP SLEEP',
                  value: hasData ? _fmt(_deepDuration) : '--',
                  unit: '',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  label: 'REM SLEEP',
                  value: hasData ? _fmt(_remDuration) : '--',
                  unit: '',
                ),
              ),
            ]),
            const SizedBox(height: 10),

            // ── 5. Sleep stages breakdown ────────────────────────────────
            _StagesBreakdownCard(
              hasData: hasData,
              awakeDuration: _awakeDuration,
              lightDuration: _lightDuration,
              deepDuration: _deepDuration,
              remDuration: _remDuration,
              totalDuration: _totalDuration,
              fmt: _fmt,
            ),
            const SizedBox(height: 10),

            // ── 6. Sleep summary ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _kBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SLEEP SUMMARY',
                      style: _inter(11, weight: FontWeight.w600, color: _kSec, letterSpacing: 0.6)),
                  const SizedBox(height: 12),
                  _SummaryRow(label: 'Sleep Duration', value: hasData ? _fmt(_totalDuration) : '--'),
                  const Divider(color: _kBorder, height: 20),
                  _SummaryRow(label: 'Sleep Time', value: hasData && _sleepTime > 0 ? _timeLabel(_sleepTime) : '--'),
                  const Divider(color: _kBorder, height: 20),
                  _SummaryRow(label: 'Wake Time', value: hasData && _wakeTime > 0 ? _timeLabel(_wakeTime) : '--'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── 7. Vitals during sleep ────────────────────────────────────
            Text(
              'VITALS DURING SLEEP',
              style: _inter(11, weight: FontWeight.w600, color: _kSec, letterSpacing: 0.6),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _StatCard(
                  label: 'AVG HEART RATE',
                  value: _avgHr > 0 ? '$_avgHr' : '--',
                  unit: _avgHr > 0 ? 'bpm' : '',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  label: 'AVG BLOOD OXYGEN',
                  value: _avgSpo2 > 0 ? '$_avgSpo2' : '--',
                  unit: _avgSpo2 > 0 ? '%' : '',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  label: 'AVG HRV',
                  value: _avgHrv > 0 ? '$_avgHrv' : '--',
                  unit: _avgHrv > 0 ? 'ms' : '',
                ),
              ),
            ]),
            const SizedBox(height: 20),

            // ── 8. 7-day trend ─────────────────────────────────────────────
            _ChartCard(
              headerLabel: 'LAST 7 DAYS TREND',
              rangeLabel: avgDur > 0 ? 'avg ${_fmt(avgDur)}${avgScore > 0 ? " · score $avgScore" : ""}' : '-- --',
              height: 128,
              child: trendVals.every((v) => v == 0)
                  ? Center(
                      child: Text('NO DATA YET',
                          style: _inter(12, color: _kSec, letterSpacing: 1.2)),
                    )
                  : CustomPaint(painter: _SleepBarPainter(values: trendVals)),
            ),
            const SizedBox(height: 8),
            const _TrendXAxisRow(),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

// ── Date row (same pattern as heart_rate_screen.dart's _HRDateRow) ───────────

class _SleepDateRow extends StatelessWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  const _SleepDateRow({required this.selectedDate, required this.onDateSelected});

  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'
  ];

  @override
  Widget build(BuildContext context) {
    final now  = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dates = List.generate(7, (i) => today.add(Duration(days: i - 3)));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < dates.length; i++) ...[
            if (i > 0) const SizedBox(width: 16),
            _buildItem(dates[i], today),
          ],
        ],
      ),
    );
  }

  Widget _buildItem(DateTime d, DateTime today) {
    final isToday  = d == today;
    final isFuture = d.isAfter(today);
    final sel = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final isSelected = d == sel && !isToday;

    if (isToday || isSelected) {
      return GestureDetector(
        onTap: isToday ? null : () => onDateSelected(d),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF202020),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF363636)),
          ),
          child: Text(
            isToday
                ? 'Today, ${d.day} ${_months[d.month - 1]}'
                : '${d.day} ${_months[d.month - 1]}',
            style: _inter(13, weight: FontWeight.w500),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: isFuture ? null : () => onDateSelected(d),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text(
          '${d.day}',
          style: _inter(15, color: isFuture ? const Color(0xFF333333) : _kSec2),
        ),
      ),
    );
  }
}

// ── Chart card wrapper (same header/border pattern as _HRChartCard) ──────────

class _ChartCard extends StatelessWidget {
  final String headerLabel;
  final String rangeLabel;
  final double height;
  final Widget child;

  const _ChartCard({
    required this.headerLabel,
    required this.rangeLabel,
    required this.child,
    this.height = 128,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(headerLabel,
                  style: _inter(11, weight: FontWeight.w600, color: _kSec, letterSpacing: 0.6)),
              Text(rangeLabel,
                  style: _inter(11, weight: FontWeight.w500, color: const Color(0xFF999999))),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(height: height, width: double.infinity, child: child),
        ],
      ),
    );
  }
}

// ── Stat card (same pattern as _HRStatCard) ───────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  const _StatCard({required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: _inter(10, weight: FontWeight.w600, color: _kSec, letterSpacing: 0.7)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: _inter(17, weight: FontWeight.w600)),
              const SizedBox(width: 4),
              Text(unit, style: _inter(11, color: _kSec)),
            ],
          ),
          const SizedBox(height: 6),
          Text('know more >', style: _inter(11, color: _kSec)),
        ],
      ),
    );
  }
}

// ── Sleep stages breakdown card ───────────────────────────────────────────────

class _StagesBreakdownCard extends StatelessWidget {
  final bool hasData;
  final int awakeDuration, lightDuration, deepDuration, remDuration, totalDuration;
  final String Function(int) fmt;

  const _StagesBreakdownCard({
    required this.hasData,
    required this.awakeDuration,
    required this.lightDuration,
    required this.deepDuration,
    required this.remDuration,
    required this.totalDuration,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final total = totalDuration > 0 ? totalDuration : 1;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SLEEP STAGE BREAKDOWN',
              style: _inter(11, weight: FontWeight.w600, color: _kSec, letterSpacing: 0.6)),
          const SizedBox(height: 14),
          _StageRow(
              label: 'Time Awake',
              value: hasData ? fmt(awakeDuration) : '--',
              progress: hasData ? (awakeDuration / total).clamp(0.0, 1.0) : 0.0,
              color: _kAwakeColor),
          const SizedBox(height: 12),
          _StageRow(
              label: 'Light Sleep',
              value: hasData ? fmt(lightDuration) : '--',
              progress: hasData ? (lightDuration / total).clamp(0.0, 1.0) : 0.0,
              color: _kLightColor),
          const SizedBox(height: 12),
          _StageRow(
              label: 'Deep Sleep',
              value: hasData ? fmt(deepDuration) : '--',
              progress: hasData ? (deepDuration / total).clamp(0.0, 1.0) : 0.0,
              color: _kDeepColor),
          const SizedBox(height: 12),
          _StageRow(
              label: 'REM Sleep',
              value: hasData ? fmt(remDuration) : '--',
              progress: hasData ? (remDuration / total).clamp(0.0, 1.0) : 0.0,
              color: _kRemColor),
        ],
      ),
    );
  }
}

// ── Stage Row ──────────────────────────────────────────────────────────────────

class _StageRow extends StatelessWidget {
  final String label, value;
  final double progress;
  final Color color;
  const _StageRow({required this.label, required this.value, required this.progress, required this.color});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 10),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: _inter(13, weight: FontWeight.w500)),
        Text(value, style: _inter(12, color: _kSec2)),
      ]),
      const SizedBox(height: 5),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: progress,
          backgroundColor: _kBorder,
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 4,
        ),
      ),
    ])),
  ]);
}

// ── Summary Row ────────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final String label, value;
  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: _inter(13, color: _kSec2)),
      Text(value, style: _inter(13, weight: FontWeight.w600)),
    ],
  );
}

// ── Legend Dot ─────────────────────────────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 4),
    Text(label, style: _inter(10, color: _kSec2)),
  ]);
}

// ── 7-day X-axis row ───────────────────────────────────────────────────────────

class _TrendXAxisRow extends StatelessWidget {
  const _TrendXAxisRow();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    const names = ['M','T','W','T','F','S','S'];
    final days = List.generate(7, (i) => now.subtract(Duration(days: 6 - i)));
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: days.map((d) => Text(names[d.weekday - 1], style: _inter(10, color: _kSec2))).toList(),
    );
  }
}

// ── Hypnogram Painter ──────────────────────────────────────────────────────────

class _HypnogramPainter extends CustomPainter {
  final List<Map<String, int>> segments;
  final int sleepTime, wakeTime;
  final int totalDuration, awakeDuration, lightDuration, deepDuration, remDuration;

  const _HypnogramPainter({
    required this.segments,
    required this.sleepTime,
    required this.wakeTime,
    required this.totalDuration,
    required this.awakeDuration,
    required this.lightDuration,
    required this.deepDuration,
    required this.remDuration,
  });

  // Normalized Y position for each stage (0=top, 1=bottom)
  static const _yPos = {
    _kAwake: 0.05,
    _kRem:   0.35,
    _kLight: 0.62,
    _kDeep:  0.88,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final window = (wakeTime > sleepTime && sleepTime > 0)
        ? (wakeTime - sleepTime).toDouble()
        : totalDuration.toDouble();
    if (window <= 0) return;

    final segs = segments.isNotEmpty ? segments : _syntheticSegs();
    if (segs.isEmpty) return;

    final fillPaint = Paint()..style = PaintingStyle.fill;
    final linePath  = Path();
    bool first = true;

    for (int i = 0; i < segs.length; i++) {
      final seg      = segs[i];
      final startOff = (seg['start']! - (sleepTime > 0 ? sleepTime : 0)).clamp(0, window.toInt()).toDouble();
      final endOff   = (seg['end']!   - (sleepTime > 0 ? sleepTime : 0)).clamp(0, window.toInt()).toDouble();
      final type     = seg['type']!;
      final x1       = startOff / window * size.width;
      final x2       = endOff   / window * size.width;
      final y        = (_yPos[type] ?? 0.62) * size.height;
      final color    = _stageColors[type] ?? _kLightColor;

      // Shaded area under segment
      fillPaint.color = color.withValues(alpha: 0.18);
      canvas.drawPath(
        Path()
          ..moveTo(x1, size.height)
          ..lineTo(x1, y)
          ..lineTo(x2, y)
          ..lineTo(x2, size.height)
          ..close(),
        fillPaint,
      );

      // Step line
      if (first) {
        linePath.moveTo(x1, y);
        first = false;
      } else {
        linePath.lineTo(x1, y); // vertical step
      }
      linePath.lineTo(x2, y);
    }

    canvas.drawPath(
      linePath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.75)
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke,
    );
  }

  List<Map<String, int>> _syntheticSegs() {
    if (totalDuration <= 0) return [];
    final base   = sleepTime > 0 ? sleepTime : 0;
    int cursor   = base;
    final parts  = [
      (awakeDuration > 0 ? (awakeDuration ~/ 2).clamp(600, 1800)  : 900,  _kAwake),
      (lightDuration > 0 ? (lightDuration * 0.35).round()         : 2700, _kLight),
      (deepDuration  > 0 ? deepDuration                           : 3600, _kDeep),
      (remDuration   > 0 ? remDuration                            : 2400, _kRem),
      (lightDuration > 0 ? (lightDuration * 0.35).round()         : 2400, _kLight),
      (awakeDuration > 0 ? (awakeDuration ~/ 2).clamp(300, 900)   : 600,  _kAwake),
    ];
    final segs = <Map<String, int>>[];
    for (final p in parts) {
      if (p.$1 <= 0) continue;
      segs.add({'start': cursor, 'end': cursor + p.$1, 'type': p.$2});
      cursor += p.$1;
    }
    return segs;
  }

  @override
  bool shouldRepaint(_HypnogramPainter old) =>
      old.segments != segments || old.sleepTime != sleepTime || old.totalDuration != totalDuration;
}

// ── Sleep Bar Painter (7-day trend) ────────────────────────────────────────────

class _SleepBarPainter extends CustomPainter {
  final List<int> values;
  const _SleepBarPainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxVal = values.fold(0, math.max).toDouble();
    if (maxVal <= 0) return;

    final n    = values.length;
    final gap  = size.width * 0.015;
    final barW = (size.width - gap * (n - 1)) / n;

    // 8h reference line (28800s)
    final refY = size.height - math.min(28800.0, maxVal) / maxVal * size.height;
    canvas.drawLine(
      Offset(0, refY),
      Offset(size.width, refY),
      Paint()..color = Colors.white.withValues(alpha: 0.07)..strokeWidth = 1,
    );

    final paint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < n; i++) {
      final v    = values[i];
      final barH = v > 0 ? math.max(3.0, v / maxVal * size.height) : 3.0;
      final x    = i * (barW + gap);
      paint.color = v > 0 ? AppTheme.sleepColor.withValues(alpha: 0.85) : _kBorder;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, size.height - barH, barW, barH), const Radius.circular(3)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SleepBarPainter old) => old.values != values;
}
