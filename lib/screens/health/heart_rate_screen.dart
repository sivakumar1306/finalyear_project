import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
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

class HeartRateScreen extends StatefulWidget {
  const HeartRateScreen({super.key});
  @override
  State<HeartRateScreen> createState() => _HeartRateScreenState();
}

class _HeartRateScreenState extends State<HeartRateScreen> {
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

  DateTime _selectedDate = DateTime.now();

  int _manualHr = 0;

  // Today's ring data
  List<int> _chartValues = [];
  int _avgHr = 0, _minHr = 0, _maxHr = 0;
  int _latestHr = 0;
  // ignore: unused_field
  int _latestHrAt = 0;

  // Past-day Supabase data
  int _dayAvg = 0, _dayMin = 0, _dayMax = 0;

  // 7-day trend (always loaded on open)
  List<int> _trendValues = [];
  int _trendMin = 0, _trendMax = 0;

  // ── Computed ──────────────────────────────────────────────────────────────────

  bool get _isToday {
    final n = DateTime.now();
    return _selectedDate.year == n.year &&
        _selectedDate.month == n.month &&
        _selectedDate.day == n.day;
  }

  int get _displayAvg {
    if (!_isToday) return _dayAvg;
    if (_avgHr > 0) return _avgHr;
    try { return context.watch<BleProvider>().todayAvgHr; } catch(_) { return 0; }
  }

  int get _displayMin {
    if (!_isToday) return _dayMin;
    if (_minHr > 0) return _minHr;
    try { return context.watch<BleProvider>().todayMinHr; } catch(_) { return 0; }
  }

  int get _displayMax {
    if (!_isToday) return _dayMax;
    if (_maxHr > 0) return _maxHr;
    try { return context.watch<BleProvider>().todayMaxHr; } catch(_) { return 0; }
  }

