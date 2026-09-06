import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/incident_service.dart';
import '../../services/local_vitals_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_menu.dart';
import '../../widgets/offline_notice.dart';
import '../../widgets/screenshot_share.dart';
import 'vital_note_screen.dart';
import '../../services/health_engine/health_engine.dart';
import '../../services/health_engine/models.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/date_scroll_row.dart';
import '../../widgets/legend_dot.dart';
import '../../widgets/chart_scrubber.dart';
import '../../utils/date_keys.dart';
import '../../utils/formatters.dart';
import '../../widgets/metric_stat_card.dart';
import '../../widgets/not_enough_data_card.dart';
import '../../utils/hourly_aggregator.dart';


// ── Local design tokens ───────────────────────────────────────────────────────

const _kBorder = AppTheme.div;
const _kSec = Color(0xFF666666);
const _kSec2 = AppTheme.textSec;

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

class StressScreen extends StatefulWidget {
  const StressScreen({super.key});
  @override
  State<StressScreen> createState() => _StressScreenState();
}

// Kept for backward compat — `/pressure` route still works.
typedef PressureScreen = StressScreen;

class _StressScreenState extends State<StressScreen> {
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

  int _manualStress = 0;

  // Today's ring data (in-memory)
  List<int> _chartValues = [];
  int _avgStress = 0, _minStress = 0, _maxStress = 0;

  // Past-day Supabase stats
  int _dayAvg = 0, _dayMin = 0, _dayMax = 0;

  // 7-day trend
  List<int> _trendValues = [];
  int _trendMin = 0, _trendMax = 0;

  // ── Computed ──────────────────────────────────────────────────────────────

  bool get _isToday => DateKeys.isToday(_selectedDate);

  int get _displayAvg {
    if (!_isToday) return _dayAvg;
    if (_avgStress > 0) return _avgStress;
    try { return context.read<BleProvider>().todayAvgStress; } catch(_) { return 0; }
  }

  int get _displayMin {
    if (!_isToday) return _dayMin;
    if (_minStress > 0) return _minStress;
    try { return context.read<BleProvider>().todayMinStress; } catch(_) { return 0; }
  }

  int get _displayMax {
    if (!_isToday) return _dayMax;
    if (_maxStress > 0) return _maxStress;
    try { return context.read<BleProvider>().todayMaxStress; } catch(_) { return 0; }
  }

