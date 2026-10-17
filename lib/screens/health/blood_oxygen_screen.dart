import 'dart:async';
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
import '../../services/health_engine/models.dart';
import '../../services/health_engine/health_engine.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/date_scroll_row.dart';
import '../../widgets/chart_scrubber.dart';
import '../../widgets/glass_pill.dart';
import '../../utils/date_keys.dart';
import '../../utils/formatters.dart';
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

class BloodOxygenScreen extends StatefulWidget {
  const BloodOxygenScreen({super.key});
  @override
  State<BloodOxygenScreen> createState() => _BloodOxygenScreenState();
}

class _BloodOxygenScreenState extends State<BloodOxygenScreen> {
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

  int _manualSpo2 = 0;

  // Today's ring data
  List<int> _chartValues = [];
  int _avgSpo2 = 0, _minSpo2 = 0, _maxSpo2 = 0;
  int _latestSpo2 = 0;
  // ignore: unused_field
  int _latestSpo2At = 0;

  // Past-day Supabase data
  int _dayAvg = 0, _dayMin = 0, _dayMax = 0;

  // 7-day trend (always loaded on open)
  List<int> _trendValues = [];
  int _trendMin = 0, _trendMax = 0;

  // ── Computed ──────────────────────────────────────────────────────────────

  bool get _isToday => DateKeys.isToday(_selectedDate);

  int get _displayAvg {
    if (!_isToday) return _dayAvg;
    if (_avgSpo2 > 0) return _avgSpo2;
    try { return context.watch<BleProvider>().todayAvgSpo2; } catch(_) { return 0; }
  }

  int get _displayMin {
    if (!_isToday) return _dayMin;
    if (_minSpo2 > 0) return _minSpo2;
    try { return context.watch<BleProvider>().todayMinSpo2; } catch(_) { return 0; }
  }

  int get _displayMax {
    if (!_isToday) return _dayMax;
    if (_maxSpo2 > 0) return _maxSpo2;
    try { return context.watch<BleProvider>().todayMaxSpo2; } catch(_) { return 0; }
  }

  int get _displayLatestLocal {
    if (!_isToday) return 0;
    if (_manualSpo2 > 0) return _manualSpo2;
    if (_latestSpo2 > 0) return _latestSpo2;
    return 0;
  }

  String _fmt(DateTime d) => DateKeys.fmt(d);

