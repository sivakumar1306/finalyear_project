import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vital_widgets.dart';

// DBP uses a contrasting violet so both lines are distinct
const _dbpColor = Color(0xFFC084FC);

class BloodPressureScreen extends StatefulWidget {
  const BloodPressureScreen({super.key});
  @override
  State<BloodPressureScreen> createState() => _BloodPressureScreenState();
}

class _BloodPressureScreenState extends State<BloodPressureScreen> {
  final _ble = BleService();

  int _period = 0; // 0=Day, 1=Week, 2=Month
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _readings = [];
  bool _loadingData = false;
  bool _measuring = false;
  bool _settingEnabled = true;
  int _settingInterval = 30;

  String _sbp = '--';
  String _dbp = '--';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadData();
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    if (!mounted) return;
    if (!context.read<BleProvider>().isConnected) return;
    try {
      final json = await _ble.getBloodPressureSetting();
      final m = jsonDecode(json) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _settingEnabled = m['enable'] as bool? ?? true;
          _settingInterval = (m['interval'] as num? ?? 30).toInt();
        });
      }
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      await _ble.setBloodPressureSetting(
          enable: _settingEnabled, interval: _settingInterval);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Settings saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ── Data loading ──────────────────────────────────────────────────────────

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
      final data = await SupabaseService.getBpReadings(
          userId: user.id, from: from, to: to);
      if (mounted) {
        setState(() {
          _readings = data;
          _refreshDisplayValues();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  void _refreshDisplayValues() {
    if (_readings.isEmpty) {
      _sbp = '--';
      _dbp = '--';
      return;
    }
    final sorted = [..._readings]
      ..sort((a, b) =>
          (b['measured_at'] as String).compareTo(a['measured_at'] as String));
    final latest = sorted.first;
    _sbp = '${latest['systolic'] ?? '--'}';
    _dbp = '${latest['diastolic'] ?? '--'}';
  }

  // ── Manual measurement ────────────────────────────────────────────────────

  Future<void> _toggleManual() async {
    final start = !_measuring;
    setState(() => _measuring = start);
    try {
      final result = await _ble.manualModeBP(start: start);
      final m = jsonDecode(result) as Map<String, dynamic>;
      final sbp = (m['sbp'] as num? ?? 0).toInt();
      final dbp = (m['dbp'] as num? ?? 0).toInt();
      if (start) {
        setState(() {
          _measuring = false;
          if (sbp > 0 && dbp > 0) {
            _sbp = '$sbp';
            _dbp = '$dbp';
          }
        });
        if (sbp > 0 && dbp > 0) await _saveMeasurement(sbp, dbp);
      } else {
        setState(() => _measuring = false);
      }
    } catch (e) {
      setState(() => _measuring = !start);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _saveMeasurement(int sbp, int dbp) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.insertBp(
        userId: user.id,
        systolic: sbp,
        diastolic: dbp,
        measuredAt: DateTime.now(),
      );
      if (mounted) context.read<BleProvider>().updateBpLatest(sbp, dbp);
      await _loadData();
    } catch (_) {}
  }

  // ── Derived stats ─────────────────────────────────────────────────────────

  ({String avg, String min, String max}) _sbpStats() {
    final vals = _readings
        .map((r) => (r['systolic'] as num? ?? 0).toInt())
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

  Map<String, _DayBpStats> _groupByDay() {
    final map = <String, _DayBpStats>{};
    for (final r in _readings) {
      final dt = DateTime.parse(r['measured_at'] as String).toLocal();
      final key =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      final sbp = (r['systolic'] as num? ?? 0).toInt();
      final dbp = (r['diastolic'] as num? ?? 0).toInt();
      if (sbp <= 0) continue;
      final prev = map[key];
      map[key] = _DayBpStats(
        date: DateTime(dt.year, dt.month, dt.day),
        maxSbp: prev == null ? sbp : (sbp > prev.maxSbp ? sbp : prev.maxSbp),
        minSbp: prev == null ? sbp : (sbp < prev.minSbp ? sbp : prev.minSbp),
        avgSbp: prev == null
            ? sbp.toDouble()
            : (prev.avgSbp * prev.count + sbp) / (prev.count + 1),
        maxDbp: prev == null ? dbp : (dbp > prev.maxDbp ? dbp : prev.maxDbp),
        minDbp: prev == null ? dbp : (dbp < prev.minDbp ? dbp : prev.minDbp),
        avgDbp: prev == null
            ? dbp.toDouble()
            : (prev.avgDbp * prev.count + dbp) / (prev.count + 1),
        count: (prev?.count ?? 0) + 1,
      );
    }
    return map;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _darkBar('Blood Pressure'),
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
              _bpCard(),
              const SizedBox(height: 16),
              _chartCard(),
              const SizedBox(height: 16),
              _statsRow(),
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
              const SizedBox(height: 16),
              _monitorCard(),
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

  Widget _bpCard() {
    final hasData = _sbp != '--' && _dbp != '--';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppTheme.bpColor.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: AppTheme.bpColor.withValues(alpha: 0.15),
                shape: BoxShape.circle),
            child: const Icon(Icons.water_drop_rounded,
                color: AppTheme.bpColor, size: 22),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('BLOOD PRESSURE',
                style: TextStyle(
                    color: AppTheme.bpColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5)),
            Text(
              _measuring
                  ? 'Measuring…'
                  : (hasData ? 'Latest reading' : 'No data yet'),
              style: const TextStyle(color: AppTheme.textSec, fontSize: 12),
            ),
          ]),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: _BPValue(
                  label: 'Systolic',
                  value: _measuring ? '···' : _sbp,
                  unit: 'mmHg')),
          Container(width: 1, height: 50, color: AppTheme.div),
          Expanded(
              child: _BPValue(
                  label: 'Diastolic',
                  value: _measuring ? '···' : _dbp,
                  unit: 'mmHg')),
        ]),
      ]),
    );
  }

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
      chart = CustomPaint(painter: _BPDayChartPainter(_readings));
    } else {
      chart = CustomPaint(
          painter: _BPRangeChartPainter(_groupByDay(), _period == 1 ? 7 : 30));
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
        SizedBox(height: 120, width: double.infinity, child: chart),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: const [
          _Legend(color: AppTheme.bpColor, label: 'Systolic'),
          SizedBox(width: 14),
          _Legend(color: _dbpColor, label: 'Diastolic'),
        ]),
      ]),
    );
  }

  Widget _statsRow() {
    final s = _sbpStats();
    if (_period == 0) {
      return VitalStatsRow(avg: s.avg, min: s.min, max: s.max, unit: 'SBP');
    }
    // Week/Month: max SBP, min SBP, reading count
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.div)),
      child: Row(children: [
        _statCell('Max SBP', s.max, 'mmHg'),
        Container(width: 1, height: 44, color: AppTheme.div),
        _statCell('Avg SBP', s.avg, 'mmHg'),
        Container(width: 1, height: 44, color: AppTheme.div),
        _statCell('Min SBP', s.min, 'mmHg'),
      ]),
    );
  }

  Widget _statCell(String label, String value, String unit) => Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style:
                  const TextStyle(color: AppTheme.textSec, fontSize: 11)),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
          Text(unit,
              style:
                  const TextStyle(color: AppTheme.textSec, fontSize: 10)),
        ]),
      );

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
          final sbp = r['systolic'] ?? 0;
          final dbp = r['diastolic'] ?? 0;
          final isLast = e.key == sorted.length - 1;
          return Column(children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: AppTheme.bpColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.water_drop_rounded,
                      color: AppTheme.bpColor, size: 18),
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
                      Text(r['source'] as String? ?? 'manual',
                          style: const TextStyle(
                              color: AppTheme.textSec, fontSize: 11)),
                    ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('$sbp/$dbp',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 18)),
                  const Text('mmHg',
                      style:
                          TextStyle(color: AppTheme.textSec, fontSize: 10)),
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

  Widget _monitorCard() => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.div)),
        child: Column(children: [
          Row(children: [
            const Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Auto Monitoring',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600)),
                  SizedBox(height: 2),
                  Text('Ring measures BP automatically',
                      style: TextStyle(
                          color: AppTheme.textSec, fontSize: 12)),
                ])),
            Switch.adaptive(
                value: _settingEnabled,
                onChanged: (v) {
                  setState(() => _settingEnabled = v);
                  _saveSettings();
                }),
          ]),
          if (_settingEnabled) ...[
            const Divider(color: AppTheme.div, height: 16),
            Row(children: [
              const Text('Interval',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              const Spacer(),
              DropdownButton<int>(
                value: _settingInterval,
                dropdownColor: AppTheme.card2,
                style: const TextStyle(color: Colors.white),
                underline: const SizedBox(),
                items: [5, 10, 15, 30, 60]
                    .map((e) =>
                        DropdownMenuItem(value: e, child: Text('$e min')))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _settingInterval = v ?? 30),
              ),
              const SizedBox(width: 8),
              TextButton(
                  onPressed: _saveSettings,
                  child: const Text('Save',
                      style: TextStyle(color: AppTheme.gold))),
            ]),
          ],
        ]),
      );

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _fmtTime(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = h < 12 ? 'AM' : 'PM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$m $ampm';
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class _DayBpStats {
  final DateTime date;
  final int maxSbp, minSbp, maxDbp, minDbp, count;
  final double avgSbp, avgDbp;

  const _DayBpStats({
    required this.date,
    required this.maxSbp,
    required this.minSbp,
    required this.avgSbp,
    required this.maxDbp,
    required this.minDbp,
    required this.avgDbp,
    required this.count,
  });
}

// ── Chart painters ────────────────────────────────────────────────────────────

/// Day view: scatter + line by time of day
class _BPDayChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> readings;
  const _BPDayChartPainter(this.readings);

  static const _lo = 50.0;
  static const _hi = 200.0;

  double _y(int v, double h) =>
      h - ((v - _lo) / (_hi - _lo)).clamp(0.0, 1.0) * h * 0.9 - h * 0.05;
  double _x(DateTime dt, double w) =>
      ((dt.hour * 60 + dt.minute) / (24 * 60)) * w;

  @override
  void paint(Canvas canvas, Size size) {
    final sorted = [...readings]
      ..sort(
          (a, b) => (a['measured_at'] as String).compareTo(b['measured_at'] as String));

    final sbpPts = <Offset>[];
    final dbpPts = <Offset>[];

    for (final r in sorted) {
      final dt = DateTime.parse(r['measured_at'] as String).toLocal();
      final sbp = (r['systolic'] as num? ?? 0).toInt();
      final dbp = (r['diastolic'] as num? ?? 0).toInt();
      if (sbp <= 0) continue;
      sbpPts.add(Offset(_x(dt, size.width), _y(sbp, size.height)));
      dbpPts.add(Offset(_x(dt, size.width), _y(dbp, size.height)));
    }

    if (sbpPts.isEmpty) return;

    _drawLine(canvas, sbpPts, AppTheme.bpColor);
    _drawLine(canvas, dbpPts, _dbpColor);

    for (final p in sbpPts) {
      canvas.drawCircle(p, 4,
          Paint()..color = Colors.black..style = PaintingStyle.fill);
      canvas.drawCircle(
          p, 4, Paint()..color = AppTheme.bpColor..style = PaintingStyle.stroke..strokeWidth = 2);
    }
    for (final p in dbpPts) {
      canvas.drawCircle(p, 4,
          Paint()..color = Colors.black..style = PaintingStyle.fill);
      canvas.drawCircle(
          p, 4, Paint()..color = _dbpColor..style = PaintingStyle.stroke..strokeWidth = 2);
    }
  }

  void _drawLine(Canvas canvas, List<Offset> pts, Color color) {
    if (pts.length < 2) return;
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length; i++) {
      final cp = Offset((pts[i - 1].dx + pts[i].dx) / 2, pts[i - 1].dy);
      final cp2 = Offset((pts[i - 1].dx + pts[i].dx) / 2, pts[i].dy);
      path.cubicTo(cp.dx, cp.dy, cp2.dx, cp2.dy, pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_BPDayChartPainter old) => old.readings != readings;
}

/// Week/Month view: grouped bar chart (avg SBP + avg DBP per day)
class _BPRangeChartPainter extends CustomPainter {
  final Map<String, _DayBpStats> groups;
  final int days;
  const _BPRangeChartPainter(this.groups, this.days);

  static const _lo = 50.0;
  static const _hi = 200.0;
  double _h(double v, double maxH) =>
      (((v - _lo) / (_hi - _lo)).clamp(0.0, 1.0) * maxH * 0.85)
          .clamp(3.0, maxH);

  @override
  void paint(Canvas canvas, Size size) {
    final now = DateTime.now();
    final slotW = size.width / days;
    final barW = slotW * 0.3;

    for (int i = 0; i < days; i++) {
      final day = now.subtract(Duration(days: days - 1 - i));
      final key =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      final s = groups[key];
      if (s == null) continue;

      final cx = i * slotW + slotW / 2;

      // SBP bar (left)
      final sbpH = _h(s.avgSbp, size.height);
      canvas.drawRRect(
        RRect.fromLTRBR(cx - barW - 2, size.height - sbpH, cx - 2, size.height,
            const Radius.circular(3)),
        Paint()..color = AppTheme.bpColor,
      );
      // SBP range tick (min–max)
      if (s.maxSbp != s.minSbp) {
        final yMax = size.height - _h(s.maxSbp.toDouble(), size.height);
        final yMin = size.height - _h(s.minSbp.toDouble(), size.height);
        canvas.drawLine(
          Offset(cx - barW / 2 - 2, yMax),
          Offset(cx - barW / 2 - 2, yMin),
          Paint()
            ..color = AppTheme.bpColor.withValues(alpha: 0.35)
            ..strokeWidth = 2,
        );
      }

      // DBP bar (right)
      final dbpH = _h(s.avgDbp, size.height);
      canvas.drawRRect(
        RRect.fromLTRBR(cx + 2, size.height - dbpH, cx + barW + 2, size.height,
            const Radius.circular(3)),
        Paint()..color = _dbpColor,
      );
      if (s.maxDbp != s.minDbp) {
        final yMax = size.height - _h(s.maxDbp.toDouble(), size.height);
        final yMin = size.height - _h(s.minDbp.toDouble(), size.height);
        canvas.drawLine(
          Offset(cx + barW / 2 + 2, yMax),
          Offset(cx + barW / 2 + 2, yMin),
          Paint()
            ..color = _dbpColor.withValues(alpha: 0.35)
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BPRangeChartPainter old) =>
      old.groups != groups || old.days != days;
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _BPValue extends StatelessWidget {
  final String label, value, unit;
  const _BPValue(
      {required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(label,
            style:
                const TextStyle(color: AppTheme.textSec, fontSize: 11)),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w700)),
        Text(unit,
            style:
                const TextStyle(color: AppTheme.textSec, fontSize: 11)),
      ]);
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(radius: 4, backgroundColor: color),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSec, fontSize: 10)),
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
