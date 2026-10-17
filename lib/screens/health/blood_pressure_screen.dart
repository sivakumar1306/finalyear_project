import 'dart:async';
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
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/date_scroll_row.dart';
import '../../services/health_engine/health_engine.dart';
import '../../services/health_engine/models.dart';
import '../../widgets/legend_dot.dart';
import '../../widgets/chart_scrubber.dart';
import '../../widgets/glass_pill.dart';
import '../../utils/date_keys.dart';
import '../../widgets/metric_stat_card.dart';
import '../../widgets/not_enough_data_card.dart';
import '../../utils/hourly_aggregator.dart';
import '../../utils/trend_math.dart';
import 'measurement_log_screen.dart';


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

class BloodPressureScreen extends StatefulWidget {
  const BloodPressureScreen({super.key});
  @override
  State<BloodPressureScreen> createState() => _BloodPressureScreenState();
}

class _BloodPressureScreenState extends State<BloodPressureScreen> {
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

  bool get _isToday => DateKeys.isToday(_selectedDate);

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

  String _fmt(DateTime d) => DateKeys.fmt(d);

  // ── Init ──────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _fetchTodayFromLocalDb();
      _load7DayTrend();
      // Ring-buffer backfill (dayIndex 0..6) in the background.
      unawaited(_pullRingHistory());
    });
  }



  // ── Date selection ────────────────────────────────────────────────────────────

  /// Pulls the ring's full 7-day buffer (getBloodPressures 0..6) and inserts
  /// each reading, then quietly reloads the trend. Best-effort.
  Future<void> _pullRingHistory() async {
    try {
      if (!context.read<BleProvider>().isConnected) return;
      final raw = await _ble.fetchRingHistory('blood_pressure');
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) return;
      final user = SupabaseService.currentUser;
      if (user == null || !mounted) return;
      var wroteAny = false;
      for (final e in decoded) {
        if (e is! Map<String, dynamic>) continue;
        final dayIdx =
            (e['dayIndex'] as num? ?? e['day_index'] as num? ?? -1).toInt();
        if (dayIdx < 0 || dayIdx > 6) continue;
        final inner = e['data'];
        if (inner is! List) continue;
        for (final r in inner) {
          if (r is! Map<String, dynamic>) continue;
          final sbp = (r['sbp'] as num?)?.toInt() ?? 0;
          final dbp = (r['dbp'] as num?)?.toInt() ?? 0;
          if (sbp < 70 || sbp > 250 || dbp < 40 || dbp > 150) continue;
          final t = (r['time'] as num?)?.toInt() ?? 0;
          if (t <= 0) continue;
          // time may be seconds or millis — normalize by magnitude.
          final measuredAt = DateTime.fromMillisecondsSinceEpoch(
            t < 100000000000 ? t * 1000 : t,
          );
          await SupabaseService.insertBp(
            userId: user.id,
            systolic: sbp,
            diastolic: dbp,
            measuredAt: measuredAt,
            source: 'ring_history',
          );
          wroteAny = true;
          if (!mounted) return;
        }
      }
      if (wroteAny && mounted) await _load7DayTrend(quiet: true);
    } catch (_) {}
  }

  void _onDateSelected(DateTime date) {
    final isToday = DateKeys.isToday(date);
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
      final dayStart = DateKeys.dayStartMs(now);
      final dayEnd = DateKeys.dayEndMs(now);

      final summary =
          jsonDecode(await _ble.getTodaySummary('blood_pressure'))
              as Map<String, dynamic>;
      final count = (summary['count'] as num? ?? 0).toInt();

      var sbpHourly = List<int>.filled(24, 0);
      var dbpHourly = List<int>.filled(24, 0);
      if (count > 0) {
        final readingsJson = await _ble.getReadings(
          'blood_pressure',
          fromMs: dayStart,
          toMs: dayEnd,
          limit: 1000,
        );
        final decoded = jsonDecode(readingsJson);
        final list = decoded is List ? decoded : <dynamic>[];
        final typedBp = list.whereType<Map<String, dynamic>>().toList();
        final agg = HourlyAggregator.aggregateBp(typedBp);
        sbpHourly = agg.sbp;
        dbpHourly = agg.dbp;
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

  // ── Local-first day / trend (cloud fills gaps + caches for offline) ────────

  Future<void> _loadDayFromSupabase(DateTime date) async {
    setState(() {
      _loadingDay = true;
      _dayOffline = false;
    });
    try {
      // 1) Local Room first — works offline and across month boundaries.
      final local = await _local.getDaySummary('blood_pressure', date);
      final localReadings = await _local.getReadings('blood_pressure', date);
      final agg = HourlyAggregator.aggregateBp(localReadings);
      final sbpHourly = agg.sbp;
      final dbpHourly = agg.dbp;
      if (!mounted) return;
      // Local summary keys: avg/min/max for SBP, avgSecondary/minSecondary/maxSecondary for DBP
      // Fallback to legacy keys avgSbp etc if present.
      final hasLocal = _local.hasData(local);
      if (hasLocal) {
        final avgSbp = (local['avg'] as num? ?? local['avgSbp'] as num? ?? 0).toInt();
        final minSbp = (local['min'] as num? ?? local['minSbp'] as num? ?? 0).toInt();
        final maxSbp = (local['max'] as num? ?? local['maxSbp'] as num? ?? 0).toInt();
        final avgDbp = (local['avgSecondary'] as num? ?? local['avgDbp'] as num? ?? 0).toInt();
        final minDbp = (local['minSecondary'] as num? ?? local['minDbp'] as num? ?? 0).toInt();
        final maxDbp = (local['maxSecondary'] as num? ?? local['maxDbp'] as num? ?? 0).toInt();
        setState(() {
          if (avgSbp > 0) _daySbpAvg = avgSbp;
          if (minSbp > 0) _daySbpMin = minSbp;
          if (maxSbp > 0) _daySbpMax = maxSbp;
          if (avgDbp > 0) _dayDbpAvg = avgDbp;
          if (minDbp > 0) _dayDbpMin = minDbp;
          if (maxDbp > 0) _dayDbpMax = maxDbp;
          if (_selectedDate.year == date.year &&
              _selectedDate.month == date.month &&
              _selectedDate.day == date.day) {
            _chartSbp = sbpHourly;
            _chartDbp = dbpHourly;
          }
        });
      } else if ((sbpHourly.any((v) => v > 0) || dbpHourly.any((v) => v > 0)) &&
          _selectedDate.year == date.year &&
          _selectedDate.month == date.month &&
          _selectedDate.day == date.day) {
        setState(() {
          _chartSbp = sbpHourly;
          _chartDbp = dbpHourly;
        });
      }

      // 2) Cloud enrich + cache.
      List<int> sbps = [];
      List<int> dbps = [];
      final user = SupabaseService.currentUser;
      if (user != null) {
        try {
          final from = DateTime(date.year, date.month, date.day);
          final to = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
          final rows = await SupabaseService.getBpReadings(
            userId: user.id,
            from: from,
            to: to,
          );
          if (!mounted) return;
          sbps = rows.map((r) => (r['systolic'] as num? ?? 0).toInt()).where((v) => v > 0).toList();
          dbps = rows.map((r) => (r['diastolic'] as num? ?? 0).toInt()).where((v) => v > 0).toList();
          int avgSbp = 0, minSbp = 0, maxSbp = 0, avgDbp = 0, minDbp = 0, maxDbp = 0;
          if (sbps.isNotEmpty) {
            avgSbp = (sbps.reduce((a, b) => a + b) / sbps.length).round();
            minSbp = sbps.reduce((a, b) => a < b ? a : b);
            maxSbp = sbps.reduce((a, b) => a > b ? a : b);
          }
          if (dbps.isNotEmpty) {
            avgDbp = (dbps.reduce((a, b) => a + b) / dbps.length).round();
            minDbp = dbps.reduce((a, b) => a < b ? a : b);
            maxDbp = dbps.reduce((a, b) => a > b ? a : b);
          }
          if (!hasLocal && _selectedDate.year == date.year && _selectedDate.month == date.month && _selectedDate.day == date.day) {
            if (avgSbp > 0 || avgDbp > 0) {
              setState(() {
                if (avgSbp > 0) _daySbpAvg = avgSbp;
                if (minSbp > 0) _daySbpMin = minSbp;
                if (maxSbp > 0) _daySbpMax = maxSbp;
                if (avgDbp > 0) _dayDbpAvg = avgDbp;
                if (minDbp > 0) _dayDbpMin = minDbp;
                if (maxDbp > 0) _dayDbpMax = maxDbp;
              });
            }
          }
          if (sbps.isNotEmpty || dbps.isNotEmpty) {
            await _local.cacheBpDay(
              date: date,
              avgSbp: avgSbp,
              minSbp: minSbp,
              maxSbp: maxSbp,
              avgDbp: avgDbp,
              minDbp: minDbp,
              maxDbp: maxDbp,
              count: rows.length,
            );
          }
        } catch (e) {
          if (mounted && isNetworkError(e) && !_local.hasData(local)) {
            setState(() => _dayOffline = true);
          }
        }
      }

      if (!hasLocal && sbps.isEmpty && dbps.isEmpty && !(sbpHourly.any((v) => v > 0) || dbpHourly.any((v) => v > 0)) &&
          _selectedDate.year == date.year && _selectedDate.month == date.month && _selectedDate.day == date.day) {
        setState(() {
          _daySbpAvg = 0;
          _daySbpMin = 0;
          _daySbpMax = 0;
          _dayDbpAvg = 0;
          _dayDbpMin = 0;
          _dayDbpMax = 0;
          _chartSbp = [];
          _chartDbp = [];
        });
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'blood_pressure_screen',
        error: e,
        stackTrace: st,
        customMessage: '_loadDayFromSupabase failed',
      );
    } finally {
      if (mounted) setState(() => _loadingDay = false);
    }
  }

  Future<void> _load7DayTrend({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loadingTrend = true;
        _trendOffline = false;
      });
    }
    try {
      // 1) Local first.
      final localSbpVals = await _local.historyAvgSeries('blood_pressure', days: 7, avgKey: 'avg');
      final localDbpVals = await _local.historyAvgSeries('blood_pressure', days: 7, avgKey: 'avgSecondary');
      if (!mounted) return;
      final hasLocalSbp = localSbpVals.any((v) => v > 0);
      final hasLocalDbp = localDbpVals.any((v) => v > 0);
      if (hasLocalSbp || hasLocalDbp) {
        setState(() {
          _trendSbp = localSbpVals;
          _trendDbp = localDbpVals;
        });
      }

      final user = SupabaseService.currentUser;
      if (user == null) return;
      try {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final from = today.subtract(const Duration(days: 6));
        final toEnd = DateTime(today.year, today.month, today.day, 23, 59, 59, 999);
        final rows = await SupabaseService.getBpReadings(
          userId: user.id,
          from: from,
          to: toEnd,
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
          final day = today.subtract(Duration(days: 6 - i));
          final vals = byDaySbp[_fmt(day)];
          if (vals == null || vals.isEmpty) return 0;
          return (vals.reduce((a, b) => a + b) / vals.length).round();
        });
        final dbpVals = List.generate(7, (i) {
          final day = today.subtract(Duration(days: 6 - i));
          final vals = byDayDbp[_fmt(day)];
          if (vals == null || vals.isEmpty) return 0;
          return (vals.reduce((a, b) => a + b) / vals.length).round();
        });
        if (!mounted) return;
        final hasLocalTrend = hasLocalSbp || hasLocalDbp;
        if (!hasLocalTrend && (sbpVals.any((v) => v > 0) || dbpVals.any((v) => v > 0))) {
          setState(() {
            _trendSbp = sbpVals;
            _trendDbp = dbpVals;
          });
        }
        // Cache each day.
        for (int i = 0; i < 7; i++) {
          final day = today.subtract(Duration(days: 6 - i));
          final sbpDay = byDaySbp[_fmt(day)];
          final dbpDay = byDayDbp[_fmt(day)];
          if ((sbpDay == null || sbpDay.isEmpty) && (dbpDay == null || dbpDay.isEmpty)) continue;
          final avgSbp = sbpDay == null || sbpDay.isEmpty ? 0 : (sbpDay.reduce((a, b) => a + b) / sbpDay.length).round();
          final minSbp = sbpDay == null || sbpDay.isEmpty ? 0 : sbpDay.reduce((a, b) => a < b ? a : b);
          final maxSbp = sbpDay == null || sbpDay.isEmpty ? 0 : sbpDay.reduce((a, b) => a > b ? a : b);
          final avgDbp = dbpDay == null || dbpDay.isEmpty ? 0 : (dbpDay.reduce((a, b) => a + b) / dbpDay.length).round();
          final minDbp = dbpDay == null || dbpDay.isEmpty ? 0 : dbpDay.reduce((a, b) => a < b ? a : b);
          final maxDbp = dbpDay == null || dbpDay.isEmpty ? 0 : dbpDay.reduce((a, b) => a > b ? a : b);
          await _local.cacheBpDay(
            date: day,
            avgSbp: avgSbp,
            minSbp: minSbp,
            maxSbp: maxSbp,
            avgDbp: avgDbp,
            minDbp: minDbp,
            maxDbp: maxDbp,
            count: (sbpDay?.length ?? 0) + (dbpDay?.length ?? 0),
          );
        }
      } catch (e) {
        if (mounted && isNetworkError(e) && !localSbpVals.any((v) => v > 0) && !localDbpVals.any((v) => v > 0)) {
          setState(() => _trendOffline = true);
        }
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'blood_pressure_screen',
        error: e,
        stackTrace: st,
        customMessage: '_load7DayTrend failed',
      );
    } finally {
      if (mounted) setState(() => _loadingTrend = false);
    }
  }

  // ── Manual measurement ────────────────────────────────────────────────────────

  Future<void> _startMeasurement() async {
    if (_measuring) return;
    bool isConnected = false;
    try {
      isConnected = context.read<BleProvider>().isConnected;
    } catch (_) {}
    if (!isConnected) {
      IncidentService.reportUnhandled(
        source: 'blood_pressure_screen',
        error: Exception('manual BP tapped while disconnected'),
        customMessage: 'Measurement tapped while ring not connected',
      );
      if (mounted) {
        showGlassPill(context, 'Please connect your ring first', type: GlassPillType.error);
      }
      return;
    }
    setState(() {
      _measuring = true;
      _manualSbp = 0;
      _manualDbp = 0;
    });
    try {
      final result = await _ble.manualModeBP(start: true);
      int sbp = 0;
      int dbp = 0;
      try {
        final m = jsonDecode(result) as Map<String, dynamic>;
        sbp = (m['sbp'] as num? ?? 0).toInt();
        dbp = (m['dbp'] as num? ?? 0).toInt();
      } catch (e, st) {
        IncidentService.reportUnhandled(
          source: 'blood_pressure_screen',
          error: e,
          stackTrace: st,
          customMessage: 'parse manual BP result failed',
          extraInfo: {'rawResult': result},
        );
      }
      if (!mounted) return;
      setState(() => _measuring = false);
      if (sbp > 0 && dbp > 0) {
        setState(() {
          _manualSbp = sbp;
          _manualDbp = dbp;
        });
        await _saveMeasurement(sbp, dbp);
      } else {
        IncidentService.reportUnhandled(
          source: 'blood_pressure_screen',
          error: Exception('manual BP returned no valid values'),
          customMessage: 'manual BP measurement returned 0',
          extraInfo: {'rawResult': result, 'sbp': sbp, 'dbp': dbp},
        );
        if (mounted) {
          showGlassPill(context, 'Blood pressure measurement returned no data — keep ring snug and retry. Raw: $result', type: GlassPillType.error);
        }
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'blood_pressure_screen',
        error: e,
        stackTrace: st,
        customMessage: 'manual BP measurement failed',
      );
      if (mounted) {
        setState(() => _measuring = false);
        final msg = e.toString().contains('BUSY')
            ? 'Another measurement is in progress — wait and retry.'
            : e.toString().contains('TIMEOUT')
                ? 'Blood pressure measurement timed out — keep ring on finger.'
                : 'Blood pressure measurement failed: $e';
        showGlassPill(context, msg, type: GlassPillType.error);
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
            text: 'My Blood Pressure — Vital Monitoring',
          ),
        ),
        GlassMenuItem(
          label: 'Note',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VitalNoteScreen.fromMetric(HealthMetric.bloodPressure),
            ),
          ),
        ),
      ],
    );
  }

  // ── View All Readings ─────────────────────────────────────────────────────

  Widget _buildViewAllReadingsButton() {
    return GestureDetector(
      onTap: _openMeasurementLog,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.div),
        ),
        child: Row(
          children: [
            const Icon(Icons.list_alt_rounded, color: AppTheme.bpColor, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text('View All Readings', style: _inter(14, weight: FontWeight.w600)),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _openMeasurementLog() async {
    final entries = <MeasurementEntry>[];
    try {
      final dayStart = DateKeys.dayStartMs(_selectedDate);
      final dayEnd = DateKeys.dayEndMs(_selectedDate);
      final readingsJson = await _ble.getReadings(
        'blood_pressure',
        fromMs: dayStart,
        toMs: dayEnd,
        limit: 1000,
      );
      final decoded = jsonDecode(readingsJson);
      if (decoded is List && decoded.isNotEmpty) {
        for (final item in decoded.reversed) {
          if (item is! Map) continue;
          final m = Map<String, dynamic>.from(item);
          final sbp = (m['systolic'] as num? ?? m['valueSbp'] as num? ?? 0).toInt();
          final dbp = (m['diastolic'] as num? ?? m['valueDbp'] as num? ?? 0).toInt();
          final ms = (m['measuredAt'] as num?)?.toInt() ?? 0;
          if (sbp <= 0 || dbp <= 0 || ms <= 0) continue;
          final dt = DateTime.fromMillisecondsSinceEpoch(ms);
          final assessment = HealthEngine.instance.assessBloodPressure(sbp, dbp);
          entries.add(MeasurementEntry(
            time: dt,
            value: '$sbp/$dbp',
            unit: 'mmHg',
            label: assessment.label,
            color: assessment.color,
            icon: Icons.speed_rounded,
          ));
        }
      }
    } catch (_) {}

    if (entries.isEmpty) {
      final len = _chartSbp.length < _chartDbp.length ? _chartSbp.length : _chartDbp.length;
      for (int i = 0; i < len; i++) {
        if (_chartSbp[i] <= 0 && _chartDbp[i] <= 0) continue;
        final minutes = i * 30;
        final dt = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, minutes ~/ 60, minutes % 60);
        final sbp = _chartSbp[i];
        final dbp = _chartDbp[i];
        final assessment = HealthEngine.instance.assessBloodPressure(sbp, dbp);
        entries.add(MeasurementEntry(
          time: dt, value: '$sbp/$dbp', unit: 'mmHg',
          label: assessment.label, color: assessment.color,
          icon: Icons.speed_rounded,
        ));
      }
    }

    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => MeasurementLogScreen(
        title: 'Blood Pressure Readings', date: _selectedDate,
        entries: entries, accentColor: AppTheme.bpColor,
      ),
    ));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  List<String> _trendXLabels() => DateKeys.trendXLabels();

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
        : (HealthEngine.instance.assessBloodPressure(currentSbp, currentDbp).label == 'No data' ? '' : HealthEngine.instance.assessBloodPressure(currentSbp, currentDbp).label);
    final currentLabelColor = HealthEngine.instance.assessBloodPressure(currentSbp, currentDbp).color;

    final hasChartData = _chartSbp.any((v) => v > 0) || _chartDbp.any((v) => v > 0);
    final hasData = hasChartData || _displaySbpAvg > 0 || _manualSbp > 0;

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

              // ── 4-6. Daily section — collapse to single glass card when empty
              if (!hasData && !_loading && !_dayOffline) ...[
                NotEnoughDataCard(
                  metric: 'blood pressure',
                  date: _selectedDate,
                  isConnected: connected,
                  measuring: _measuring,
                  loading: _loadingDay,
                  onMeasure: _startMeasurement,
                  measureLabel: 'Measure blood pressure',
                ),
              ] else ...[
                ScrubbableBPChart(
                  sbpValues: _chartSbp,
                  dbpValues: _chartDbp,
                  headerLabel: hasData ? 'TODAY' : 'NO DATA YET',
                  rangeLabel: dailyRangeLabel,
                  yLabels: const ['160', '120', '80', '40'],
                  xLabels: const ['12am', '6am', '12pm', '6pm', ''],
                  barCount: _chartSbp.length,
                  loading: _loading || _loadingDay,
                  loadingAccent: AppTheme.bpColor,
                ),
                if (_dayOffline && !_isToday) ...[
                  const SizedBox(height: 8),
                  const OfflineNotice(
                    message: 'Connect to WiFi to load this day\'s blood pressure',
                  ),
                ],
                const SizedBox(height: 10),
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
                _RealTimeBPCard(
                  sbp: _manualSbp,
                  dbp: _manualDbp,
                  measuring: _measuring,
                  enabled: connected && !_measuring,
                  onTap: _startMeasurement,
                ),
              ],
              const SizedBox(height: 20),

              // ── View All Readings
              if (hasChartData) ...[
                _buildViewAllReadingsButton(),
                const SizedBox(height: 16),
              ],

              // ── 7. 7-day trend — also collapse when empty (2+ paired days)
              if (!TrendMath.hasEnoughBpTrendData(_trendSbp, _trendDbp) && !_loadingTrend && !_trendOffline)
                const NotEnoughTrendDataCard(metric: 'blood pressure')
              else ...[
                ScrubbableBPChart(
                  sbpValues: _trendSbp,
                  dbpValues: _trendDbp,
                  headerLabel: 'LAST 7 DAYS TREND',
                  rangeLabel: trendRangeLabel,
                  yLabels: const ['160', '120', '80', '40'],
                  xLabels: _trendXLabels(),
                  barCount: _trendSbp.length,
                  loading: _loadingTrend,
                  loadingAccent: AppTheme.bpColor,
                  footer: const Row(
                    children: [
                      LegendDot(color: AppTheme.bpColor, label: 'Systolic'),
                      SizedBox(width: 14),
                      LegendDot(color: AppTheme.softViolet, label: 'Diastolic'),
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

// ── BP Bar Painter ─────────────────────────────────────────────────────────────
// ignore: unused_element - kept for reference, superseded by _ScrubbableBPBarPainter in chart_scrubber.dart
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
            children: [
              Flexible(
                child: Text(
                  'Real Time Blood Pressure',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _inter(14, weight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
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
            behavior: HitTestBehavior.opaque,
            onTap: measuring ? null : onTap,
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
                          color: AppTheme.bpColor,
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
        ),
      ),
    );
  }
}

