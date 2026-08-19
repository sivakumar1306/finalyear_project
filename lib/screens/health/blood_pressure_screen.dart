import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/incident_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_menu.dart';
import '../../widgets/offline_notice.dart';
import '../../widgets/screenshot_share.dart';
import 'vital_note_screen.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/date_scroll_row.dart';
import '../../utils/bp_staging.dart';
import '../../widgets/legend_dot.dart';
import '../../widgets/metric_chart_card.dart';
import '../../widgets/metric_stat_card.dart';


// ── Local design tokens ───────────────────────────────────────────────────────


TextStyle _inter(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = Colors.white,
  double? letterSpacing,
  double? height,
}) => AppTypography.inter(
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: letterSpacing,
  height: height,
);

String _bpStatus(int sbp, int dbp) => bpStatusLabel(sbp, dbp);

Color _bpStatusColor(int sbp, int dbp) =>
    bpStatusColor(sbp, dbp, noDataColor: AppTheme.textSec);

// ── Screen ────────────────────────────────────────────────────────────────────

class BloodPressureScreen extends StatefulWidget {
  const BloodPressureScreen({super.key});
  @override
  State<BloodPressureScreen> createState() => _BloodPressureScreenState();
}

class _BloodPressureScreenState extends State<BloodPressureScreen> {
  final _ble = BleService();
  final _moreButtonKey = GlobalKey();
  final _screenshotKey = GlobalKey();

  bool _loading = false;
  bool _loadingDay = false;
  bool _loadingTrend = false;
  bool _measuring = false;
  bool _dayOffline = false;
  bool _trendOffline = false;

  DateTime _selectedDate = DateTime.now();

  int _manualSbp = 0, _manualDbp = 0;

  // Today's local-DB data
  List<int> _chartSbp = [];
  List<int> _chartDbp = [];
  int _avgSbp = 0, _minSbp = 0, _maxSbp = 0;
  int _avgDbp = 0, _minDbp = 0, _maxDbp = 0;

  // Past-day Supabase data
  int _daySbpAvg = 0, _daySbpMin = 0, _daySbpMax = 0;
  int _dayDbpAvg = 0, _dayDbpMin = 0, _dayDbpMax = 0;

  // 7-day trend
  List<int> _trendSbp = [];
  List<int> _trendDbp = [];

  // ── Computed ──────────────────────────────────────────────────────────────────

  bool get _isToday {
    final n = DateTime.now();
    return _selectedDate.year == n.year &&
        _selectedDate.month == n.month &&
        _selectedDate.day == n.day;
  }