  // ── Init ──────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _fetchToday();
      _load7DayTrend();
      // Ring-buffer backfill (dayIndex 0..6) in the background.
      unawaited(_pullRingHistory());
    });
  }



  // ── Date selection ────────────────────────────────────────────────────────

  void _onDateSelected(DateTime date) {
    final isToday = DateKeys.isToday(date);
    setState(() {
      _selectedDate = date;
      _manualSpo2 = 0;
      if (isToday) {
        _dayAvg = _dayMin = _dayMax = 0;
      }
    });
    if (!isToday) {
      _loadDayFromSupabase(date);
    } else {
      _fetchToday();
    }
  }

  // ── Local DB fetch (today) ───────────────────────────────────────────────

  /// Pulls the ring's full 7-day buffer (getBloodOxygens 0..6) and backfills
  /// Supabase via upsertSpo2, then quietly reloads the trend. Best-effort.
  Future<void> _pullRingHistory() async {
    try {
      if (!context.read<BleProvider>().isConnected) return;
      final raw = await _ble.fetchRingHistory('spo2');
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) return;
      final user = SupabaseService.currentUser;
      if (user == null || !mounted) return;
      final today = DateTime.now();
      var wroteAny = false;
      for (final e in decoded) {
        if (e is! Map<String, dynamic>) continue;
        final dayIdx =
            (e['dayIndex'] as num? ?? e['day_index'] as num? ?? -1).toInt();
        if (dayIdx < 0 || dayIdx > 6) continue;
        final inner = e['data'];
        if (inner is! Map<String, dynamic>) continue;
        final vals = <int>[];
        for (final key in ['array', 'minArray', 'maxArray']) {
          final arr = inner[key];
          if (arr is List) {
            vals.addAll(arr.whereType<num>().map((v) => v.toInt()));
          }
        }
        final clean = vals.where((v) => v > 0 && v <= 100).toList();
        if (clean.isEmpty) continue;
        clean.sort();
        final date = DateTime(today.year, today.month, today.day)
            .subtract(Duration(days: dayIdx));
        await SupabaseService.upsertSpo2(
          userId: user.id,
          date: date,
          avgSpo2: (clean.reduce((a, b) => a + b) / clean.length).round(),
          minSpo2: clean.first,
          maxSpo2: clean.last,
          sampleCount: clean.length,
        );
        wroteAny = true;
        if (!mounted) return;
      }
      if (wroteAny && mounted) await _load7DayTrend(quiet: true);
    } catch (_) {}
  }

  Future<void> _fetchToday() async {
    setState(() {
      _manualSpo2 = 0;
    });
    try {
      final now = DateTime.now();
      final dayStart = DateKeys.dayStartMs(now);
      final dayEnd = DateKeys.dayEndMs(now);

      final summary =
          jsonDecode(await _ble.getTodaySummary('spo2'))
              as Map<String, dynamic>;

      const totalSlots = 24;
      final slots = List<int>.filled(totalSlots, 0);

      try {
        final readingsJson = await _ble.getReadings(
          'spo2',
          fromMs: dayStart,
          toMs: dayEnd,
          limit: 1000,
        );
        final decoded = jsonDecode(readingsJson);
        final list = decoded is List ? decoded : <dynamic>[];
        final typedSpo2 = list.whereType<Map<String, dynamic>>().toList();
        final aggSpo2 = HourlyAggregator.aggregateInt(typedSpo2, valueKey: 'valuePct', measuredAtKey: 'measuredAt', slots: 24);
        for (int i = 0; i < totalSlots; i++) {
          slots[i] = aggSpo2[i];
        }
      } catch (e, st) {
        IncidentService.reportUnhandled(
          source: 'blood_oxygen_screen',
          error: e,
          stackTrace: st,
          customMessage: 'build daily chart slots failed',
        );
      }

      if (!mounted) return;
      final avg = (summary['avg'] as num?)?.round() ?? 0;
      final minVal = (summary['min'] as num? ?? 0).toInt();
      final maxVal = (summary['max'] as num? ?? 0).toInt();
      final latest = (summary['lastValue'] as num?)?.toInt() ?? 0;
      final latestAt = (summary['lastMeasuredAt'] as num?)?.toInt() ?? 0;
      setState(() {
        _chartValues = slots;
        _avgSpo2 = avg;
        _minSpo2 = minVal;
        _maxSpo2 = maxVal;
        if (latest > 0) {
          _latestSpo2 = latest;
          _latestSpo2At = latestAt;
        }
        _selectedDate = now;
      });
      if (avg > 0 && mounted) {
        context.read<BleProvider>().updateSpo2Data(avg, minVal, maxVal);
      }
      if (latest > 0 && mounted) {
        context.read<BleProvider>().updateSpo2Latest(latest, latestAt);
      }
    } catch (_) {
      // Local DB read failing isn't worth surfacing loudly — chart just stays blank.
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
      final local = await _local.getDaySummary('spo2', date);
      final list = await _local.getReadings('spo2', date);
      final slots = HourlyAggregator.aggregateInt(list, valueKey: 'valuePct', measuredAtKey: 'measuredAt', slots: 24);

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

      Map<String, dynamic>? row;
      final user = SupabaseService.currentUser;
      if (user != null) {
        try {
          row = await SupabaseService.getSpo2ForDate(user.id, date);
          if (!mounted) return;
          if (row != null) {
            final avg = (row['avg_spo2'] as num? ?? 0).toInt();
            final minV = (row['min_spo2'] as num? ?? 0).toInt();
            final maxV = (row['max_spo2'] as num? ?? 0).toInt();
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
              vital: 'spo2',
              date: date,
              avg: avg,
              min: minV,
              max: maxV,
              count: (row['sample_count'] as num?)?.toInt() ?? 1,
            );
          }
        } catch (e) {
          if (mounted && isNetworkError(e) && !_local.hasData(local)) {
            setState(() => _dayOffline = true);
          }
        }
      }

      if (!_local.hasData(local) && (row == null || row.isEmpty) && !slots.any((v) => v > 0) && _selectedDate == date) {
        setState(() {
          _dayAvg = 0;
          _dayMin = 0;
          _dayMax = 0;
          _chartValues = [];
        });
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'blood_oxygen_screen',
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
      final localRows = await _local.getHistory('spo2', days: 7);
      final localVals = await _local.historyAvgSeries('spo2', days: 7);
      if (!mounted) return;
      if (localVals.any((v) => v > 0)) {
        final mm = TrendMath.minMax(localRows, 'min', 'max');
        setState(() {
          _trendValues = localVals;
          _trendMin = mm.min;
          _trendMax = mm.max;
        });
      }

      final user = SupabaseService.currentUser;
      if (user == null) return;
      try {
        final now = DateTime.now();
        final rows = await SupabaseService.getSpo2History(
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
          return (row['avg_spo2'] as num? ?? 0).toInt();
        });
        if (!mounted) return;
        final hasLocalTrend = localVals.any((v) => v > 0);
        if (!hasLocalTrend && vals.any((v) => v > 0)) {
          final mm2 = TrendMath.minMax(rows, 'min_spo2', 'max_spo2');
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
            vital: 'spo2',
            date: day,
            avg: r['avg_spo2'] as num?,
            min: r['min_spo2'] as num?,
            max: r['max_spo2'] as num?,
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
        source: 'blood_oxygen_screen',
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
        source: 'blood_oxygen_screen',
        error: Exception('manual SpO2 tapped while disconnected'),
        customMessage: 'Measurement tapped while ring not connected',
      );
      if (mounted) {
        showGlassPill(context, 'Please connect your ring first', type: GlassPillType.error);
      }
      return;
    }
    setState(() {
      _measuring = true;
      _manualSpo2 = 0;
    });
    try {
      final result = await _ble.manualModeBloodOxygen(start: true);
      int liveVal = 0;
      try {
        final m = jsonDecode(result) as Map<String, dynamic>;
        liveVal = (m['spo2'] as num?)?.toInt() ?? 0;
        if (liveVal <= 0) liveVal = (m['value'] as num?)?.toInt() ?? 0;
        if (liveVal <= 0) liveVal = (m['bloodOxygen'] as num?)?.toInt() ?? 0;
      } catch (e, st) {
        IncidentService.reportUnhandled(
          source: 'blood_oxygen_screen',
          error: e,
          stackTrace: st,
          customMessage: 'parse manual spo2 result failed',
          extraInfo: {'rawResult': result},
        );
      }
      if (!mounted) return;
      if (liveVal > 0) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        setState(() {
          _measuring = false;
          _manualSpo2 = liveVal;
          _latestSpo2 = liveVal;
          _latestSpo2At = nowMs;
        });
        try {
          context.read<BleProvider>().updateSpo2Latest(liveVal, nowMs);
        } catch (e, st) {
          IncidentService.reportUnhandled(
            source: 'blood_oxygen_screen',
            error: e,
            stackTrace: st,
            customMessage: 'updateSpo2Latest failed',
            extraInfo: {'liveVal': liveVal},
          );
        }
        try {
          await _ble.insertSpo2(valuePct: liveVal, measuredAtMs: nowMs, source: 'manual');
        } catch (e, st) {
          IncidentService.reportUnhandled(
            source: 'blood_oxygen_screen',
            error: e,
            stackTrace: st,
            customMessage: 'insertSpo2 failed',
            extraInfo: {'liveVal': liveVal, 'measuredAtMs': nowMs},
          );
        }
        // Refresh true aggregates from Room (not Supabase weighted estimate).
        try {
          final summaryJson = await _ble.getTodaySummary('spo2');
          final summary = jsonDecode(summaryJson) as Map<String, dynamic>;
          final count = (summary['count'] as num?)?.toInt() ?? 1;
          final avg = (summary['avg'] as num?)?.round() ?? liveVal;
          final minVal = (summary['min'] as num?)?.toInt() ?? liveVal;
          final maxVal = (summary['max'] as num?)?.toInt() ?? liveVal;
          if (mounted) {
            setState(() { _avgSpo2 = avg; _minSpo2 = minVal; _maxSpo2 = maxVal; });
            try {
              context.read<BleProvider>().updateSpo2Data(avg, minVal, maxVal);
            } catch (e, st) {
              IncidentService.reportUnhandled(
                source: 'blood_oxygen_screen',
                error: e,
                stackTrace: st,
                customMessage: 'updateSpo2Data failed',
              );
            }
          }
          final user = SupabaseService.currentUser;
          if (user != null) {
            await SupabaseService.upsertSpo2(userId: user.id, date: DateTime.now(), avgSpo2: avg, minSpo2: minVal, maxSpo2: maxVal, sampleCount: count);
          }
          await _fetchToday();
        } catch (e, st) {
          IncidentService.reportUnhandled(
            source: 'blood_oxygen_screen',
            error: e,
            stackTrace: st,
            customMessage: 'refresh aggregates from Room failed',
            extraInfo: {'liveVal': liveVal},
          );
          await _saveSingleMeasurement(liveVal);
        }
      } else {
        IncidentService.reportUnhandled(
          source: 'blood_oxygen_screen',
          error: Exception('manual SpO2 returned no valid value'),
          customMessage: 'manual SpO2 measurement returned 0',
          extraInfo: {'rawResult': result},
        );
        if (mounted) {
          setState(() => _measuring = false);
          showGlassPill(context, 'SpO2 measurement returned no data — keep ring snug and retry. Raw: $result', type: GlassPillType.error);
        } else {
          setState(() => _measuring = false);
        }
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'blood_oxygen_screen',
        error: e,
        stackTrace: st,
        customMessage: 'manual SpO2 measurement failed',
      );
      if (mounted) {
        setState(() => _measuring = false);
        final msg = e.toString().contains('BUSY')
            ? 'Another measurement is in progress — wait and retry.'
            : e.toString().contains('TIMEOUT')
                ? 'SpO2 measurement timed out — keep ring on finger and retry.'
                : 'SpO2 measurement failed: $e';
        showGlassPill(context, msg, type: GlassPillType.error);
      } else {
        if (mounted) setState(() => _measuring = false);
      }
    }
  }

  Future<void> _saveSingleMeasurement(int spo2) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      final existing = await SupabaseService.getSpo2ForDate(
        user.id,
        DateTime.now(),
      );
      int newAvg, newMin, newMax, newCount;
      final prevCount = (existing?['sample_count'] as num? ?? 0).toInt();
      if (existing != null && prevCount > 0) {
        final prevAvg = (existing['avg_spo2'] as num).toInt();
        final prevMin = (existing['min_spo2'] as num).toInt();
        final prevMax = (existing['max_spo2'] as num).toInt();
        newCount = prevCount + 1;
        newAvg = ((prevAvg * prevCount + spo2) / newCount).round();
        newMin = spo2 < prevMin ? spo2 : prevMin;
        newMax = spo2 > prevMax ? spo2 : prevMax;
      } else {
        newAvg = newMin = newMax = spo2;
        newCount = 1;
      }
      await SupabaseService.upsertSpo2(
        userId: user.id,
        date: DateTime.now(),
        avgSpo2: newAvg,
        minSpo2: newMin,
        maxSpo2: newMax,
        sampleCount: newCount,
      );
      if (mounted) {
        context.read<BleProvider>().updateSpo2Data(newAvg, newMin, newMax);
        setState(() {
          _avgSpo2 = newAvg;
          _minSpo2 = newMin;
          _maxSpo2 = newMax;
        });
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'blood_oxygen_screen',
        error: e,
        stackTrace: st,
        customMessage: '_saveSingleMeasurement failed',
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
              shareScreenshot(_screenshotKey, text: 'My Blood Oxygen — Vital Monitoring'),
        ),
        GlassMenuItem(
          label: 'Note',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VitalNoteScreen.fromMetric(HealthMetric.spo2),
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
            const Icon(Icons.list_alt_rounded, color: AppTheme.spo2Color, size: 18),
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
        'spo2',
        fromMs: dayStart,
        toMs: dayEnd,
        limit: 1000,
      );
      final decoded = jsonDecode(readingsJson);
      if (decoded is List && decoded.isNotEmpty) {
        for (final item in decoded.reversed) {
          if (item is! Map) continue;
          final m = Map<String, dynamic>.from(item);
          final v = (m['valuePct'] as num?)?.toInt() ?? 0;
          final ms = (m['measuredAt'] as num?)?.toInt() ?? 0;
          if (v <= 0 || ms <= 0) continue;
          final dt = DateTime.fromMillisecondsSinceEpoch(ms);
          final assessment = HealthEngine.instance.assessSpo2(v);
          entries.add(MeasurementEntry(
            time: dt,
            value: '$v',
            unit: '%',
            label: assessment.label,
            color: assessment.color,
            icon: Icons.bloodtype_rounded,
          ));
        }
      }
    } catch (_) {}

    if (entries.isEmpty) {
      for (int i = 0; i < _chartValues.length; i++) {
        if (_chartValues[i] <= 0) continue;
        final minutes = i * 30;
        final dt = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, minutes ~/ 60, minutes % 60);
        final v = _chartValues[i];
        final assessment = HealthEngine.instance.assessSpo2(v);
        entries.add(MeasurementEntry(
          time: dt, value: '$v', unit: '%',
          label: assessment.label, color: assessment.color,
          icon: Icons.bloodtype_rounded,
        ));
      }
    }

    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => MeasurementLogScreen(
        title: 'Blood Oxygen Readings', date: _selectedDate,
        entries: entries, accentColor: AppTheme.spo2Color,
      ),
    ));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<String> _trendXLabels() => DateKeys.trendXLabels();

  String _hourLabel(int hour) => Formatters.hourLabel(hour);

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final connected = ble.isConnected;

    final localLatest = _displayLatestLocal;
    final providerLatest = ble.latestSpo2;
    final displayLatest = localLatest > 0 ? localLatest : providerLatest;
    final spo2Value = _measuring
        ? '···'
        : displayLatest > 0
        ? '$displayLatest'
        : _displayAvg > 0
        ? '$_displayAvg'
        : '--';
    final isStale = !_measuring && displayLatest == 0 && _displayAvg > 0;

    final hasChartData = _chartValues.any((v) => v > 0);
    final hasData = hasChartData || _displayAvg > 0 || _latestSpo2 > 0;

    final dailyRangeLabel = hasData ? '$_displayMin – $_displayMax' : '-- --';

    final trendRangeLabel = _trendMin > 0 && _trendMax > 0
        ? '$_trendMin – $_trendMax %'
        : '-- -- %';

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
            'Blood Oxygen',
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

              // ── 3. Current SpO₂ value ──────────────────────────────────────
              Text(
                'CURRENT BLOOD OXYGEN',
                style: _inter(
                  11,
                  weight: FontWeight.w600,
                  color: AppTheme.spo2Color,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                spo2Value,
                style: _inter(
                  52,
                  weight: FontWeight.w300,
                  color: isStale ? Colors.white.withValues(alpha: 0.6) : Colors.white,
                  height: 1.1,
                ),
              ),
              Row(
                children: [
                  Text('%', style: _inter(13, color: AppTheme.textTertiary)),
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
                  metric: 'blood oxygen',
                  date: _selectedDate,
                  isConnected: connected,
                  measuring: _measuring,
                  loading: _loadingDay,
                  onMeasure: _startMeasurement,
                  measureLabel: 'Measure SpO₂',
                ),
              ] else ...[
                ScrubbableChart(
                  values: _chartValues,
                  maxY: 100,
                  baseline: 85,
                  yLines: const [100, 97, 94, 85],
                  barColor: AppTheme.spo2Color.withValues(alpha: 0.88),
                  accent: AppTheme.spo2Color,
                  headerLabel: hasData ? 'TODAY' : 'NO DATA YET',
                  rangeLabel: dailyRangeLabel,
                  yLabels: const ['100', '97', '94', '85'],
                  xLabels: const ['12am', '6am', '12pm', '6pm', ''],
                  barCount: _chartValues.length,
                  loading: _loading || _loadingDay,
                  loadingAccent: AppTheme.spo2Color,
                  valueLabelBuilder: (i, v) => '${_hourLabel(i)} • $v%',
                ),
                if (_dayOffline && !_isToday) ...[
                  const SizedBox(height: 8),
                  const OfflineNotice(
                    message: 'Connect to WiFi to load this day\'s SpO2',
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: MetricStatCard(
                        label: 'AVERAGE',
                        value: _displayAvg > 0 ? '$_displayAvg' : '--',
                        unit: _displayAvg > 0 ? '%' : '--',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MetricStatCard(
                        label: 'MINIMUM',
                        value: _displayMin > 0 ? '$_displayMin' : '--',
                        unit: _displayMin > 0 ? '%' : '--',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MetricStatCard(
                        label: 'MAXIMUM',
                        value: _displayMax > 0 ? '$_displayMax' : '--',
                        unit: _displayMax > 0 ? '%' : '--',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                RealTimeCard(
                  title: 'Real Time Blood Oxygen',
                  value: _measuring ? '···' : _manualSpo2 > 0 ? '$_manualSpo2' : '--',
                  unit: '%',
                  accent: AppTheme.spo2Color,
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

              // ── 7. 7-day trend — also collapse when empty (2+ days required)
              if (!TrendMath.hasEnoughTrendData(_trendValues) && !_loadingTrend && !_trendOffline)
                const NotEnoughTrendDataCard(metric: 'blood oxygen')
              else ...[
                ScrubbableChart(
                  values: _trendValues,
                  maxY: 100,
                  baseline: 85,
                  yLines: const [100, 97, 94, 85],
                  barColor: AppTheme.spo2Color.withValues(alpha: 0.88),
                  accent: AppTheme.spo2Color,
                  headerLabel: 'LAST 7 DAYS TREND',
                  rangeLabel: trendRangeLabel,
                  yLabels: const ['100', '97', '94', '85'],
                  xLabels: _trendXLabels(),
                  barCount: _trendValues.length,
                  loading: _loadingTrend,
                  loadingAccent: AppTheme.spo2Color,
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