  int get _displayLatestLocal {
    if (!_isToday) return 0;
    if (_manualHr > 0) return _manualHr;
    if (_latestHr > 0) return _latestHr;
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
      _manualHr = 0;
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

  // ── Local DB fetch (today) ──────────────────────────────────────────────────

  Future<void> _fetchTodayFromLocalDb() async {
    setState(() {
      _manualHr = 0;
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

      final summaryJson = await _ble.getTodaySummary('heart_rate');
      final summary = jsonDecode(summaryJson) as Map<String, dynamic>;

      final hourly = List<int>.filled(24, 0);
      try {
        final readingsJson = await _ble.getReadings(
          'heart_rate',
          fromMs: dayStart,
          toMs: dayEnd,
          limit: 1000,
        );
        final decoded = jsonDecode(readingsJson);
        final list = decoded is List ? decoded : <dynamic>[];
        final sums = List<int>.filled(24, 0);
        final counts = List<int>.filled(24, 0);
        for (final item in list) {
          final m = item as Map<String, dynamic>;
          final bpm = (m['valueBpm'] as num? ?? 0).toInt();
          final measuredAt = (m['measuredAt'] as num? ?? 0).toInt();
          if (bpm <= 0 || measuredAt <= 0) continue;
          final h = DateTime.fromMillisecondsSinceEpoch(measuredAt).hour;
          sums[h] += bpm;
          counts[h] += 1;
        }
        for (int h = 0; h < 24; h++) {
          if (counts[h] > 0) hourly[h] = (sums[h] / counts[h]).round();
        }
      } catch (e, st) {
        IncidentService.reportUnhandled(
          source: 'heart_rate_screen',
          error: e,
          stackTrace: st,
          customMessage: 'build daily chart slots failed',
        );
      }

      if (!mounted) return;
      final avg = (summary['avg'] as num?)?.round() ?? 0;
      final minVal = (summary['min'] as num?)?.toInt() ?? 0;
      final maxVal = (summary['max'] as num?)?.toInt() ?? 0;
      final latest = (summary['lastValue'] as num?)?.toInt() ?? 0;
      final latestAt = (summary['lastMeasuredAt'] as num?)?.toInt() ?? 0;
      // Don't fabricate an hourly bucket from AVG — leave empty to surface sparsity (QRing style).
      setState(() {
        _chartValues = hourly;
        _avgHr = avg;
        _minHr = minVal;
        _maxHr = maxVal;
        if (latest > 0) {
          _latestHr = latest;
          _latestHrAt = latestAt;
        }
        _selectedDate = DateTime.now();
      });
      if (avg > 0 && mounted) {
        context.read<BleProvider>().updateHrData(avg, minVal, maxVal);
      }
      if (latest > 0 && mounted) {
        context.read<BleProvider>().updateHrLatest(latest, latestAt);
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'heart_rate_screen',
        error: e,
        stackTrace: st,
        customMessage: '_loadToday failed',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveHrToSupabase(int avg, int min, int max, int count) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.upsertHr(
        userId: user.id,
        date: DateTime.now(),
        avgHr: avg,
        minHr: min,
        maxHr: max,
        sampleCount: count,
      );
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'heart_rate_screen',
        error: e,
        stackTrace: st,
        customMessage: '_saveHrToSupabase failed',
      );
    }
  }

  // ── Local-first day / trend (cloud only fills gaps + refreshes cache) ──────

  Future<void> _loadDayFromSupabase(DateTime date) async {
    setState(() {
      _loadingDay = true;
      _dayOffline = false;
    });
    try {
      // 1) Local Room first — works offline.
      final local = await _local.getDaySummary('heart_rate', date);
      final localReadings = await _local.getReadings('heart_rate', date);
      final hourly = _hourlyFromHrReadings(localReadings);

      if (!mounted) return;
      if (_local.hasData(local)) {
        setState(() {
          _dayAvg = (local['avg'] as num?)?.round() ?? 0;
          _dayMin = (local['min'] as num?)?.toInt() ?? 0;
          _dayMax = (local['max'] as num?)?.toInt() ?? 0;
          if (_selectedDate == date) _chartValues = hourly;
        });
      } else if (hourly.any((v) => v > 0) && _selectedDate == date) {
        setState(() => _chartValues = hourly);
      }

      // 2) Optional cloud enrich + cache for next offline open.
      // QRing-style: local Room is authoritative for past days if present; cloud
      // is fallback for days never measured on this device. Never overwrite a
      // non-empty local display with cloud stale 87.
      final user = SupabaseService.currentUser;
      if (user == null) return;
      try {
        final row = await SupabaseService.getHrForDate(user.id, date);
        if (!mounted || row == null) return;
        final avg = (row['avg_hr'] as num? ?? 0).toInt();
        final minV = (row['min_hr'] as num? ?? 0).toInt();
        final maxV = (row['max_hr'] as num? ?? 0).toInt();
        final count = (row['sample_count'] as num? ?? 1).toInt();
        if (!_local.hasData(local)) {
          if (avg > 0 || minV > 0 || maxV > 0) {
            setState(() {
              if (avg > 0) _dayAvg = avg;
              if (minV > 0) _dayMin = minV;
              if (maxV > 0) _dayMax = maxV;
            });
          }
        }
        await _local.cacheSimpleDay(
          vital: 'heart_rate',
          date: date,
          avg: avg,
          min: minV,
          max: maxV,
          count: count,
        );
      } catch (e) {
        if (mounted && isNetworkError(e) && !_local.hasData(local)) {
          setState(() => _dayOffline = true);
        }
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'heart_rate_screen',
        error: e,
        stackTrace: st,
        customMessage: '_loadDayFromSupabase failed',
      );
    } finally {
      if (mounted) setState(() => _loadingDay = false);
    }
  }

  List<int> _hourlyFromHrReadings(List<Map<String, dynamic>> list) {
    final hourly = List<int>.filled(24, 0);
    final sums = List<int>.filled(24, 0);
    final counts = List<int>.filled(24, 0);
    for (final m in list) {
      final bpm = (m['valueBpm'] as num? ?? 0).toInt();
      final measuredAt = (m['measuredAt'] as num? ?? 0).toInt();
      if (bpm <= 0 || measuredAt <= 0) continue;
      final h = DateTime.fromMillisecondsSinceEpoch(measuredAt).hour;
      sums[h] += bpm;
      counts[h] += 1;
    }
    for (int h = 0; h < 24; h++) {
      if (counts[h] > 0) hourly[h] = (sums[h] / counts[h]).round();
    }
    return hourly;
  }

  Future<void> _load7DayTrend() async {
    setState(() {
      _loadingTrend = true;
      _trendOffline = false;
    });
    try {
      // 1) Local rollups first.
      final localRows = await _local.getHistory('heart_rate', days: 7);
      final localVals = await _local.historyAvgSeries('heart_rate', days: 7);
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

      // 2) Cloud refresh + write-through cache when online.
      // Only replace local trend when local is empty — preserves QRing-style
      // per-day interval fidelity and avoids stale cloud 87 overwriting fresh local.
      final user = SupabaseService.currentUser;
      if (user == null) return;
      try {
        final now = DateTime.now();
        final rows = await SupabaseService.getHrHistory(
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
          return (row['avg_hr'] as num? ?? 0).toInt();
        });
        final valid = rows.where((r) => r['min_hr'] != null).toList();
        if (!mounted) return;
        final hasLocalTrend = localVals.any((v) => v > 0);
        if (!hasLocalTrend && vals.any((v) => v > 0)) {
          setState(() {
            _trendValues = vals;
            _trendMin = valid.isEmpty
                ? 0
                : valid
                    .map((r) => (r['min_hr'] as num).toInt())
                    .reduce((a, b) => a < b ? a : b);
            _trendMax = valid.isEmpty
                ? 0
                : valid
                    .map((r) => (r['max_hr'] as num).toInt())
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
            vital: 'heart_rate',
            date: day,
            avg: r['avg_hr'] as num?,
            min: r['min_hr'] as num?,
            max: r['max_hr'] as num?,
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
        source: 'heart_rate_screen',
        error: e,
        stackTrace: st,
        customMessage: '_load7DayTrend failed',
      );
    } finally {
      if (mounted) setState(() => _loadingTrend = false);
    }
  }

  Future<void> _startMeasurement() async {
    if (_measuring) return;
    setState(() {
      _measuring = true;
      _manualHr = 0;
    });
    try {
      final hr = await _ble.readHeartRate();
      if (!mounted) return;
      const hrMin = 30, hrMax = 220;
      if (hr != null && hr >= hrMin && hr <= hrMax) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        // Show live value immediately (QRing-style: last > avg).
        setState(() {
          _manualHr = hr;
          _latestHr = hr;
          _latestHrAt = nowMs;
          _measuring = false;
        });
        try {
          context.read<BleProvider>().updateHrLatest(hr, nowMs);
        } catch (e, st) {
          IncidentService.reportUnhandled(
            source: 'heart_rate_screen',
            error: e,
            stackTrace: st,
            customMessage: 'updateHrLatest failed',
            extraInfo: {'hr': hr},
          );
        }
        // Persist to local Room so hourly chart + daily aggregate include it.
        try {
          await _ble.insertHeartRate(valueBpm: hr, measuredAtMs: nowMs, source: 'manual');
        } catch (e, st) {
          IncidentService.reportUnhandled(
            source: 'heart_rate_screen',
            error: e,
            stackTrace: st,
            customMessage: 'insertHeartRate failed',
            extraInfo: {'hr': hr, 'measuredAtMs': nowMs},
          );
        }
        // Recompute true daily aggregate from Room (not ~/2 blend).
        try {
          final summaryJson = await _ble.getTodaySummary('heart_rate');
          final summary = jsonDecode(summaryJson) as Map<String, dynamic>;
          final count = (summary['count'] as num?)?.toInt() ?? 0;
          final avg = (summary['avg'] as num?)?.round() ?? hr;
          final minVal = (summary['min'] as num?)?.toInt() ?? hr;
          final maxVal = (summary['max'] as num?)?.toInt() ?? hr;
          if (mounted) {
            setState(() {
              _avgHr = avg;
              _minHr = minVal;
              _maxHr = maxVal;
            });
            try {
              context.read<BleProvider>().updateHrData(avg, minVal, maxVal);
            } catch (e, st) {
              IncidentService.reportUnhandled(
                source: 'heart_rate_screen',
                error: e,
                stackTrace: st,
                customMessage: 'updateHrData failed',
              );
            }
          }
          await _saveHrToSupabase(avg, minVal, maxVal, count > 0 ? count : 1);
          // Refresh hourly chart to include the new point.
          await _fetchTodayFromLocalDb();
        } catch (e, st) {
          IncidentService.reportUnhandled(
            source: 'heart_rate_screen',
            error: e,
            stackTrace: st,
            customMessage: 'recompute daily aggregate failed',
            extraInfo: {'hr': hr},
          );
          // Fallback: at least update Supabase with single point.
          final fallbackMin = (_minHr > 0 && _minHr < hr) ? _minHr : hr;
          final fallbackMax = (_maxHr > hr) ? _maxHr : hr;
          await _saveHrToSupabase(hr, fallbackMin, fallbackMax, 1);
        }
      } else {
        IncidentService.reportUnhandled(
          source: 'heart_rate_screen',
          error: Exception('readHeartRate returned invalid bpm'),
          customMessage: 'heart rate measurement returned out-of-range or null',
          extraInfo: {'hr': hr},
        );
        if (!mounted) return;
        setState(() => _measuring = false);
        if (mounted) {
          final msg = hr == null
              ? 'Heart rate measurement returned no data — keep ring snug and retry.'
              : 'Heart rate $hr bpm out of range (30-220)';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: AppTheme.danger),
          );
        }
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'heart_rate_screen',
        error: e,
        stackTrace: st,
        customMessage: 'readHeartRate failed',
      );
      if (mounted) {
        setState(() => _measuring = false);
        final msg = e.toString().contains('BUSY')
            ? 'Another measurement is in progress — wait and retry.'
            : e.toString().contains('TIMEOUT')
                ? 'Heart rate measurement timed out — keep ring on finger.'
                : 'Heart rate measurement failed: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppTheme.danger),
        );
      }
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
          onTap: () =>
              shareScreenshot(_screenshotKey, text: 'My Heart Rate — SUNDR'),
        ),
        GlassMenuItem(
          label: 'Note',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const VitalNoteScreen(
                title: 'Heart Rate',
                heading: 'About Heart Rate',
                intro:
                    'Beats per minute, measured continuously by the ring\'s '
                    'optical sensor. Resting heart rate is one of the '
                    'clearest day-to-day fitness signals you have.',
                ranges: [
                  VitalRange(
                    label: 'Below normal',
                    range: '< 60 bpm',
                    color: AppTheme.hrvColor,
                  ),
                  VitalRange(
                    label: 'Normal',
                    range: '60–99 bpm',
                    color: AppTheme.success,
                  ),
                  VitalRange(
                    label: 'Above normal',
                    range: '100+ bpm',
                    color: AppTheme.danger,
                  ),
                ],
                tips: [
                  VitalTip(
                    icon: Icons.trending_down_rounded,
                    color: AppTheme.hrvColor,
                    title: 'Lower can be fine',
                    tip:
                        'A resting rate under 60 bpm is often a sign of '
                        'good cardiovascular fitness, not a problem.',
                  ),
                  VitalTip(
                    icon: Icons.show_chart_rounded,
                    color: AppTheme.hrColor,
                    title: 'Watch the trend',
                    tip:
                        'A resting rate that\'s creeping up week over week '
                        'is more meaningful than any single reading.',
                  ),
                ],
                didYouKnow:
                    'Caffeine, dehydration, and poor sleep can all push '
                    'your resting heart rate up temporarily.',
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
    final ble = context.watch<BleProvider>();
    final connected = ble.isConnected;

    // QRing-style hero: manual > latest (live) > avg fallback. Shows 65 even when avg is frozen 87.
    final localLatest = _displayLatestLocal;
    final providerLatest = ble.latestHr;
    final displayLatest = localLatest > 0 ? localLatest : providerLatest;
    final hrValue = _measuring
        ? '···'
        : displayLatest > 0
        ? '$displayLatest'
        : _displayAvg > 0
        ? '$_displayAvg'
        : '--';
    final isStale = !_measuring && displayLatest == 0 && _displayAvg > 0;

    final hasData = _chartValues.any((v) => v > 0);

    final dailyRangeLabel = hasData ? '$_displayMin - $_displayMax' : '-- --';

    final trendRangeLabel = _trendMin > 0 && _trendMax > 0
        ? '$_trendMin - $_trendMax BPM'
        : '-- -- BPM';

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
          title: Text('Heart Rate', style: _inter(17, weight: FontWeight.w600)),
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

              // ── 3. Current HR value ────────────────────────────────────────
              Text(
                'CURRENT HEART RATE',
                style: _inter(
                  11,
                  weight: FontWeight.w600,
                  color: AppTheme.gold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hrValue,
                style: _inter(
                  52,
                  weight: FontWeight.w300,
                  color: isStale ? Colors.white.withValues(alpha: 0.6) : Colors.white,
                  height: 1.1,
                ),
              ),
              Row(
                children: [
                  Text('bpm', style: _inter(13, color: AppTheme.textTertiary)),
                  if (isStale && _displayAvg > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Text('avg · no fresh reading', style: _inter(10, color: AppTheme.textTertiary)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              // ── 4. Daily chart ─────────────────────────────────────────────
              MetricChartCard(
                headerLabel: hasData ? 'TODAY' : 'NO DATA YET',
                rangeLabel: dailyRangeLabel,
                yLabels: const ['120', '100', '80', '60'],
                loadingAccent: AppTheme.hrColor,
                barCount: _chartValues.length,
                xLabels: const ['12am', '6am', '12pm', '6pm', ''],
                loading: _loading || _loadingDay,
                child: CustomPaint(
                  painter: MetricBarPainter(
                    values: _chartValues,
                    maxY: 120,
                    yLines: const [120, 100, 80, 60],
                    barColor: AppTheme.hrColor.withValues(alpha: 0.88),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              if (_dayOffline && !_isToday) ...[
                const SizedBox(height: 8),
                const OfflineNotice(
                  message: 'Connect to WiFi to load this day\'s heart rate',
                ),
              ],
              const SizedBox(height: 10),

              // ── 5. Stats row ───────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: MetricStatCard(
                      label: 'AVERAGE',
                      value: _displayAvg > 0 ? '$_displayAvg' : '--',
                      unit: _displayAvg > 0 ? 'bpm' : '--',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: MetricStatCard(
                      label: 'MINIMUM',
                      value: _displayMin > 0 ? '$_displayMin' : '--',
                      unit: _displayMin > 0 ? 'bpm' : '--',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: MetricStatCard(
                      label: 'MAXIMUM',
                      value: _displayMax > 0 ? '$_displayMax' : '--',
                      unit: _displayMax > 0 ? 'bpm' : '--',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // ── 6. Real-time measurement ───────────────────────────────────
RealTimeCard(
                title: 'Real Time Heart Rate',
                value: _measuring ? '···' : _manualHr > 0 ? '$_manualHr' : '--',
                unit: 'BPM',
                accent: AppTheme.hrColor,
                measuring: _measuring,
                enabled: connected && !_measuring,
                onTap: _startMeasurement,
              ),
              const SizedBox(height: 20),

              // ── 7. 7-day trend ─────────────────────────────────────────────
              MetricChartCard(
                headerLabel: 'LAST 7 DAYS TREND',
                rangeLabel: trendRangeLabel,
                yLabels: const ['120', '100', '80', '60'],
                loadingAccent: AppTheme.hrColor,
                barCount: _trendValues.length,
                xLabels: _trendXLabels(),
                loading: _loadingTrend,
                child: CustomPaint(
                  painter: MetricBarPainter(
                    values: _trendValues,
                    maxY: 120,
                    yLines: const [120, 100, 80, 60],
                    barColor: AppTheme.hrColor.withValues(alpha: 0.88),
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

              // ── 8. Sleep ───────────────────────────────────────────────────
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}