  String _fmt(DateTime d) => DateKeys.fmt(d);

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
    final isToday = DateKeys.isToday(date);
    setState(() {
      _selectedDate = date;
      _manualStress = 0;
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
      _manualStress = 0;
    });
    try {
      final now = DateTime.now();
      final dayStart = DateKeys.dayStartMs(now);
      final dayEnd = DateKeys.dayEndMs(now);

      final summary =
          jsonDecode(await _ble.getTodaySummary('stress'))
              as Map<String, dynamic>;

      final hourly = List<int>.filled(24, 0);
      try {
        final readingsJson = await _ble.getReadings(
          'stress',
          fromMs: dayStart,
          toMs: dayEnd,
          limit: 1000,
        );
        final decoded = jsonDecode(readingsJson);
        final list = decoded is List ? decoded : <dynamic>[];
        final typedStress = list.whereType<Map<String, dynamic>>().toList();
        final aggStress = HourlyAggregator.aggregateInt(typedStress, valueKey: 'value', measuredAtKey: 'measuredAt', slots: 24);
        for (int h = 0; h < 24; h++) {
          hourly[h] = aggStress[h];
        }
      } catch (e, st) {
        IncidentService.reportUnhandled(
          source: 'stress_screen',
          error: e,
          stackTrace: st,
          customMessage: 'build daily chart slots failed',
        );
      }

      if (!mounted) return;
      final avg = (summary['avg'] as num?)?.round() ?? 0;
      final minVal = (summary['min'] as num?)?.toInt() ?? 0;
      final maxVal = (summary['max'] as num?)?.toInt() ?? 0;
      if (!hourly.any((v) => v > 0) && mounted) {
        final ble = context.read<BleProvider>();
        final liveVal = ble.todayAvgStress > 0 ? ble.todayAvgStress : ble.latestStressValue;
        if (liveVal > 0) {
          hourly[now.hour] = liveVal;
        }
      }
      setState(() {
        _chartValues = hourly;
        _avgStress = avg > 0 ? avg : (hourly.any((v) => v > 0) ? hourly[now.hour] : 0);
        _minStress = minVal;
        _maxStress = maxVal;
        _selectedDate = DateTime.now();
      });
      if (avg > 0 && mounted) {
        context.read<BleProvider>().updateStressLatest(avg);
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'stress_screen',
        error: e,
        stackTrace: st,
        customMessage: '_loadToday failed',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Local-first day / trend (cloud fills gaps + caches for offline) ────────

  Future<void> _loadDayFromSupabase(DateTime date) async {
    setState(() {
      _loadingDay = true;
      _dayOffline = false;
    });
    try {
      // 1) Local Room first — works offline and across month boundaries.
      final local = await _local.getDaySummary('stress', date);
      final localReadings = await _local.getReadings('stress', date);
      final hourly = HourlyAggregator.aggregateInt(localReadings, valueKey: 'value', measuredAtKey: 'measuredAt', slots: 24);
      if (!mounted) return;
      if (_local.hasData(local)) {
        setState(() {
          _dayAvg = (local['avg'] as num?)?.round() ?? 0;
          _dayMin = (local['min'] as num?)?.toInt() ?? 0;
          _dayMax = (local['max'] as num?)?.toInt() ?? 0;
          if (_selectedDate.year == date.year &&
              _selectedDate.month == date.month &&
              _selectedDate.day == date.day) {
            _chartValues = hourly;
          }
        });
      } else if (hourly.any((v) => v > 0) &&
          _selectedDate.year == date.year &&
          _selectedDate.month == date.month &&
          _selectedDate.day == date.day) {
        setState(() => _chartValues = hourly);
      }

      // 2) Cloud enrich + cache for next offline open.
      final user = SupabaseService.currentUser;
      if (user == null) return;
      try {
        final from = DateTime(date.year, date.month, date.day);
        final to = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
        final rows = await SupabaseService.getStressReadings(
          userId: user.id,
          from: from,
          to: to,
        );
        if (!mounted) return;
        final vals = rows
            .map((r) => (r['stress_value'] as num? ?? 0).toInt())
            .where((v) => v > 0)
            .toList();
        int avg = 0, minV = 0, maxV = 0;
        if (vals.isNotEmpty) {
          avg = (vals.reduce((a, b) => a + b) / vals.length).round();
          minV = vals.reduce((a, b) => a < b ? a : b);
          maxV = vals.reduce((a, b) => a > b ? a : b);
          if (!_local.hasData(local)) {
            setState(() {
              _dayAvg = avg;
              _dayMin = minV;
              _dayMax = maxV;
            });
          }
        }
        if (vals.isNotEmpty) {
          await _local.cacheSimpleDay(
            vital: 'stress',
            date: date,
            avg: avg,
            min: minV,
            max: maxV,
            count: vals.length,
          );
        }
      } catch (e) {
        if (mounted && isNetworkError(e) && !_local.hasData(local)) {
          setState(() => _dayOffline = true);
        }
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'stress_screen',
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
      // 1) Local rollups first.
      final localRows = await _local.getHistory('stress', days: 7);
      final localVals = await _local.historyAvgSeries('stress', days: 7);
      final localValid = localRows.where((r) => r['min'] != null).toList();
      if (!mounted) return;
      if (localVals.any((v) => v > 0)) {
        setState(() {
          _trendValues = localVals;
          _trendMin = localValid.isEmpty
              ? 0
              : localValid.map((r) => (r['min'] as num).toInt()).reduce((a, b) => a < b ? a : b);
          _trendMax = localValid.isEmpty
              ? 0
              : localValid.map((r) => (r['max'] as num).toInt()).reduce((a, b) => a > b ? a : b);
        });
      }

      final user = SupabaseService.currentUser;
      if (user == null) return;
      try {
        final now = DateTime.now();
        // Normalized midnight so Aug-31 Sep-1 month roll keeps full first day.
        final today = DateTime(now.year, now.month, now.day);
        final from = today.subtract(const Duration(days: 6));
        final toEnd = DateTime(today.year, today.month, today.day, 23, 59, 59, 999);
        final rows = await SupabaseService.getStressReadings(
          userId: user.id,
          from: from,
          to: toEnd,
        );
        final byDay = <String, List<int>>{};
        for (final r in rows) {
          final dt = DateTime.parse(r['measured_at'] as String).toLocal();
          final v = (r['stress_value'] as num? ?? 0).toInt();
          if (v > 0) byDay.putIfAbsent(_fmt(dt), () => []).add(v);
        }
        final vals = List.generate(7, (i) {
          final day = today.subtract(Duration(days: 6 - i));
          final dayVals = byDay[_fmt(day)];
          if (dayVals == null || dayVals.isEmpty) return 0;
          return (dayVals.reduce((a, b) => a + b) / dayVals.length).round();
        });
        final valid = vals.where((v) => v > 0).toList();
        if (!mounted) return;
        final hasLocalTrend = localVals.any((v) => v > 0);
        if (!hasLocalTrend && vals.any((v) => v > 0)) {
          setState(() {
            _trendValues = vals;
            _trendMin = valid.isEmpty ? 0 : valid.reduce((a, b) => a < b ? a : b);
            _trendMax = valid.isEmpty ? 0 : valid.reduce((a, b) => a > b ? a : b);
          });
        }
        // Cache each day for next offline open.
        for (int i = 0; i < 7; i++) {
          final day = today.subtract(Duration(days: 6 - i));
          final dayVals = byDay[_fmt(day)];
          if (dayVals == null || dayVals.isEmpty) continue;
          final avg = (dayVals.reduce((a, b) => a + b) / dayVals.length).round();
          final minV = dayVals.reduce((a, b) => a < b ? a : b);
          final maxV = dayVals.reduce((a, b) => a > b ? a : b);
          await _local.cacheSimpleDay(
            vital: 'stress',
            date: day,
            avg: avg,
            min: minV,
            max: maxV,
            count: dayVals.length,
          );
        }
      } catch (e) {
        if (mounted && isNetworkError(e) && !localVals.any((v) => v > 0)) {
          setState(() => _trendOffline = true);
        }
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'stress_screen',
        error: e,
        stackTrace: st,
        customMessage: '_load7DayTrend failed',
      );
    } finally {
      if (mounted) setState(() => _loadingTrend = false);
    }
  }

  // ── Manual measurement ────────────────────────────────────────────────────

  Future<void> _startMeasurement() async {
    if (_measuring) return;
    bool isConnected = false;
    try {
      isConnected = context.read<BleProvider>().isConnected;
    } catch (_) {}
    if (!isConnected) {
      IncidentService.reportUnhandled(
        source: 'stress_screen',
        error: Exception('manual pressure tapped while disconnected'),
        customMessage: 'Measurement tapped while ring not connected',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please connect your ring first'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
      return;
    }
    setState(() {
      _measuring = true;
      _manualStress = 0;
    });
    try {
      final result = await _ble.manualModePressure(start: true);
      if (!mounted) return;
      int v = 0;
      try {
        final m = jsonDecode(result) as Map<String, dynamic>;
        v = (m['value'] as num? ?? 0).toInt();
      } catch (e, st) {
        IncidentService.reportUnhandled(
          source: 'stress_screen',
          error: e,
          stackTrace: st,
          customMessage: 'parse manual pressure result failed',
          extraInfo: {'rawResult': result},
        );
      }
      setState(() => _measuring = false);
      if (v > 0) {
        setState(() => _manualStress = v);
        await _saveMeasurement(v);
      } else {
        IncidentService.reportUnhandled(
          source: 'stress_screen',
          error: Exception('manual pressure returned no valid value'),
          customMessage: 'manual pressure measurement returned 0',
          extraInfo: {'rawResult': result},
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Stress measurement returned no data — keep ring snug and retry. Raw: $result'),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'stress_screen',
        error: e,
        stackTrace: st,
        customMessage: 'manual pressure measurement failed',
      );
      if (mounted) {
        setState(() => _measuring = false);
        final msg = e.toString().contains('BUSY')
            ? 'Another measurement is in progress — wait and retry.'
            : e.toString().contains('TIMEOUT')
                ? 'Stress measurement timed out — keep ring on finger.'
                : 'Stress measurement failed: $e';
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
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'stress_screen',
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
          onTap: () =>
              shareScreenshot(_screenshotKey, text: 'My Stress — SUNDR'),
        ),
        GlassMenuItem(
          label: 'Note',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VitalNoteScreen.fromMetric(HealthMetric.stress),
            ),
          ),
        ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<String> _trendXLabels() => DateKeys.trendXLabels();

  String _hourLabel(int hour) => Formatters.hourLabel(hour);

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;

    final currentValue = _measuring
        ? '···'
        : _manualStress > 0
        ? '$_manualStress'
        : _displayAvg > 0
        ? '$_displayAvg'
        : '--';

    final currentLabel = _measuring
        ? 'Measuring…'
        : (HealthEngine.instance.assessStress(_manualStress > 0 ? _manualStress : _displayAvg).label == '--' ? '' : HealthEngine.instance.assessStress(_manualStress > 0 ? _manualStress : _displayAvg).label);

    final currentLabelColor = (() {
      final a = HealthEngine.instance.assessStress(_manualStress > 0 ? _manualStress : _displayAvg);
      return a.severity == HealthSeverity.unknown ? _kSec2 : a.color;
    })();

    final hasData = _chartValues.any((v) => v > 0);

    final trendRangeLabel = _trendMin > 0 && _trendMax > 0
        ? '$_trendMin - $_trendMax'
        : '-- --';

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
          title: Text('Stress', style: _inter(17, weight: FontWeight.w600)),
          actions: [
            IconButton(
              key: _moreButtonKey,
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onPressed: _openMenu,
            ),
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

              // ── 2. Date row ────────────────────────────────────────────────
              DateScrollRow(
                selectedDate: _selectedDate,
                onDateSelected: _onDateSelected,
              ),
              const SizedBox(height: 22),

              // ── 3. Current stress value ────────────────────────────────────
              Text(
                'CURRENT STRESS LEVEL',
                style: _inter(
                  11,
                  weight: FontWeight.w600,
                  color: AppTheme.gold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                currentValue,
                style: _inter(
                  52,
                  weight: FontWeight.w300,
                  color: Colors.white,
                  height: 1.1,
                ),
              ),
              Text(currentLabel, style: _inter(13, color: currentLabelColor)),
              const SizedBox(height: 16),

              // ── 4. Daily chart ─────────────────────────────────────────────
              if (!hasData && !_loading && !_loadingDay && !_dayOffline) ...[
                NotEnoughDataCard(
                  metric: 'stress',
                  date: _selectedDate,
                  isConnected: connected,
                  onMeasure: _startMeasurement,
                  measureLabel: 'Measure stress',
                ),
              ] else ...[
                ScrubbableChart(
                  values: _chartValues,
                  maxY: 100,
                  yLines: const [100, 75, 50, 25],
                  colorFor: (v) => HealthEngine.instance.stressBarColor(v).withValues(alpha: 0.88),
                  accent: AppTheme.stressColor,
                  headerLabel: hasData ? 'TODAY' : 'NO DATA YET',
                  rangeLabel: hasData ? '$_displayMin - $_displayMax' : '-- --',
                  yLabels: const ['100', '75', '50', '25'],
                  xLabels: const ['12am', '6am', '12pm', '6pm'],
                  barCount: _chartValues.length,
                  loading: _loading || _loadingDay,
                  loadingAccent: AppTheme.stressColor,
                  valueLabelBuilder: (i, v) => '${_hourLabel(i)} • $v',
                ),
                if (_dayOffline && !_isToday) ...[
                  const SizedBox(height: 8),
                  const OfflineNotice(
                    message: 'Connect to WiFi to load this day\'s stress',
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
                        unit: _displayAvg > 0 ? '/100' : '--',
                        caption: _displayAvg > 0 ? (HealthEngine.instance.assessStress(_displayAvg).label == '--' ? '' : HealthEngine.instance.assessStress(_displayAvg).label) : '--',
                        captionColor: (() { final a = HealthEngine.instance.assessStress(_displayAvg); return a.severity == HealthSeverity.unknown ? _kSec2 : a.color; })(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MetricStatCard(
                        label: 'MINIMUM',
                        value: _displayMin > 0 ? '$_displayMin' : '--',
                        unit: _displayMin > 0 ? '/100' : '--',
                        caption: _displayMin > 0 ? (HealthEngine.instance.assessStress(_displayMin).label == '--' ? '' : HealthEngine.instance.assessStress(_displayMin).label) : '--',
                        captionColor: (() { final a = HealthEngine.instance.assessStress(_displayMin); return a.severity == HealthSeverity.unknown ? _kSec2 : a.color; })(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MetricStatCard(
                        label: 'MAXIMUM',
                        value: _displayMax > 0 ? '$_displayMax' : '--',
                        unit: _displayMax > 0 ? '/100' : '--',
                        caption: _displayMax > 0 ? (HealthEngine.instance.assessStress(_displayMax).label == '--' ? '' : HealthEngine.instance.assessStress(_displayMax).label) : '--',
                        captionColor: (() { final a = HealthEngine.instance.assessStress(_displayMax); return a.severity == HealthSeverity.unknown ? _kSec2 : a.color; })(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // ── 6. Real-time measurement ───────────────────────────────────
                _StressMeasurementCard(
                  latestStress: _manualStress,
                  measuring: _measuring,
                  enabled: connected && !_measuring,
                  onTap: _startMeasurement,
                ),
              ],
              const SizedBox(height: 20),

              // ── 7. 7-day trend ─────────────────────────────────────────────
              if (_trendValues.every((v) => v == 0) && !_loadingTrend && !_trendOffline)
                const NotEnoughTrendDataCard(metric: 'stress')
              else ...[
                ScrubbableChart(
                  values: _trendValues,
                  maxY: 100,
                  yLines: const [100, 75, 50, 25],
                  colorFor: (v) => HealthEngine.instance.stressBarColor(v).withValues(alpha: 0.88),
                  accent: AppTheme.stressColor,
                  headerLabel: 'LAST 7 DAYS TREND',
                  rangeLabel: trendRangeLabel,
                  yLabels: const ['100', '75', '50', '25'],
                  xLabels: _trendXLabels(),
                  barCount: _trendValues.length,
                  loading: _loadingTrend,
                  loadingAccent: AppTheme.stressColor,
                  footer: const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      LegendDot(color: AppTheme.success, label: 'Relaxed'),
                      LegendDot(color: AppTheme.amber, label: 'Normal'),
                      LegendDot(color: AppTheme.stressColor, label: 'Elevated'),
                      LegendDot(color: AppTheme.danger, label: 'High'),
                    ],
                  ),
                ),
                if (_trendOffline) ...[
                  const SizedBox(height: 8),
                  const OfflineNotice(
                    message: 'Connect to WiFi to load your 7-day trend',
                  ),
                ],
              ],

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}


// ── Real-time measurement card ────────────────────────────────────────────────

class _StressMeasurementCard extends StatelessWidget {
  final int latestStress;
  final bool measuring;
  final bool enabled;
  final VoidCallback? onTap;

  const _StressMeasurementCard({
    required this.latestStress,
    required this.measuring,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final stressText = measuring
        ? '···'
        : latestStress > 0
        ? '$latestStress'
        : '--';

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.glassCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.glassBorder, width: 0.5),
          ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Real Time Stress',
                style: _inter(14, weight: FontWeight.w500),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    stressText,
                    style: _inter(
                      15,
                      weight: FontWeight.w600,
                      color: measuring || latestStress > 0
                          ? Colors.white
                          : _kSec2,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('/100', style: _inter(11, color: _kSec)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: measuring ? null : onTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2E2E2E)),
              ),
              child: Center(
                child: measuring
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: AppTheme.stressColor,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Click to start measurement',
                        style: _inter(
                          14,
                          weight: FontWeight.w500,
                          color: enabled ? Colors.white70 : _kSec,
                        ),
                      ),
              ),
            ),
          ),
        ],
          ),
        ),
      ),
    );
  }
}