  int get _displaySbpAvg {
    if (!_isToday) return _daySbpAvg;
    try {
      final v = context.read<BleProvider>().latestBpSbp;
      if (v > 0) return v;
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'blood_pressure_screen',
        error: e,
        stackTrace: st,
        customMessage: 'read latestBpSbp failed',
      );
    }
    if (_avgSbp > 0) return _avgSbp;
    return 0;
  }

  int get _displaySbpMin {
    if (!_isToday) return _daySbpMin;
    if (_minSbp > 0) return _minSbp;
    return 0;
  }

  int get _displaySbpMax {
    if (!_isToday) return _daySbpMax;
    if (_maxSbp > 0) return _maxSbp;
    return 0;
  }

  int get _displayDbpAvg {
    if (!_isToday) return _dayDbpAvg;
    try {
      final v = context.read<BleProvider>().latestBpDbp;
      if (v > 0) return v;
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'blood_pressure_screen',
        error: e,
        stackTrace: st,
        customMessage: 'read latestBpDbp failed',
      );
    }
    if (_avgDbp > 0) return _avgDbp;
    return 0;
  }

  int get _displayDbpMin {
    if (!_isToday) return _dayDbpMin;
    if (_minDbp > 0) return _minDbp;
    return 0;
  }

  int get _displayDbpMax {
    if (!_isToday) return _dayDbpMax;
    if (_maxDbp > 0) return _maxDbp;
    return 0;
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Init ──────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _fetchTodayFromLocalDb();
      _load7DayTrend();
    });
  }



  // ── Date selection ────────────────────────────────────────────────────────────

  void _onDateSelected(DateTime date) {
    final n = DateTime.now();
    final isToday =
        date.year == n.year && date.month == n.month && date.day == n.day;
    setState(() {
      _selectedDate = date;
      _manualSbp = 0;
      _manualDbp = 0;
      if (isToday) {
        _daySbpAvg = _daySbpMin = _daySbpMax = 0;
        _dayDbpAvg = _dayDbpMin = _dayDbpMax = 0;
      }
    });
    if (!isToday) {
      _loadDayFromSupabase(date);
    } else {
      _fetchTodayFromLocalDb();
    }
  }

  // ── Local DB fetch (today) ──────────────────────────────────────────────────

  Future<void> _fetchTodayFromLocalDb() async {
    setState(() {
      _manualSbp = 0;
      _manualDbp = 0;
    });
    try {
      final now = DateTime.now();
      final dayStart = DateTime(
        now.year,
        now.month,
        now.day,
      ).millisecondsSinceEpoch;
      final dayEnd = DateTime(
        now.year,
        now.month,
        now.day,
        23,
        59,
        59,
        999,
      ).millisecondsSinceEpoch;

      final summary =
          jsonDecode(await _ble.getTodaySummary('blood_pressure'))
              as Map<String, dynamic>;
      final count = (summary['count'] as num? ?? 0).toInt();

      final sbpHourly = List<int>.filled(24, 0);
      final dbpHourly = List<int>.filled(24, 0);
      if (count > 0) {
        final readingsJson = await _ble.getReadings(
          'blood_pressure',
          fromMs: dayStart,
          toMs: dayEnd,
          limit: 1000,
        );
        final decoded = jsonDecode(readingsJson);
        final list = decoded is List ? decoded : <dynamic>[];
        final sbpSums = List<int>.filled(24, 0);
        final dbpSums = List<int>.filled(24, 0);
        final counts = List<int>.filled(24, 0);
        for (final item in list) {
          final m = item as Map<String, dynamic>;
          final sbp = (m['systolic'] as num? ?? 0).toInt();
          final dbp = (m['diastolic'] as num? ?? 0).toInt();
          final measuredAt = (m['measuredAt'] as num? ?? 0).toInt();
          if (sbp <= 0 || dbp <= 0 || measuredAt <= 0) continue;
          final h = DateTime.fromMillisecondsSinceEpoch(measuredAt).hour;
          sbpSums[h] += sbp;
          dbpSums[h] += dbp;
          counts[h] += 1;
        }
        for (int h = 0; h < 24; h++) {
          if (counts[h] > 0) {
            sbpHourly[h] = (sbpSums[h] / counts[h]).round();
            dbpHourly[h] = (dbpSums[h] / counts[h]).round();
          }
        }
      }

      if (!mounted) return;
      final avgSbp = (summary['avgSbp'] as num?)?.round() ?? 0;
      final minSbp = (summary['minSbp'] as num?)?.toInt() ?? 0;
      final maxSbp = (summary['maxSbp'] as num?)?.toInt() ?? 0;
      final avgDbp = (summary['avgDbp'] as num?)?.round() ?? 0;
      final minDbp = (summary['minDbp'] as num?)?.toInt() ?? 0;
      final maxDbp = (summary['maxDbp'] as num?)?.toInt() ?? 0;
      setState(() {
        _chartSbp = sbpHourly;
        _chartDbp = dbpHourly;
        _avgSbp = avgSbp;
        _minSbp = minSbp;
        _maxSbp = maxSbp;
        _avgDbp = avgDbp;
        _minDbp = minDbp;
        _maxDbp = maxDbp;
        _selectedDate = DateTime.now();
      });
      final lastSbp = (summary['lastSbp'] as num?)?.toInt() ?? avgSbp;
      final lastDbp = (summary['lastDbp'] as num?)?.toInt() ?? avgDbp;
      if (lastSbp > 0 && lastDbp > 0) {
        context.read<BleProvider>().updateBpLatest(lastSbp, lastDbp);
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'blood_pressure_screen',
        error: e,
        stackTrace: st,
        customMessage: '_loadToday failed',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Supabase fetches (past days / trend — historical data predates local DB) ─

  Future<void> _loadDayFromSupabase(DateTime date) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() {
      _loadingDay = true;
      _dayOffline = false;
    });
    try {
      final from = DateTime(date.year, date.month, date.day);
      final to = DateTime(date.year, date.month, date.day, 23, 59, 59);
      final rows = await SupabaseService.getBpReadings(
        userId: user.id,
        from: from,
        to: to,
      );

      final sbpHourly = List<int>.filled(24, 0);
      final dbpHourly = List<int>.filled(24, 0);
      final sbpSums = List<int>.filled(24, 0);
      final dbpSums = List<int>.filled(24, 0);
      final counts = List<int>.filled(24, 0);
      for (final r in rows) {
        final dt = DateTime.parse(r['measured_at'] as String).toLocal();
        final h = dt.hour;
        final sbp = (r['systolic'] as num? ?? 0).toInt();
        final dbp = (r['diastolic'] as num? ?? 0).toInt();
        if (sbp <= 0 || dbp <= 0) continue;
        sbpSums[h] += sbp;
        dbpSums[h] += dbp;
        counts[h] += 1;
      }
      for (int h = 0; h < 24; h++) {
        if (counts[h] > 0) {
          sbpHourly[h] = (sbpSums[h] / counts[h]).round();
          dbpHourly[h] = (dbpSums[h] / counts[h]).round();
        }
      }

      if (!mounted) return;
      final sbps = rows
          .map((r) => (r['systolic'] as num? ?? 0).toInt())
          .where((v) => v > 0)
          .toList();
      final dbps = rows
          .map((r) => (r['diastolic'] as num? ?? 0).toInt())
          .where((v) => v > 0)
          .toList();
      setState(() {
        if (sbps.isNotEmpty) {
          _daySbpAvg = (sbps.reduce((a, b) => a + b) / sbps.length).round();
          _daySbpMin = sbps.reduce((a, b) => a < b ? a : b);
          _daySbpMax = sbps.reduce((a, b) => a > b ? a : b);
        }
        if (dbps.isNotEmpty) {
          _dayDbpAvg = (dbps.reduce((a, b) => a + b) / dbps.length).round();
          _dayDbpMin = dbps.reduce((a, b) => a < b ? a : b);
          _dayDbpMax = dbps.reduce((a, b) => a > b ? a : b);
        }
        if (_selectedDate == date) {
          _chartSbp = sbpHourly;
          _chartDbp = dbpHourly;
        }
      });
    } catch (e) {
      if (mounted && isNetworkError(e)) setState(() => _dayOffline = true);
    } finally {
      if (mounted) setState(() => _loadingDay = false);
    }
  }

  Future<void> _load7DayTrend() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() {
      _loadingTrend = true;
      _trendOffline = false;
    });
    try {
      final now = DateTime.now();
      final rows = await SupabaseService.getBpReadings(
        userId: user.id,
        from: now.subtract(const Duration(days: 6)),
        to: now,
      );
      final byDaySbp = <String, List<int>>{};
      final byDayDbp = <String, List<int>>{};
      for (final r in rows) {
        final dt = DateTime.parse(r['measured_at'] as String).toLocal();
        final key = _fmt(dt);
        final sbp = (r['systolic'] as num? ?? 0).toInt();
        final dbp = (r['diastolic'] as num? ?? 0).toInt();
        if (sbp > 0) byDaySbp.putIfAbsent(key, () => []).add(sbp);
        if (dbp > 0) byDayDbp.putIfAbsent(key, () => []).add(dbp);
      }
      final sbpVals = List.generate(7, (i) {
        final day = now.subtract(Duration(days: 6 - i));
        final vals = byDaySbp[_fmt(day)];
        if (vals == null || vals.isEmpty) return 0;
        return (vals.reduce((a, b) => a + b) / vals.length).round();
      });
      final dbpVals = List.generate(7, (i) {
        final day = now.subtract(Duration(days: 6 - i));
        final vals = byDayDbp[_fmt(day)];
        if (vals == null || vals.isEmpty) return 0;
        return (vals.reduce((a, b) => a + b) / vals.length).round();
      });
      if (!mounted) return;
      setState(() {
        _trendSbp = sbpVals;
        _trendDbp = dbpVals;
      });
    } catch (e) {
      if (mounted && isNetworkError(e)) setState(() => _trendOffline = true);
    } finally {
      if (mounted) setState(() => _loadingTrend = false);
    }
  }

  // ── Manual measurement ────────────────────────────────────────────────────────

  Future<void> _startMeasurement() async {
    if (_measuring) return;
    setState(() {
      _measuring = true;
      _manualSbp = 0;
      _manualDbp = 0;
    });
    try {
      final result = await _ble.manualModeBP(start: true);
      final m = jsonDecode(result) as Map<String, dynamic>;
      final sbp = (m['sbp'] as num? ?? 0).toInt();
      final dbp = (m['dbp'] as num? ?? 0).toInt();
      if (!mounted) return;
      setState(() => _measuring = false);
      if (sbp > 0 && dbp > 0) {
        setState(() {
          _manualSbp = sbp;
          _manualDbp = dbp;
        });
        await _saveMeasurement(sbp, dbp);
      }
    } catch (_) {
      if (mounted) setState(() => _measuring = false);
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
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'blood_pressure_screen',
        error: e,
        stackTrace: st,
        customMessage: '_saveMeasurement failed',
      );
    }
  }

  // ── Three-dot menu ────────────────────────────────────────────────────────

  void _openMenu() {
    showGlassMenu(
      context: context,
      anchorKey: _moreButtonKey,
      items: [
        GlassMenuItem(
          label: 'Share',
          onTap: () => shareScreenshot(
            _screenshotKey,
            text: 'My Blood Pressure — SUNDR',
          ),
        ),
        GlassMenuItem(
          label: 'Note',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const VitalNoteScreen(
                title: 'Blood Pressure',
                heading: 'About Blood Pressure',
                intro:
                    'Systolic (top) over diastolic (bottom) — the pressure '
                    'in your arteries as your heart beats and rests. '
                    'Cuffless ring readings are an estimate, best read as a '
                    'trend rather than a single exact number.',
                ranges: [
                  VitalRange(
                    label: 'Normal',
                    range: '<120/80',
                    color: AppTheme.success,
                  ),
                  VitalRange(
                    label: 'Elevated',
                    range: '120–129/<80',
                    color: AppTheme.amber,
                  ),
                  VitalRange(
                    label: 'Stage 1',
                    range: '130–139/80–89',
                    color: AppTheme.stressColor,
                  ),
                  VitalRange(
                    label: 'Stage 2',
                    range: '140+/90+',
                    color: AppTheme.danger,
                  ),
                ],
                tips: [
                  VitalTip(
                    icon: Icons.self_improvement_rounded,
                    color: AppTheme.success,
                    title: 'Sodium adds up fast',
                    tip:
                        'Cutting back on salty, processed food is one of '
                        'the quickest ways to bring elevated readings down.',
                  ),
                  VitalTip(
                    icon: Icons.schedule_rounded,
                    color: AppTheme.bpColor,
                    title: 'Measure the same way',
                    tip:
                        'Readings taken while resting, seated, and at the '
                        'same time of day are the most comparable over time.',
                  ),
                ],
                didYouKnow:
                    'Blood pressure naturally dips at night and rises in '
                    'the morning — a single high reading isn\'t cause for alarm.',
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  List<String> _trendXLabels() {
    final now = DateTime.now();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return days[d.weekday - 1];
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;

    final sbpText = _measuring
        ? '···'
        : _manualSbp > 0
        ? '$_manualSbp'
        : _displaySbpAvg > 0
        ? '$_displaySbpAvg'
        : '--';
    final dbpText = _measuring
        ? '···'
        : _manualDbp > 0
        ? '$_manualDbp'
        : _displayDbpAvg > 0
        ? '$_displayDbpAvg'
        : '--';

    final currentSbp = _manualSbp > 0 ? _manualSbp : _displaySbpAvg;
    final currentDbp = _manualDbp > 0 ? _manualDbp : _displayDbpAvg;
    final currentLabel = _measuring
        ? 'Measuring…'
        : _bpStatus(currentSbp, currentDbp);
    final currentLabelColor = _bpStatusColor(currentSbp, currentDbp);

    final hasData = _chartSbp.any((v) => v > 0) || _chartDbp.any((v) => v > 0);

    final dailyRangeLabel = hasData
        ? '$_displaySbpMin-$_displaySbpMax / $_displayDbpMin-$_displayDbpMax'
        : '-- --';

    final trendNonZeroSbp = _trendSbp.where((v) => v > 0).toList();
    final trendRangeLabel = trendNonZeroSbp.isNotEmpty
        ? '${trendNonZeroSbp.reduce((a, b) => a < b ? a : b)} - ${trendNonZeroSbp.reduce((a, b) => a > b ? a : b)} mmHg'
        : '-- -- mmHg';

    return RepaintBoundary(
      key: _screenshotKey,
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(
          backgroundColor: AppTheme.bg,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: const GlassBackButton(),
          title: Text(
            'Blood Pressure',
            style: _inter(17, weight: FontWeight.w600),
          ),
          actions: [
            IconButton(
              key: _moreButtonKey,
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onPressed: _openMenu,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(0.5),
            child: Container(color: AppTheme.div, height: 0.5),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // ── 2. Date row ────────────────────────────────────────────────
              DateScrollRow(
                selectedDate: _selectedDate,
                onDateSelected: _onDateSelected,
              ),
              const SizedBox(height: 22),

              // ── 3. Current BP value ────────────────────────────────────────
              Text(
                'CURRENT BLOOD PRESSURE',
                style: _inter(
                  11,
                  weight: FontWeight.w600,
                  color: AppTheme.gold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    sbpText,
                    style: _inter(
                      52,
                      weight: FontWeight.w300,
                      color: Colors.white,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    '/',
                    style: _inter(36, weight: FontWeight.w300, color: AppTheme.textTertiary),
                  ),
                  Text(
                    dbpText,
                    style: _inter(
                      52,
                      weight: FontWeight.w300,
                      color: Colors.white,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('mmHg', style: _inter(13, color: AppTheme.textTertiary)),
                  if (currentLabel.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: currentLabelColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        currentLabel,
                        style: _inter(
                          11,
                          weight: FontWeight.w600,
                          color: currentLabelColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              // ── 4. Daily chart ─────────────────────────────────────────────
              MetricChartCard(
                headerLabel: hasData ? 'TODAY' : 'NO DATA YET',
                rangeLabel: dailyRangeLabel,
                yLabels: const ['160', '120', '80', '40'],
                loadingAccent: AppTheme.bpColor,
                barCount: _chartSbp.length,
                xLabels: const ['12am', '6am', '12pm', '6pm', ''],
                loading: _loading || _loadingDay,
                child: CustomPaint(
                  painter: _BPBarPainter(
                    sbpValues: _chartSbp,
                    dbpValues: _chartDbp,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              if (_dayOffline && !_isToday) ...[
                const SizedBox(height: 8),
                const OfflineNotice(
                  message: 'Connect to WiFi to load this day\'s blood pressure',
                ),
              ],
              const SizedBox(height: 10),

              // ── 5. Stats row ───────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: MetricStatCard(
                      label: 'AVERAGE',
                      value: (_displaySbpAvg > 0 && _displayDbpAvg > 0)
                          ? '$_displaySbpAvg/$_displayDbpAvg'
                          : '--',
                      unit: (_displaySbpAvg > 0 && _displayDbpAvg > 0)
                          ? 'mmHg'
                          : '',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: MetricStatCard(
                      label: 'MINIMUM',
                      value: (_displaySbpMin > 0 && _displayDbpMin > 0)
                          ? '$_displaySbpMin/$_displayDbpMin'
                          : '--',
                      unit: (_displaySbpMin > 0 && _displayDbpMin > 0)
                          ? 'mmHg'
                          : '',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: MetricStatCard(
                      label: 'MAXIMUM',
                      value: (_displaySbpMax > 0 && _displayDbpMax > 0)
                          ? '$_displaySbpMax/$_displayDbpMax'
                          : '--',
                      unit: (_displaySbpMax > 0 && _displayDbpMax > 0)
                          ? 'mmHg'
                          : '',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // ── 6. Real-time measurement ───────────────────────────────────
              _RealTimeBPCard(
                sbp: _manualSbp,
                dbp: _manualDbp,
                measuring: _measuring,
                enabled: connected && !_measuring,
                onTap: _startMeasurement,
              ),
              const SizedBox(height: 20),

              // ── 7. 7-day trend ─────────────────────────────────────────────
              MetricChartCard(
                headerLabel: 'LAST 7 DAYS TREND',
                rangeLabel: trendRangeLabel,
                yLabels: const ['160', '120', '80', '40'],
                loadingAccent: AppTheme.bpColor,
                barCount: _trendSbp.length,
                xLabels: _trendXLabels(),
                loading: _loadingTrend,
                footer: const Row(
                  children: [
                    LegendDot(color: AppTheme.bpColor, label: 'Systolic'),
                    SizedBox(width: 14),
                    LegendDot(color: AppTheme.softViolet, label: 'Diastolic'),
                  ],
                ),
                child: CustomPaint(
                  painter: _BPBarPainter(
                    sbpValues: _trendSbp,
                    dbpValues: _trendDbp,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              if (_trendOffline) ...[
                const SizedBox(height: 8),
                const OfflineNotice(
                  message: 'Connect to WiFi to load your 7-day trend',
                ),
              ],

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}

// ── BP Bar Painter ─────────────────────────────────────────────────────────────

class _BPBarPainter extends CustomPainter {
  final List<int> sbpValues;
  final List<int> dbpValues;
  const _BPBarPainter({required this.sbpValues, required this.dbpValues});

  static const _maxY = 160.0;
  static const _yLines = [160, 120, 80, 40];

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppTheme.grid
      ..strokeWidth = 0.5;
    for (final y in _yLines) {
      final yPos = size.height - (y / _maxY) * size.height;
      canvas.drawLine(Offset(0, yPos), Offset(size.width, yPos), gridPaint);
    }

    final n = sbpValues.length;
    if (n == 0) return;
    final slotW = size.width / n;
    final barW = (slotW * 0.3).clamp(1.5, 5.0);
    final sbpPaint = Paint()..color = AppTheme.bpColor.withValues(alpha: 0.88);
    final dbpPaint = Paint()..color = AppTheme.softViolet.withValues(alpha: 0.88);

    for (int i = 0; i < n; i++) {
      final cx = i * slotW + slotW / 2;

      final sbp = sbpValues[i];
      if (sbp > 0) {
        final ratio = (sbp / _maxY).clamp(0.0, 1.0);
        final barH = (ratio * size.height).clamp(2.0, size.height);
        canvas.drawRRect(
          RRect.fromLTRBR(
            cx - barW - 1,
            size.height - barH,
            cx - 1,
            size.height,
            const Radius.circular(2),
          ),
          sbpPaint,
        );
      }

      final dbp = i < dbpValues.length ? dbpValues[i] : 0;
      if (dbp > 0) {
        final ratio = (dbp / _maxY).clamp(0.0, 1.0);
        final barH = (ratio * size.height).clamp(2.0, size.height);
        canvas.drawRRect(
          RRect.fromLTRBR(
            cx + 1,
            size.height - barH,
            cx + barW + 1,
            size.height,
            const Radius.circular(2),
          ),
          dbpPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BPBarPainter old) =>
      old.sbpValues != sbpValues || old.dbpValues != dbpValues;
}

// ── Real-time measurement card ────────────────────────────────────────────────

class _RealTimeBPCard extends StatelessWidget {
  final int sbp;
  final int dbp;
  final bool measuring;
  final bool enabled;
  final VoidCallback? onTap;

  const _RealTimeBPCard({
    required this.sbp,
    required this.dbp,
    required this.measuring,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bpText = measuring
        ? '···'
        : (sbp > 0 && dbp > 0)
        ? '$sbp/$dbp'
        : '--';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.div),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Real Time Blood Pressure',
                style: _inter(14, weight: FontWeight.w500),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    bpText,
                    style: _inter(
                      15,
                      weight: FontWeight.w600,
                      color: measuring || (sbp > 0 && dbp > 0)
                          ? Colors.white
                          : AppTheme.textSec,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('mmHg', style: _inter(11, color: AppTheme.textTertiary)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: enabled ? onTap : null,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.surfaceMid,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.dividerSoft),
              ),
              child: Center(
                child: measuring
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: enabled ? AppTheme.bpColor : AppTheme.textTertiary,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Click to start measurement',
                        style: _inter(
                          14,
                          weight: FontWeight.w500,
                          color: enabled ? Colors.white70 : AppTheme.textTertiary,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

