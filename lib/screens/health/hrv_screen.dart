import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/health_connect_service.dart';
import '../../services/incident_service.dart';
import '../../services/local_vitals_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/real_time_card.dart';
import '../../widgets/glass_menu.dart';
import '../../widgets/offline_notice.dart';
import '../../widgets/screenshot_share.dart';
import 'vital_note_screen.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/date_scroll_row.dart';
import '../../widgets/legend_dot.dart';
import '../../widgets/metric_bar_painter.dart';
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

// ── Screen ────────────────────────────────────────────────────────────────────

class HrvScreen extends StatefulWidget {
  const HrvScreen({super.key});
  @override
  State<HrvScreen> createState() => _HrvScreenState();
}

class _HrvScreenState extends State<HrvScreen> {
  final _ble = BleService();
  final _local = LocalVitalsService();
  final _moreButtonKey = GlobalKey();
  final _screenshotKey = GlobalKey();

  bool _loading = false;
  bool _loadingDay = false;
  bool _loadingTrend = false;
  bool _measuring = false;
  bool _dayOffline = false;
  bool _trendOffline = false;
  int _manualHrv = 0;

  DateTime _selectedDate = DateTime.now();

  // Today's local-DB data
  List<int> _chartValues = [];
  int _avgHrv = 0, _minHrv = 0, _maxHrv = 0;

  // Past-day / Supabase data
  int _dayAvg = 0, _dayMin = 0, _dayMax = 0;

  // 7-day trend
  List<int> _trendValues = [];
  int _trendMin = 0, _trendMax = 0;

  // ── Computed ──────────────────────────────────────────────────────────────

  bool get _isToday {
    final n = DateTime.now();
    return _selectedDate.year == n.year &&
        _selectedDate.month == n.month &&
        _selectedDate.day == n.day;
  }

  bool get _hasRingData => _chartValues.any((v) => v > 0);

  int get _displayAvg {
    if (!_isToday) return _dayAvg;
    if (_avgHrv > 0) return _avgHrv;
    try { return context.read<BleProvider>().todayAvgHrv; } catch(_) { return 0; }
  }

  int get _displayMin {
    if (!_isToday) return _dayMin;
    if (_minHrv > 0) return _minHrv;
    return 0; // BleProvider doesn't track min/max HRV for today yet
  }

