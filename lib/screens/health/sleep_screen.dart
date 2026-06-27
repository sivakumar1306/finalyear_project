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

const _kBg    = Color(0xFF000000);
const _kCard  = Color(0xFF111111);
const _kDiv   = Color(0xFF1E1E1E);
const _kSec2  = Color(0xFF777777);

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

class SleepScreen extends StatefulWidget {
  const SleepScreen({super.key});
  @override
  State<SleepScreen> createState() => _SleepScreenState();
}

class _SleepScreenState extends State<SleepScreen> {
  final _ble = BleService();

  int _period = 0; // 0=Day 1=Week 2=Month
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

  // Week/Month history
  List<Map<String, dynamic>> _historyRows = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _init();
    });
  }

  Future<void> _init() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      if (_period == 0) {
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
      } else {
        await _loadHistory();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    final days = _period == 2 ? 30 : 7;
    final now  = DateTime.now();
    final from = now.subtract(Duration(days: days - 1));
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

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        foregroundColor: Colors.white,
        title: Text('Sleep', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
        actions: [IconButton(icon: const Icon(Icons.more_vert, color: Colors.white), onPressed: () {})],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(color: _kDiv, height: 0.5),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.gold, strokeWidth: 2))
          : SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DateStrip(
                    selected: _selectedDate,
                    onSelect: (d) {
                      setState(() {
                        _selectedDate = d;
                        _period = 0;
                        _totalDuration = 0;
                        _segments = [];
                      });
                      _init();
                    },
                  ),
                  _PeriodTabs(
                    period: _period,
                    onChanged: (p) {
                      setState(() => _period = p);
                      _init();
                    },
                  ),
                  const SizedBox(height: 16),
                  if (_period == 0) ..._dayBody()
                  else            ..._historyBody(),
                ],
              ),
            ),
    );
  }

  // ── Day view ─────────────────────────────────────────────────────────────────

  List<Widget> _dayBody() {
    final hasData = _totalDuration > 0;
    return [
      _buildScoreRow(hasData),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(child: _InfoCard(label: 'SLEEP EFFICIENCY', value: hasData ? _efficiency() : '--', sub: 'Time asleep vs in bed')),
          const SizedBox(width: 10),
          Expanded(child: _InfoCard(label: 'SLEEP QUALITY',    value: hasData ? _quality()    : '--', sub: 'Based on sleep stages')),
        ]),
      ),
      const SizedBox(height: 12),
      _buildStagesCard(hasData),
      const SizedBox(height: 12),
      _buildHypnogramCard(hasData),
      const SizedBox(height: 12),
      _buildSleepSummaryCard(hasData),
      const SizedBox(height: 12),
      _buildVitalCard(
        label: 'AVERAGE HEART RATE',
        value: _avgHr > 0 ? '$_avgHr' : '--',
        unit: 'BPM',
        icon: Icons.favorite_rounded,
        color: const Color(0xFFEF4444),
      ),
      const SizedBox(height: 10),
      _buildVitalCard(
        label: 'AVERAGE BLOOD OXYGEN',
        value: _avgSpo2 > 0 ? '$_avgSpo2' : '--',
        unit: '%',
        icon: Icons.water_drop_rounded,
        color: const Color(0xFF60A5FA),
      ),
      const SizedBox(height: 10),
      _buildVitalCard(
        label: 'AVERAGE HRV',
        value: _avgHrv > 0 ? '$_avgHrv' : '--',
        unit: 'MS',
        icon: Icons.bar_chart_rounded,
        color: const Color(0xFF818CF8),
      ),
      const SizedBox(height: 16),
    ];
  }

  Widget _buildScoreRow(bool hasData) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        SizedBox(
          width: 86, height: 86,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(
              width: 86, height: 86,
              child: CircularProgressIndicator(
                value: hasData ? _sleepScore / 100.0 : 0.0,
                strokeWidth: 7,
                backgroundColor: _kDiv,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.gold),
              ),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                hasData ? '$_sleepScore' : '--',
                style: GoogleFonts.inter(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700),
              ),
              Text('SCORE', style: GoogleFonts.inter(color: AppTheme.gold, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1)),
            ]),
          ]),
        ),
        const SizedBox(width: 18),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('TOTAL DURATION', style: GoogleFonts.inter(color: _kSec2, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(
            hasData ? _fmt(_totalDuration) : '-h --m',
            style: GoogleFonts.inter(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            hasData ? _quality() : 'Wear device to monitor sleep',
            style: GoogleFonts.inter(
              color: hasData ? AppTheme.gold : _kSec2,
              fontSize: 11, fontWeight: FontWeight.w500,
            ),
          ),
        ])),
      ]),
    ),
  );

  Widget _buildStagesCard(bool hasData) {
    final total = _totalDuration > 0 ? _totalDuration : 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            hasData ? 'SLEEP STAGES' : 'WEAR DEVICE TO MONITOR SLEEP',
            style: GoogleFonts.inter(color: _kSec2, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1),
          ),
          const SizedBox(height: 14),
          _StageRow(label: 'Time Awake',  value: hasData ? _fmt(_awakeDuration) : '--', progress: hasData ? (_awakeDuration / total).clamp(0.0, 1.0) : 0.0, color: _kAwakeColor),
          const SizedBox(height: 12),
          _StageRow(label: 'Light Sleep', value: hasData ? _fmt(_lightDuration) : '--', progress: hasData ? (_lightDuration / total).clamp(0.0, 1.0) : 0.0, color: _kLightColor),
          const SizedBox(height: 12),
          _StageRow(label: 'Deep Sleep',  value: hasData ? _fmt(_deepDuration)  : '--', progress: hasData ? (_deepDuration  / total).clamp(0.0, 1.0) : 0.0, color: _kDeepColor),
          const SizedBox(height: 12),
          _StageRow(label: 'REM Sleep',   value: hasData ? _fmt(_remDuration)   : '--', progress: hasData ? (_remDuration   / total).clamp(0.0, 1.0) : 0.0, color: _kRemColor),
        ]),
      ),
    );
  }

  Widget _buildHypnogramCard(bool hasData) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('SLEEP CHART', style: GoogleFonts.inter(color: _kSec2, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
        const SizedBox(height: 12),
        if (!hasData)
          Container(
            height: 90,
            alignment: Alignment.center,
            child: Text('NO DATA YET', style: GoogleFonts.inter(color: _kSec2, fontSize: 12, letterSpacing: 1.2)),
          )
        else ...[
          SizedBox(
            height: 90, width: double.infinity,
            child: CustomPaint(
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
            ),
          ),
          const SizedBox(height: 8),
          _buildXAxisLabels(),
        ],
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: const [
            _LegendDot(color: _kAwakeColor, label: 'Awake'),
            _LegendDot(color: _kRemColor,   label: 'REM'),
            _LegendDot(color: _kLightColor, label: 'Light'),
            _LegendDot(color: _kDeepColor,  label: 'Deep'),
          ],
        ),
      ]),
    ),
  );

  Widget _buildXAxisLabels() {
    if (_sleepTime <= 0 || _wakeTime <= 0) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: ['10pm','12am','2am','4am','6am']
            .map((l) => Text(l, style: GoogleFonts.inter(color: _kSec2, fontSize: 9)))
            .toList(),
      );
    }
    final st   = DateTime.fromMillisecondsSinceEpoch(_sleepTime * 1000);
    final et   = DateTime.fromMillisecondsSinceEpoch(_wakeTime * 1000);
    final spanH = et.difference(st).inHours.clamp(1, 12);
    final interval = (spanH / 4).ceil().clamp(1, 3);
    final labels = <String>[_timeLabel(_sleepTime)];
    for (int i = interval; i < spanH; i += interval) {
      final ts = st.add(Duration(hours: i));
      labels.add(_timeLabel(ts.millisecondsSinceEpoch ~/ 1000));
    }
    labels.add(_timeLabel(_wakeTime));
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: labels.map((l) => Text(l, style: GoogleFonts.inter(color: _kSec2, fontSize: 9))).toList(),
    );
  }

  Widget _buildSleepSummaryCard(bool hasData) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('SLEEP SUMMARY', style: GoogleFonts.inter(color: _kSec2, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
        const SizedBox(height: 12),
        _SummaryRow(label: 'Sleep Duration', value: hasData ? _fmt(_totalDuration)                              : '--'),
        const Divider(color: _kDiv, height: 20),
        _SummaryRow(label: 'Sleep Time',     value: hasData && _sleepTime > 0 ? _timeLabel(_sleepTime) : '--'),
        const Divider(color: _kDiv, height: 20),
        _SummaryRow(label: 'Wake Time',      value: hasData && _wakeTime  > 0 ? _timeLabel(_wakeTime)  : '--'),
      ]),
    ),
  );

  Widget _buildVitalCard({
    required String label,
    required String value,
    required String unit,
    required IconData icon,
    required Color color,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.inter(color: _kSec2, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: GoogleFonts.inter(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700)),
              const SizedBox(width: 5),
              Text(unit,  style: GoogleFonts.inter(color: _kSec2, fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
        ])),
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
      ]),
    ),
  );

  // ── History view ─────────────────────────────────────────────────────────────

  List<Widget> _historyBody() {
    final days     = _period == 2 ? 30 : 7;
    final avgScore = _avgHistoryScore();
    final avgDur   = _avgHistoryDuration();
    final now      = DateTime.now();

    // Build bar values list (oldest first), filling gaps with 0
    final bars = <int>[];
    for (int i = days - 1; i >= 0; i--) {
      final d   = now.subtract(Duration(days: i));
      final key = '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
      final row = _historyRows.firstWhere(
        (r) => r['date'] == key,
        orElse: () => <String, dynamic>{},
      );
      bars.add((row['total_duration'] as num? ?? 0).toInt());
    }

    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(child: _InfoCard(
            label: 'AVG SCORE',
            value: avgScore > 0 ? '$avgScore' : '--',
            sub:   _period == 2 ? 'Last 30 days' : 'Last 7 days',
          )),
          const SizedBox(width: 10),
          Expanded(child: _InfoCard(
            label: 'AVG DURATION',
            value: avgDur > 0 ? _fmt(avgDur) : '--',
            sub:   _period == 2 ? 'Last 30 days' : 'Last 7 days',
          )),
        ]),
      ),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              _period == 2 ? 'SLEEP · LAST 30 DAYS' : 'SLEEP · LAST 7 DAYS',
              style: GoogleFonts.inter(color: _kSec2, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 140, width: double.infinity,
              child: bars.every((b) => b == 0)
                  ? Center(child: Text('NO DATA YET', style: GoogleFonts.inter(color: _kSec2, fontSize: 12, letterSpacing: 1)))
                  : CustomPaint(painter: _SleepBarPainter(values: bars)),
            ),
            const SizedBox(height: 8),
            _XAxisRow(count: days),
          ]),
        ),
      ),
      const SizedBox(height: 16),
    ];
  }
}

