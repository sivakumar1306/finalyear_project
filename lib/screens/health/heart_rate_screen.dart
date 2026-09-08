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
import '../../services/health_engine/models.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/date_scroll_row.dart';
import '../../widgets/chart_scrubber.dart';
import '../../utils/date_keys.dart';
import '../../utils/formatters.dart';
import '../../widgets/metric_stat_card.dart';
import '../../widgets/not_enough_data_card.dart';
import '../../utils/hourly_aggregator.dart';
import '../../utils/trend_math.dart';


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

  bool get _isToday => DateKeys.isToday(_selectedDate);

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

  String _fmt(DateTime d) => DateKeys.fmt(d);

  // ── Init ──────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fetchTodayFromLocalDb();
      _load7DayTrend();
      // QRing parity: sync interval and manual backlog immediately when viewing HR screen.
      _syncRingHrData();
    });
  }

  Future<void> _syncRingHrData() async {
    try {
      final ble = context.read<BleProvider>();
      if (!ble.isConnected) return;
      // Pull autonomous 24h interval points from ring into Room
      await _ble.syncIntervalHeartRateDetail().timeout(const Duration(seconds: 15));
      // Also pull manual measurement list from ring
      await _tryManualListFallback();
      if (!mounted) return;
      await _fetchTodayFromLocalDb();
    } catch (_) {
      // Non-blocking sync attempt
    }
  }





  // ── Date selection ────────────────────────────────────────────────────────────

  void _onDateSelected(DateTime date) {
    final isToday = DateKeys.isToday(date);
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

  Future<void> _fetchTodayFromLocalDb({bool resetManual = false}) async {
    if (resetManual) {
      setState(() {
        _manualHr = 0;
      });
    }
    try {
      final now = DateTime.now();
      final dayStart = DateKeys.dayStartMs(now);
      final dayEnd = DateKeys.dayEndMs(now);

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
        final typedForHourly = list.whereType<Map<String, dynamic>>().toList();
        final aggHourly = HourlyAggregator.aggregateInt(typedForHourly, valueKey: 'valueBpm', measuredAtKey: 'measuredAt', slots: 24);
        for (int h = 0; h < 24; h++) {
          hourly[h] = aggHourly[h];
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
        if (avg > 0) _avgHr = avg;
        if (minVal > 0) _minHr = minVal;
        if (maxVal > 0) _maxHr = maxVal;
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
      Map<String, dynamic>? row;
      final user = SupabaseService.currentUser;
      if (user != null) {
        try {
          row = await SupabaseService.getHrForDate(user.id, date);
          if (!mounted) return;
          if (row != null) {
            final avg = (row['avg_hr'] as num? ?? 0).toInt();
            final minV = (row['min_hr'] as num? ?? 0).toInt();
            final maxV = (row['max_hr'] as num? ?? 0).toInt();
            final count = (row['sample_count'] as num? ?? 1).toInt();
            if (!_local.hasData(local) && _selectedDate == date) {
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
          }
        } catch (e) {
          if (mounted && isNetworkError(e) && !_local.hasData(local)) {
            setState(() => _dayOffline = true);
          }
        }
      }

      if (!_local.hasData(local) && (row == null || row.isEmpty) && !hourly.any((v) => v > 0) && _selectedDate == date) {
        setState(() {
          _dayAvg = 0;
          _dayMin = 0;
          _dayMax = 0;
          _chartValues = [];
        });
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
    return HourlyAggregator.aggregateInt(list, valueKey: 'valueBpm', measuredAtKey: 'measuredAt', slots: 24);
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
      if (!mounted) return;
      if (localVals.any((v) => v > 0)) {
        final mm = TrendMath.minMax(localRows, 'min', 'max');
        setState(() {
          _trendValues = localVals;
          _trendMin = mm.min;
          _trendMax = mm.max;
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
        if (!mounted) return;
        final hasLocalTrend = localVals.any((v) => v > 0);
        if (!hasLocalTrend && vals.any((v) => v > 0)) {
          final mm2 = TrendMath.minMax(rows, 'min_hr', 'max_hr');
          setState(() {
            _trendValues = vals;
            _trendMin = mm2.min;
            _trendMax = mm2.max;
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
    bool isConnected = false;
    try {
      isConnected = context.read<BleProvider>().isConnected;
    } catch (_) {}
    if (!isConnected) {
      IncidentService.reportUnhandled(
        source: 'heart_rate_screen',
        error: Exception('manual HR tapped while disconnected'),
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
      _manualHr = 0;
    });
    int? hr;
    String? streamError;
    try {
      hr = await _ble.readHeartRate();
    } catch (e) {
      streamError = e.toString();
    }
    // QRing parity fallback: live streaming can yield nothing on loose fit
    // while the ring still recorded a manual entry — pull the manual list.
    if ((hr == null || hr <= 0) && mounted) {
      try {
        hr = await _tryManualListFallback();
      } catch (e, st) {
        IncidentService.reportUnhandled(
          source: 'heart_rate_screen',
          error: e,
          stackTrace: st,
          customMessage: 'syncManualHeartRate fallback failed',
        );
      }
    }
    if (streamError != null && (hr == null || hr <= 0)) {
      // Streaming hard-failed and fallback found nothing — surface mapped error.
      if (!mounted) return;
      setState(() => _measuring = false);
      IncidentService.reportUnhandled(
        source: 'heart_rate_screen',
        error: Exception(streamError),
        customMessage: 'readHeartRate failed',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_measureErrorMessage(streamError)), backgroundColor: AppTheme.danger),
        );
      }
      return;
    }
    try {
      if (!mounted) return;
      const hrMin = 30, hrMax = 220;
      if (hr != null && hr >= hrMin && hr <= hrMax) {
        final bpm = hr;
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        // Show live value immediately (QRing-style: last > avg).
        setState(() {
          _manualHr = bpm;
          _latestHr = bpm;
          _latestHrAt = nowMs;
          _measuring = false;
        });
        try {
          context.read<BleProvider>().updateHrLatest(bpm, nowMs);
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
          await _ble.insertHeartRate(valueBpm: bpm, measuredAtMs: nowMs, source: 'manual');
        } catch (e, st) {
          IncidentService.reportUnhandled(
            source: 'heart_rate_screen',
            error: e,
            stackTrace: st,
            customMessage: 'insertHeartRate failed',
            extraInfo: {'hr': bpm, 'measuredAtMs': nowMs},
          );
        }
        // Recompute true daily aggregate from Room (not ~/2 blend).
        try {
          final summaryJson = await _ble.getTodaySummary('heart_rate');
          final summary = jsonDecode(summaryJson) as Map<String, dynamic>;
          final count = (summary['count'] as num?)?.toInt() ?? 0;
          final avg = (summary['avg'] as num?)?.round() ?? bpm;
          final minVal = (summary['min'] as num?)?.toInt() ?? bpm;
          final maxVal = (summary['max'] as num?)?.toInt() ?? bpm;
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
            extraInfo: {'hr': bpm},
          );
          // Fallback: at least update Supabase with single point.
          final fallbackMin = (_minHr > 0 && _minHr < bpm) ? _minHr : bpm;
          final fallbackMax = (_maxHr > bpm) ? _maxHr : bpm;
          await _saveHrToSupabase(bpm, fallbackMin, fallbackMax, 1);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_measureErrorMessage(e.toString())), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  String _measureErrorMessage(String raw) {
    if (raw.contains('BUSY')) {
      return 'Another measurement is in progress — wait and retry.';
    }
    if (raw.contains('TIMEOUT')) {
      return 'Heart rate measurement timed out — keep ring snug on your finger and retry.';
    }
    if (raw.contains('NOT_CONNECTED')) {
      return 'Ring not connected — reconnect and retry.';
    }
    if (raw.contains('SDK_GUARD_OPEN')) {
      return 'Sensor busy — wait a few seconds and retry.';
    }
    if (raw.contains('HR_ERR_')) {
      return 'Ring could not read heart rate — keep ring snug, stay still and retry.';
    }
    return 'Heart rate measurement failed: $raw';
  }

  /// Latest value from the ring-recorded manual HR entry.
  /// Returns null when empty/unparseable. Handles both the single-object
  /// shape {index,data:[{m,v}]} and the list shape [{index,data:[...]}].
  Future<int?> _tryManualListFallback() async {
    final raw = await _ble.syncManualHeartRate();
    if (raw.isEmpty || raw == '[]' || raw == '{}') return null;
    final decoded = jsonDecode(raw);
    final entries = decoded is List
        ? decoded
        : (decoded is Map ? [decoded] : <dynamic>[]);
    int? best;
    for (final e in entries) {
      if (e is! Map) continue;
      final data = e['data'];
      if (data is! List) continue;
      for (final d in data) {
        if (d is! Map) continue;
        final v = (d['v'] as num?)?.toInt() ?? 0;
        if (v >= 30 && v <= 220) best = v;
      }
    }
    return best;
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
              builder: (_) => VitalNoteScreen.fromMetric(HealthMetric.heartRate),
            ),
          ),
        ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  List<String> _trendXLabels() => DateKeys.trendXLabels();

  String _hourLabel(int hour) => Formatters.hourLabel(hour);

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

    final hasChartData = _chartValues.any((v) => v > 0);
    final hasData = hasChartData || displayLatest > 0 || _displayAvg > 0;

    final dailyRangeLabel = (_displayMin > 0 && _displayMax > 0)
        ? '$_displayMin - $_displayMax'
        : (displayLatest > 0 ? '$displayLatest BPM' : '-- --');

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

              // ── 4-6. Daily section — collapse to single glass card when empty
              if (!hasData && !_loading && !_dayOffline) ...[
                NotEnoughDataCard(
                  metric: 'heart rate',
                  date: _selectedDate,
                  isConnected: connected,
                  measuring: _measuring,
                  loading: _loadingDay,
                  onMeasure: _startMeasurement,
                  measureLabel: 'Measure heart rate',
                ),
              ] else ...[
                ScrubbableChart(
                  values: _chartValues,
                  maxY: 120,
                  yLines: const [120, 100, 80, 60],
                  barColor: AppTheme.hrColor.withValues(alpha: 0.88),
                  accent: AppTheme.hrColor,
                  headerLabel: hasChartData ? 'TODAY' : 'NO DATA YET',
                  rangeLabel: dailyRangeLabel,
                  yLabels: const ['120', '100', '80', '60'],
                  xLabels: const ['12am', '6am', '12pm', '6pm', ''],
                  barCount: _chartValues.length,
                  loading: _loading || _loadingDay,
                  loadingAccent: AppTheme.hrColor,
                  valueLabelBuilder: (i, v) => '${_hourLabel(i)} • $v bpm',
                ),
                if (_dayOffline && !_isToday) ...[
                  const SizedBox(height: 8),
                  const OfflineNotice(
                    message: 'Connect to WiFi to load this day\'s heart rate',
                  ),
                ],
                const SizedBox(height: 10),
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
                RealTimeCard(
                  title: 'Real Time Heart Rate',
                  value: _measuring ? '···' : _manualHr > 0 ? '$_manualHr' : '--',
                  unit: 'BPM',
                  accent: AppTheme.hrColor,
                  measuring: _measuring,
                  enabled: connected && !_measuring,
                  onTap: _startMeasurement,
                ),
              ],
              const SizedBox(height: 20),

              // ── 7. 7-day trend — also collapse when empty (2+ days required)
              if (!TrendMath.hasEnoughTrendData(_trendValues) && !_loadingTrend && !_trendOffline)
                const NotEnoughTrendDataCard(metric: 'heart rate')
              else ...[
                ScrubbableChart(
                  values: _trendValues,
                  maxY: 120,
                  yLines: const [120, 100, 80, 60],
                  barColor: AppTheme.hrColor.withValues(alpha: 0.88),
                  accent: AppTheme.hrColor,
                  headerLabel: 'LAST 7 DAYS TREND',
                  rangeLabel: trendRangeLabel,
                  yLabels: const ['120', '100', '80', '60'],
                  xLabels: _trendXLabels(),
                  barCount: _trendValues.length,
                  loading: _loadingTrend,
                  loadingAccent: AppTheme.hrColor,
                ),
                if (_trendOffline) ...[
                  const SizedBox(height: 8),
                  const OfflineNotice(
                    message: 'Connect to WiFi to load your 7-day trend',
                  ),
                ],
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