  int get _displayMax {
    if (!_isToday) return _dayMax;
    if (_maxHrv > 0) return _maxHrv;
    return 0; // BleProvider doesn't track min/max HRV for today yet
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _hrvLabel(int v) {
    if (v <= 0) return '--';
    if (v < 20) return 'Very Low';
    if (v < 40) return 'Low';
    if (v < 60) return 'Moderate';
    if (v < 80) return 'Good';
    return 'Excellent';
  }

  static Color _hrvColor(int v) {
    if (v <= 0) return AppTheme.textSec;
    if (v < 20) return AppTheme.danger;
    if (v < 40) return AppTheme.stressColor;
    if (v < 60) return AppTheme.amber;
    if (v < 80) return AppTheme.success;
    return AppTheme.hrvColor;
  }

  static String _fmtTime(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = h < 12 ? 'AM' : 'PM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$m $ampm';
  }

  // ── Init ──────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _fetchTodayFromLocalDb();
      _load7DayTrend();
    });
  }



  // ── Date selection ────────────────────────────────────────────────────────

  void _onDateSelected(DateTime date) {
    final n = DateTime.now();
    final isToday =
        date.year == n.year && date.month == n.month && date.day == n.day;
    setState(() {
      _selectedDate = date;
      if (isToday) {
        _dayAvg = _dayMin = _dayMax = 0;
      }
    });
    if (!isToday) {
      _loadDayFromSupabase(date);
    } else {
      _fetchTodayFromLocalDb();
    }
  }

  // ── Local DB fetch (today) ───────────────────────────────────────────────

  Future<void> _fetchTodayFromLocalDb() async {
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
          jsonDecode(await _ble.getTodaySummary('hrv')) as Map<String, dynamic>;

      const totalSlots = 48;
      final slots = List<int>.filled(totalSlots, 0);

      try {
        final readingsJson = await _ble.getReadings(
          'hrv',
          fromMs: dayStart,
          toMs: dayEnd,
          limit: 1000,
        );
        final decoded = jsonDecode(readingsJson);
        final list = decoded is List ? decoded : <dynamic>[];

        final slotSums = List<int>.filled(totalSlots, 0);
        final slotCounts = List<int>.filled(totalSlots, 0);
        for (final item in list) {
          final m = item as Map<String, dynamic>;
          final value = (m['valueMs'] as num? ?? 0).toInt();
          final measuredAt = (m['measuredAt'] as num? ?? 0).toInt();
          if (value <= 0 || measuredAt <= 0) continue;
          final dt = DateTime.fromMillisecondsSinceEpoch(measuredAt);
          final slot = (dt.hour * 60 + dt.minute) ~/ 30;
          if (slot >= 0 && slot < totalSlots) {
            slotSums[slot] += value;
            slotCounts[slot] += 1;
          }
        }
        for (int i = 0; i < totalSlots; i++) {
          if (slotCounts[i] > 0) {
            slots[i] = (slotSums[i] / slotCounts[i]).round();
          }
        }
      } catch (e, st) {
        IncidentService.reportUnhandled(
          source: 'hrv_screen',
          error: e,
          stackTrace: st,
          customMessage: 'build daily chart slots failed',
        );
      }

      if (!mounted) return;
      final avg = (summary['avg'] as num?)?.round() ?? 0;
      if (!slots.any((v) => v > 0) && mounted) {
        final liveVal = context.read<BleProvider>().todayAvgHrv;
        if (liveVal > 0) {
          final currentSlot = (now.hour * 60 + now.minute) ~/ 30;
          if (currentSlot >= 0 && currentSlot < totalSlots) {
            slots[currentSlot] = liveVal;
          }
        }
      }
      setState(() {
        _chartValues = slots;
        _avgHrv = avg;
        _minHrv = (summary['min'] as num? ?? 0).toInt();
        _maxHrv = (summary['max'] as num? ?? 0).toInt();
        _selectedDate = now;
      });
      if (avg > 0 && mounted) context.read<BleProvider>().updateHrvLatest(avg);
    } catch (_) {
      // Local DB read failing isn't worth surfacing loudly — chart just stays blank.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Manual "Measure Now" (for debugging the one-click HRV path) ───────────

  Future<void> _startMeasurement() async {
    if (_measuring) return;
    setState(() {
      _measuring = true;
      _manualHrv = 0;
    });
    try {
      final result = await _ble.manualModeHrv(start: true);
      int liveVal = 0;
      try {
        final m = jsonDecode(result) as Map<String, dynamic>;
        liveVal = (m['value'] as num?)?.toInt() ?? 0;
      } catch (e, st) {
        IncidentService.reportUnhandled(
          source: 'hrv_screen',
          error: e,
          stackTrace: st,
          customMessage: 'parse manual hrv result failed',
        );
      }
      if (!mounted) return;
      setState(() {
        _measuring = false;
        if (liveVal > 0) _manualHrv = liveVal;
      });
      if (liveVal > 0) await _saveSingleMeasurement(liveVal);
    } catch (e) {
      if (!mounted) return;
      setState(() => _measuring = false);
      // Real HRV readings take ~50s on-device (confirmed against the official QRing
      // app) — surface the actual error instead of failing silently so a timeout is
      // distinguishable from e.g. a disconnect.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('HRV measurement failed: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  Future<void> _saveSingleMeasurement(int hrv) async {
    final user = SupabaseService.currentUser;
    // Two-way sync: send the just-measured HRV sample to Health Connect.
    unawaited(HealthConnectService.instance.tryWriteHrv(hrv, DateTime.now()));
    if (user == null) return;
    try {
      final existing = await SupabaseService.getHrvForDate(
        user.id,
        DateTime.now(),
      );
      int newAvg, newMin, newMax, newCount;
      final prevCount = (existing?['sample_count'] as num? ?? 0).toInt();
      if (existing != null && prevCount > 0) {
        final prevAvg = (existing['avg_hrv'] as num).toInt();
        final prevMin = (existing['min_hrv'] as num).toInt();
        final prevMax = (existing['max_hrv'] as num).toInt();
        newCount = prevCount + 1;
        newAvg = ((prevAvg * prevCount + hrv) / newCount).round();
        newMin = hrv < prevMin ? hrv : prevMin;
        newMax = hrv > prevMax ? hrv : prevMax;
      } else {
        newAvg = newMin = newMax = hrv;
        newCount = 1;
      }
      await SupabaseService.upsertHrv(
        userId: user.id,
        date: DateTime.now(),
        avgHrv: newAvg,
        minHrv: newMin,
        maxHrv: newMax,
        sampleCount: newCount,
      );
      if (mounted) {
        context.read<BleProvider>().updateHrvLatest(newAvg);
        setState(() {
          _avgHrv = newAvg;
          _minHrv = newMin;
          _maxHrv = newMax;
        });
      }
    } catch (_) {}
  }

  // ── Local-first day / trend (cloud fills gaps + caches for offline) ────────

  Future<void> _loadDayFromSupabase(DateTime date) async {
    setState(() {
      _loadingDay = true;
      _dayOffline = false;
    });
    try {
      final local = await _local.getDaySummary('hrv', date);
      final list = await _local.getReadings('hrv', date);
      const totalSlots = 48;
      final slots = List<int>.filled(totalSlots, 0);
      final slotSums = List<int>.filled(totalSlots, 0);
      final slotCounts = List<int>.filled(totalSlots, 0);
      for (final m in list) {
        final value = (m['valueMs'] as num? ?? 0).toInt();
        final measuredAt = (m['measuredAt'] as num? ?? 0).toInt();
        if (value <= 0 || measuredAt <= 0) continue;
        final dt = DateTime.fromMillisecondsSinceEpoch(measuredAt);
        final slot = (dt.hour * 60 + dt.minute) ~/ 30;
        if (slot >= 0 && slot < totalSlots) {
          slotSums[slot] += value;
          slotCounts[slot] += 1;
        }
      }
      for (int i = 0; i < totalSlots; i++) {
        if (slotCounts[i] > 0) slots[i] = (slotSums[i] / slotCounts[i]).round();
      }

      if (!mounted) return;
      if (_local.hasData(local)) {
        setState(() {
          _dayAvg = (local['avg'] as num?)?.round() ?? 0;
          _dayMin = (local['min'] as num?)?.toInt() ?? 0;
          _dayMax = (local['max'] as num?)?.toInt() ?? 0;
          if (_selectedDate == date) _chartValues = slots;
        });
      } else if (slots.any((v) => v > 0) && _selectedDate == date) {
        setState(() => _chartValues = slots);
      }

      final user = SupabaseService.currentUser;
      if (user == null) return;
      try {
        final row = await SupabaseService.getHrvForDate(user.id, date);
        if (!mounted || row == null) return;
        final avg = (row['avg_hrv'] as num? ?? 0).toInt();
        final minV = (row['min_hrv'] as num? ?? 0).toInt();
        final maxV = (row['max_hrv'] as num? ?? 0).toInt();
        if (!_local.hasData(local) || avg > 0) {
          setState(() {
            if (avg > 0) _dayAvg = avg;
            if (minV > 0) _dayMin = minV;
            if (maxV > 0) _dayMax = maxV;
          });
        }
        await _local.cacheSimpleDay(
          vital: 'hrv',
          date: date,
          avg: avg,
          min: minV,
          max: maxV,
          count: (row['sample_count'] as num?)?.toInt() ?? 1,
        );
      } catch (e) {
        if (mounted && isNetworkError(e) && !_local.hasData(local)) {
          setState(() => _dayOffline = true);
        }
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'hrv_screen',
        error: e,
        stackTrace: st,
        customMessage: '_loadDayFromSupabase failed',
      );
    } finally {
      if (mounted) setState(() => _loadingDay = false);
    }
  }

  Future<void> _load7DayTrend() async {
    setState(() {
      _loadingTrend = true;
      _trendOffline = false;
    });
    try {
      final localRows = await _local.getHistory('hrv', days: 7);
      final localVals = await _local.historyAvgSeries('hrv', days: 7);
      final localValid = localRows.where((r) => r['min'] != null).toList();
      if (!mounted) return;
      if (localVals.any((v) => v > 0)) {
        setState(() {
          _trendValues = localVals;
          _trendMin = localValid.isEmpty
              ? 0
              : localValid
                  .map((r) => (r['min'] as num).toInt())
                  .reduce((a, b) => a < b ? a : b);
          _trendMax = localValid.isEmpty
              ? 0
              : localValid
                  .map((r) => (r['max'] as num).toInt())
                  .reduce((a, b) => a > b ? a : b);
        });
      }

      final user = SupabaseService.currentUser;
      if (user == null) return;
      try {
        final now = DateTime.now();
        final rows = await SupabaseService.getHrvHistory(
          userId: user.id,
          from: now.subtract(const Duration(days: 6)),
          to: now,
        );
        final vals = List.generate(7, (i) {
          final day = now.subtract(Duration(days: 6 - i));
          final row = rows.firstWhere(
            (r) => r['date'] == _fmt(day),
            orElse: () => {},
          );
          return (row['avg_hrv'] as num? ?? 0).toInt();
        });
        final valid = rows.where((r) => r['min_hrv'] != null).toList();
        if (!mounted) return;
        if (vals.any((v) => v > 0)) {
          setState(() {
            _trendValues = vals;
            _trendMin = valid.isEmpty
                ? 0
                : valid
                    .map((r) => (r['min_hrv'] as num).toInt())
                    .reduce((a, b) => a < b ? a : b);
            _trendMax = valid.isEmpty
                ? 0
                : valid
                    .map((r) => (r['max_hrv'] as num).toInt())
                    .reduce((a, b) => a > b ? a : b);
          });
        }
        for (final r in rows) {
          final dateStr = r['date'] as String?;
          if (dateStr == null) continue;
          final parts = dateStr.split('-');
          if (parts.length != 3) continue;
          final day = DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
          );
          await _local.cacheSimpleDay(
            vital: 'hrv',
            date: day,
            avg: r['avg_hrv'] as num?,
            min: r['min_hrv'] as num?,
            max: r['max_hrv'] as num?,
            count: (r['sample_count'] as num?)?.toInt() ?? 1,
          );
        }
      } catch (e) {
        if (mounted && isNetworkError(e) && !localVals.any((v) => v > 0)) {
          setState(() => _trendOffline = true);
        }
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'hrv_screen',
        error: e,
        stackTrace: st,
        customMessage: '_load7DayTrend failed',
      );
    } finally {
      if (mounted) setState(() => _loadingTrend = false);
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
          onTap: () => shareScreenshot(_screenshotKey, text: 'My HRV — SUNDR'),
        ),
        GlassMenuItem(
          label: 'Note',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const VitalNoteScreen(
                title: 'HRV',
                heading: 'About HRV',
                intro:
                    'Heart rate variability — the tiny variation in time '
                    'between heartbeats. Higher generally means your body '
                    'is more recovered and ready to handle stress.',
                ranges: [
                  VitalRange(
                    label: 'Very Low',
                    range: '0–19',
                    color: AppTheme.danger,
                  ),
                  VitalRange(
                    label: 'Low',
                    range: '20–39',
                    color: AppTheme.stressColor,
                  ),
                  VitalRange(
                    label: 'Moderate',
                    range: '40–59',
                    color: AppTheme.amber,
                  ),
                  VitalRange(
                    label: 'Good',
                    range: '60–79',
                    color: AppTheme.success,
                  ),
                  VitalRange(
                    label: 'Excellent',
                    range: '80+',
                    color: AppTheme.hrvColor,
                  ),
                ],
                tips: [
                  VitalTip(
                    icon: Icons.fitness_center_rounded,
                    color: AppTheme.hrvColor,
                    title: 'It\'s personal',
                    tip:
                        'HRV varies a lot person to person — track your '
                        'own trend over weeks rather than comparing to others.',
                  ),
                  VitalTip(
                    icon: Icons.local_bar_rounded,
                    color: AppTheme.stressColor,
                    title: 'Alcohol drops it fast',
                    tip:
                        'Alcohol, illness, and poor sleep are the most '
                        'common causes of a sudden overnight dip.',
                  ),
                ],
                didYouKnow:
                    'A rising HRV trend over time is one of the best signs '
                    'that training or lifestyle changes are working.',
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<String> _trendXLabels() {
    final now = DateTime.now();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return days[d.weekday - 1];
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;

    final displayAvg = _displayAvg;
    final displayMin = _displayMin;
    final displayMax = _displayMax;

    final hrvText = _loading
        ? '···'
        : displayAvg > 0
        ? '$displayAvg'
        : '--';

    final hasData = _hasRingData;
    final dailyRangeLabel = hasData
        ? '$displayMin - $displayMax ms'
        : '-- -- ms';

    final trendRangeLabel = _trendMin > 0 && _trendMax > 0
        ? '$_trendMin - $_trendMax ms'
        : '-- -- ms';

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
          title: Text('HRV', style: _inter(17, weight: FontWeight.w600)),
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
        body: RefreshIndicator(
          color: AppTheme.hrvColor,
          backgroundColor: AppTheme.card,
          onRefresh: () async {
            await _fetchTodayFromLocalDb();
            await _load7DayTrend();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),

                // ── 1. Date row ────────────────────────────────────────────
                DateScrollRow(
                  selectedDate: _selectedDate,
                  onDateSelected: _onDateSelected,
                ),
                const SizedBox(height: 22),

                // ── 2. Current HRV value ───────────────────────────────────
                Text(
                  'CURRENT HRV',
                  style: _inter(
                    11,
                    weight: FontWeight.w600,
                    color: AppTheme.gold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hrvText,
                  style: _inter(52, weight: FontWeight.w300, height: 1.1),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('ms', style: _inter(13, color: AppTheme.textTertiary)),
                    const SizedBox(width: 10),
                    if (!_loading && displayAvg > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _hrvColor(displayAvg).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _hrvLabel(displayAvg),
                          style: _inter(
                            11,
                            weight: FontWeight.w600,
                            color: _hrvColor(displayAvg),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── 3. Daily chart ─────────────────────────────────────────
                MetricChartCard(
                  headerLabel: hasData
                      ? 'TODAY'
                      : (_isToday ? 'NO DATA YET' : _dateLabel()),
                  rangeLabel: dailyRangeLabel,
                  yLabels: const ['100', '80', '60', '40'],
                  loadingAccent: AppTheme.hrvColor,
                  barCount: _chartValues.length,
                  xLabels: const ['12am', '6am', '12pm', '6pm', ''],
                  loading: _loading || _loadingDay,
                  child: CustomPaint(
                    painter: MetricBarPainter(
                      values: _chartValues,
                      maxY: 100,
                      yLines: const [100, 80, 60, 40, 20],
                      colorFor: (v) => _hrvBarColor(v).withValues(alpha: 0.88),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
                if (_dayOffline && !_isToday) ...[
                  const SizedBox(height: 8),
                  const OfflineNotice(
                    message: 'Connect to WiFi to load this day\'s HRV',
                  ),
                ],
                const SizedBox(height: 10),

                // ── 4. Stats row ───────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: MetricStatCard(
                        label: 'AVERAGE',
                        value: displayAvg > 0 ? '$displayAvg' : '--',
                        unit: displayAvg > 0 ? 'ms' : '--',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MetricStatCard(
                        label: 'MINIMUM',
                        value: displayMin > 0 ? '$displayMin' : '--',
                        unit: displayMin > 0 ? 'ms' : '--',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MetricStatCard(
                        label: 'MAXIMUM',
                        value: displayMax > 0 ? '$displayMax' : '--',
                        unit: displayMax > 0 ? 'ms' : '--',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // ── 4b. Real-time measurement ───────────────────────────────
                RealTimeCard(
                  title: 'Real Time HRV',
                  value: _measuring ? '···' : _manualHrv > 0 ? '$_manualHrv' : '--',
                  unit: 'ms',
                  accent: AppTheme.hrvColor,
                  measuring: _measuring,
                  enabled: connected && !_measuring,
                  onTap: _startMeasurement,
                ),
                const SizedBox(height: 20),

                // ── 5. 7-day trend ─────────────────────────────────────────
                MetricChartCard(
                  headerLabel: 'LAST 7 DAYS TREND',
                  rangeLabel: trendRangeLabel,
                  yLabels: const ['100', '80', '60', '40'],
                  loadingAccent: AppTheme.hrvColor,
                  barCount: _trendValues.length,
                  xLabels: _trendXLabels(),
                  loading: _loadingTrend,
                  footer: const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      LegendDot(color: AppTheme.danger, label: 'Very Low'),
                      LegendDot(color: AppTheme.stressColor, label: 'Low'),
                      LegendDot(color: AppTheme.amber, label: 'Moderate'),
                      LegendDot(color: AppTheme.success, label: 'Good'),
                      LegendDot(color: AppTheme.hrvColor, label: 'Excellent'),
                    ],
                  ),
                  child: CustomPaint(
                    painter: MetricBarPainter(
                      values: _trendValues,
                      maxY: 100,
                      yLines: const [100, 80, 60, 40, 20],
                      colorFor: (v) => _hrvBarColor(v).withValues(alpha: 0.88),
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
                const SizedBox(height: 10),

                // ── 6. Slot readings (today only) ──────────────────────────
                if (hasData) ...[
                  const SizedBox(height: 10),
                  _slotReadingsList(_chartValues),
                ],

                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _dateLabel() {
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return '${months[_selectedDate.month - 1]} ${_selectedDate.day}';
  }

  Widget _slotReadingsList(List<int> values) {
    final entries = <(String, int)>[];
    for (int i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final minutes = i * 30;
      final dt = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        minutes ~/ 60,
        minutes % 60,
      );
      entries.add((_fmtTime(dt), values[i]));
    }
    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.div),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              'READINGS',
              style: _inter(
                10,
                weight: FontWeight.w600,
                color: AppTheme.textTertiary,
                letterSpacing: 0.7,
              ),
            ),
          ),
          ...entries.asMap().entries.map((e) {
            final time = e.value.$1;
            final v = e.value.$2;
            final color = _hrvColor(v);
            final label = _hrvLabel(v);
            final isLast = e.key == entries.length - 1;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.monitor_heart_rounded,
                          color: color,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              time,
                              style: _inter(14, weight: FontWeight.w600),
                            ),
                            Text(label, style: _inter(11, color: color)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$v',
                            style: _inter(22, weight: FontWeight.w700),
                          ),
                          Text('ms', style: _inter(10, color: AppTheme.textTertiary)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  const Divider(color: AppTheme.div, height: 0.5, indent: 66),
              ],
            );
          }),
        ],
      ),
    );
  }
}


// ── HRV bar color ─────────────────────────────────────────────────────────────

Color _hrvBarColor(num v) {
  if (v < 20) return AppTheme.danger;
  if (v < 40) return AppTheme.stressColor;
  if (v < 60) return AppTheme.amber;
  if (v < 80) return AppTheme.success;
  return AppTheme.hrvColor;
}