// ── Date Strip ─────────────────────────────────────────────────────────────────

class _DateStrip extends StatelessWidget {
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  const _DateStrip({required this.selected, required this.onSelect});

  static const _dayNames = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days  = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
    return SizedBox(
      height: 72,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: 7,
        itemBuilder: (_, i) {
          final d       = days[i];
          final isToday = d.year == today.year && d.month == today.month && d.day == today.day;
          final isSel   = d.year == selected.year && d.month == selected.month && d.day == selected.day;
          return GestureDetector(
            onTap: () => onSelect(d),
            child: Container(
              width: 50,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: isSel ? AppTheme.gold : const Color(0xFF111111),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(
                  _dayNames[d.weekday - 1],
                  style: GoogleFonts.inter(color: isSel ? Colors.black : const Color(0xFF666666), fontSize: 10, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  '${d.day}',
                  style: GoogleFonts.inter(color: isSel ? Colors.black : Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                ),
                if (isToday && !isSel)
                  Container(
                    width: 4, height: 4,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: const BoxDecoration(color: AppTheme.gold, shape: BoxShape.circle),
                  ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ── Period Tabs ────────────────────────────────────────────────────────────────

class _PeriodTabs extends StatelessWidget {
  final int period;
  final ValueChanged<int> onChanged;
  const _PeriodTabs({required this.period, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(children: [
      _Tab(label: 'Day',   active: period == 0, onTap: () => onChanged(0)),
      const SizedBox(width: 8),
      _Tab(label: 'Week',  active: period == 1, onTap: () => onChanged(1)),
      const SizedBox(width: 8),
      _Tab(label: 'Month', active: period == 2, onTap: () => onChanged(2)),
    ]),
  );
}

class _Tab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Tab({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
      decoration: BoxDecoration(
        color: active ? AppTheme.gold : const Color(0xFF111111),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: active ? Colors.black : const Color(0xFF666666),
          fontSize: 13,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ),
  );
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
        Text(label, style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
        Text(value, style: GoogleFonts.inter(color: _kSec2, fontSize: 12)),
      ]),
      const SizedBox(height: 5),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: progress,
          backgroundColor: _kDiv,
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 4,
        ),
      ),
    ])),
  ]);
}

// ── Info Card ──────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final String label, value, sub;
  const _InfoCard({required this.label, required this.value, required this.sub});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: _kDiv)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.inter(color: _kSec2, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1)),
      const SizedBox(height: 6),
      Text(value, style: GoogleFonts.inter(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
      Row(children: [
        Expanded(child: Text(sub, style: GoogleFonts.inter(color: _kSec2, fontSize: 10))),
        Text('know more >', style: GoogleFonts.inter(color: AppTheme.gold, fontSize: 9, fontWeight: FontWeight.w600)),
      ]),
    ]),
  );
}

// ── Summary Row ────────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final String label, value;
  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: GoogleFonts.inter(color: _kSec2, fontSize: 13)),
      Text(value, style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
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
    Text(label, style: GoogleFonts.inter(color: _kSec2, fontSize: 10)),
  ]);
}

// ── X-Axis Row ─────────────────────────────────────────────────────────────────

class _XAxisRow extends StatelessWidget {
  final int count;
  const _XAxisRow({required this.count});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    if (count <= 7) {
      const names = ['M','T','W','T','F','S','S'];
      final days = List.generate(count, (i) => now.subtract(Duration(days: count - 1 - i)));
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: days.map((d) => Text(names[d.weekday - 1], style: GoogleFonts.inter(color: _kSec2, fontSize: 10))).toList(),
      );
    }
    final labels = <String>[];
    for (int i = 0; i < count; i += 5) {
      final d = now.subtract(Duration(days: count - 1 - i));
      labels.add('${d.month}/${d.day}');
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: labels.map((l) => Text(l, style: GoogleFonts.inter(color: _kSec2, fontSize: 9))).toList(),
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

// ── Sleep Bar Painter (history) ────────────────────────────────────────────────

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
      paint.color = v > 0 ? AppTheme.sleepColor.withValues(alpha: 0.85) : _kDiv;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, size.height - barH, barW, barH), const Radius.circular(3)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SleepBarPainter old) => old.values != values;
}
