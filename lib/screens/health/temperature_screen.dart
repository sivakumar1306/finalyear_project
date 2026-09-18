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
import '../../services/unit_prefs.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_menu.dart';
import '../../widgets/offline_notice.dart';
import '../../widgets/screenshot_share.dart';
import 'vital_note_screen.dart';
import '../../services/health_engine/health_engine.dart';
import '../../services/health_engine/models.dart';
import '../../services/health_engine/temperature_engine.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/date_scroll_row.dart';
import '../../widgets/legend_dot.dart';
import '../../widgets/chart_scrubber.dart';
import '../../widgets/glass_pill.dart';
import '../../utils/date_keys.dart';
import '../../utils/formatters.dart';
import '../../widgets/metric_stat_card.dart';
import '../../widgets/not_enough_data_card.dart';
import '../../utils/hourly_aggregator.dart';
import '../../utils/trend_math.dart';
import 'measurement_log_screen.dart';


// ── Local design tokens — same system as heart_rate_screen.dart / blood_oxygen_screen.dart ──


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

class TemperatureScreen extends StatefulWidget {
  const TemperatureScreen({super.key});
  @override
  State<TemperatureScreen> createState() => _TemperatureScreenState();
}

class _TemperatureScreenState extends State<TemperatureScreen> {
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

  TempUnit _tempUnit = TempUnit.celsius;

  double _manualTemp = 0;

  // Today's local-DB data
  List<double> _chartValues = [];
  double _avgTemp = 0, _minTemp = 0, _maxTemp = 0;

  // Past-day Supabase data
  double _dayAvg = 0, _dayMin = 0, _dayMax = 0;

  // 7-day trend
  List<double> _trendValues = [];
  double _trendMin = 0, _trendMax = 0;

  // ── Computed ──────────────────────────────────────────────────────────────

  bool get _isToday => DateKeys.isToday(_selectedDate);

  double get _displayAvg {
    if (!_isToday) return _dayAvg;
    try {
      final v = context.read<BleProvider>().latestTempC;
      if (v > 0) return v;
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'temperature_screen',
        error: e,
        stackTrace: st,
        customMessage: 'read latestTempC failed',
      );
    }
    if (_avgTemp > 0) return _avgTemp;
    return 0.0;
  }

  double get _displayMin {
    if (!_isToday) return _dayMin;
    if (_minTemp > 0) return _minTemp;
    return 0.0;
  }

  double get _displayMax {
    if (!_isToday) return _dayMax;
    if (_maxTemp > 0) return _maxTemp;
    return 0.0;
  }

  String _fmt(DateTime d) => DateKeys.fmt(d);

  // Display-only conversion — every stored/aggregated value above stays in
  // Celsius (the ring's native unit and the DB's canonical column); only the
  // number shown to the user changes with the Temperature Unit setting.
  double _disp(double celsiusValue) => _tempUnit == TempUnit.fahrenheit
      ? UnitPrefs.celsiusToFahrenheit(celsiusValue)
      : celsiusValue;

  String get _unitLabel => _tempUnit == TempUnit.fahrenheit ? '°F' : '°C';

  // ── Init ──────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _fetchTodayFromLocalDb();
      _load7DayTrend();
    });
    _loadTempUnit();
  }



  Future<void> _loadTempUnit() async {
    final unit = await UnitPrefs.loadTempUnit();
    if (mounted) setState(() => _tempUnit = unit);
  }

  // ── Date selection ────────────────────────────────────────────────────────

  void _onDateSelected(DateTime date) {
    final isToday = DateKeys.isToday(date);
    setState(() {
      _selectedDate = date;
      _manualTemp = 0;
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
    try {
      final now = DateTime.now();
      final dayStart = DateKeys.dayStartMs(now);
      final dayEnd = DateKeys.dayEndMs(now);

      final summary =
          jsonDecode(await _ble.getTodaySummary('temperature'))
              as Map<String, dynamic>;

      final hourly = List<double>.filled(24, 0);
      try {
        final readingsJson = await _ble.getReadings(
          'temperature',
          fromMs: dayStart,
          toMs: dayEnd,
          limit: 1000,
        );
        final decoded = jsonDecode(readingsJson);
        final list = decoded is List ? decoded : <dynamic>[];
        final typedTemp = list.whereType<Map<String, dynamic>>().toList();
        final aggTemp = HourlyAggregator.aggregateDouble(typedTemp, valueKey: 'valueC', measuredAtKey: 'measuredAt', slots: 24);
        for (int h = 0; h < 24; h++) {
          hourly[h] = aggTemp[h];
        }
      } catch (e, st) {
        IncidentService.reportUnhandled(
          source: 'temperature_screen',
          error: e,
          stackTrace: st,
          customMessage: 'build daily chart slots failed',
        );
      }

      if (!mounted) return;
      final avg = (summary['avg'] as num?)?.toDouble() ?? 0;
      final minVal = (summary['min'] as num?)?.toDouble() ?? 0;
      final maxVal = (summary['max'] as num?)?.toDouble() ?? 0;
      if (!hourly.any((v) => v > 0) && mounted) {
        final liveVal = context.read<BleProvider>().latestTempC;
        if (liveVal > 0) {
          hourly[now.hour] = liveVal;
        }
      }
      setState(() {
        _chartValues = hourly;
        _avgTemp = avg;
        _minTemp = minVal;
        _maxTemp = maxVal;
        _selectedDate = DateTime.now();
      });
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'temperature_screen',
        error: e,
        stackTrace: st,
        customMessage: '_loadToday failed',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Supabase fetches ──────────────────────────────────────────────────────

  Future<void> _loadDayFromSupabase(DateTime date) async {
    setState(() {
      _loadingDay = true;
      _dayOffline = false;
    });
    try {
      // 1) Local Room — hourly chart + summary, works across month boundaries.
      final local = await _local.getDaySummary('temperature', date);
      final dayStart = DateKeys.dayStartMs(date);
      final dayEnd = DateKeys.dayEndMs(date);
      final readingsJson = await _ble.getReadings('temperature', fromMs: dayStart, toMs: dayEnd, limit: 1000);
      final decoded = jsonDecode(readingsJson);
      final list = decoded is List ? decoded : <dynamic>[];
      final hourly = HourlyAggregator.aggregateDouble(list.whereType<Map<String, dynamic>>().toList(), valueKey: 'valueC', measuredAtKey: 'measuredAt', slots: 24);
      if (!mounted) return;
      if (_local.hasData(local)) {
        setState(() {
          _dayAvg = (local['avg'] as num?)?.toDouble() ?? 0;
          _dayMin = (local['min'] as num?)?.toDouble() ?? 0;
          _dayMax = (local['max'] as num?)?.toDouble() ?? 0;
          if (_selectedDate.year == date.year && _selectedDate.month == date.month && _selectedDate.day == date.day) {
            _chartValues = hourly;
          }
        });
      } else if (hourly.any((v) => v > 0) && _selectedDate.year == date.year && _selectedDate.month == date.month && _selectedDate.day == date.day) {
        setState(() => _chartValues = hourly);
      } else if (hourly.any((v) => v > 0) && mounted) {
        // Keep hourly for selected date if no summary.
        if (_selectedDate.year == date.year && _selectedDate.month == date.month && _selectedDate.day == date.day) {
          setState(() => _chartValues = hourly);
        }
      }

      // 2) Cloud enrich + cache.
      final user = SupabaseService.currentUser;
      if (user == null) return;
      try {
        final rows = await SupabaseService.getTempReadings(
          userId: user.id,
          from: DateTime(date.year, date.month, date.day),
          to: DateTime(date.year, date.month, date.day, 23, 59, 59, 999),
        );
        final vals = rows.map((r) => (r['value_c'] as num? ?? 0).toDouble()).where((v) => v > 0).toList();
        if (!mounted) return;
        double avg = 0, minV = 0, maxV = 0;
        if (vals.isNotEmpty) {
          avg = vals.reduce((a, b) => a + b) / vals.length;
          minV = vals.reduce((a, b) => a < b ? a : b);
          maxV = vals.reduce((a, b) => a > b ? a : b);
          if (!_local.hasData(local) && _selectedDate.year == date.year && _selectedDate.month == date.month && _selectedDate.day == date.day) {
            setState(() {
              _dayAvg = avg;
              _dayMin = minV;
              _dayMax = maxV;
            });
          }
        }
        if (vals.isNotEmpty) {
          await _local.cacheSimpleDay(vital: 'temperature', date: date, avg: avg, min: minV, max: maxV, count: vals.length);
        }
        if (!_local.hasData(local) && vals.isEmpty && !hourly.any((v) => v > 0) &&
            _selectedDate.year == date.year && _selectedDate.month == date.month && _selectedDate.day == date.day) {
          setState(() {
            _dayAvg = 0;
            _dayMin = 0;
            _dayMax = 0;
            _chartValues = [];
          });
        }
      } catch (e) {
        if (mounted && isNetworkError(e) && !_local.hasData(local)) setState(() => _dayOffline = true);
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(source: 'temperature_screen', error: e, stackTrace: st, customMessage: '_loadDayFromSupabase failed');
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
      // 1) Local first.
      final localRows = await _local.getHistory('temperature', days: 7);
      final localValsRaw = await _local.historyAvgSeries('temperature', days: 7);
      final localVals = localValsRaw.map((v) => v.toDouble()).toList();
      final localValid = localRows.where((r) => r['min'] != null).toList();
      if (!mounted) return;
      if (localVals.any((v) => v > 0)) {
        final validVals = localVals.where((v) => v > 0).toList();
        setState(() {
          _trendValues = localVals;
          _trendMin = validVals.isEmpty ? 0 : validVals.reduce((a, b) => a < b ? a : b);
          _trendMax = validVals.isEmpty ? 0 : validVals.reduce((a, b) => a > b ? a : b);
        });
        // Keep valid min/max from rows if more precise.
        if (localValid.isNotEmpty) {
          final mins = localValid.map((r) => (r['min'] as num).toDouble()).toList();
          final maxs = localValid.map((r) => (r['max'] as num).toDouble()).toList();
          if (mins.isNotEmpty && maxs.isNotEmpty) {
            setState(() {
              _trendMin = mins.reduce((a, b) => a < b ? a : b);
              _trendMax = maxs.reduce((a, b) => a > b ? a : b);
            });
          }
        }
      }

      final user = SupabaseService.currentUser;
      if (user == null) return;
      try {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final from = today.subtract(const Duration(days: 6));
        final toEnd = DateTime(today.year, today.month, today.day, 23, 59, 59, 999);
        final rows = await SupabaseService.getTempReadings(userId: user.id, from: from, to: toEnd);
        final sums = <String, double>{};
        final counts = <String, int>{};
        for (final r in rows) {
          final v = (r['value_c'] as num? ?? 0).toDouble();
          if (v <= 0) continue;
          final dt = DateTime.parse(r['measured_at'] as String).toLocal();
          final key = _fmt(dt);
          sums[key] = (sums[key] ?? 0) + v;
          counts[key] = (counts[key] ?? 0) + 1;
        }
        final vals = List.generate(7, (i) {
          final key = _fmt(today.subtract(Duration(days: 6 - i)));
          final c = counts[key];
          if (c == null || c == 0) return 0.0;
          return sums[key]! / c;
        });
        final nonZero = vals.where((v) => v > 0).toList();
        if (!mounted) return;
        final hasLocalTrend = localVals.any((v) => v > 0);
        if (!hasLocalTrend && vals.any((v) => v > 0)) {
          setState(() {
            _trendValues = vals;
            _trendMin = nonZero.isEmpty ? 0 : nonZero.reduce((a, b) => a < b ? a : b);
            _trendMax = nonZero.isEmpty ? 0 : nonZero.reduce((a, b) => a > b ? a : b);
          });
        }
        for (int i = 0; i < 7; i++) {
          final day = today.subtract(Duration(days: 6 - i));
          final key = _fmt(day);
          final c = counts[key];
          if (c == null || c == 0) continue;
          final avg = sums[key]! / c;
          // Derive min/max from rows for that day (approx via avg ± spread if needed, but use avg for cache).
          final dayVals = rows.where((r) {
            final dt = DateTime.parse(r['measured_at'] as String).toLocal();
            return _fmt(dt) == key;
          }).map((r) => (r['value_c'] as num).toDouble()).where((v) => v > 0).toList();
          double minV = avg, maxV = avg;
          if (dayVals.isNotEmpty) {
            minV = dayVals.reduce((a, b) => a < b ? a : b);
            maxV = dayVals.reduce((a, b) => a > b ? a : b);
          }
          await _local.cacheSimpleDay(vital: 'temperature', date: day, avg: avg, min: minV, max: maxV, count: c);
        }
      } catch (e) {
        if (mounted && isNetworkError(e) && !localVals.any((v) => v > 0)) setState(() => _trendOffline = true);
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(source: 'temperature_screen', error: e, stackTrace: st, customMessage: '_load7DayTrend failed');
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
        source: 'temperature_screen',
        error: Exception('manual temp tapped while disconnected'),
        customMessage: 'Measurement tapped while ring not connected',
      );
      if (mounted) {
        showGlassPill(context, 'Please connect your ring first', type: GlassPillType.error);
      }
      return;
    }
    setState(() {
      _measuring = true;
      _manualTemp = 0;
    });
    try {
      final data = await _ble.syncManualTemperature();
      final readings = _parseTempReadings(data, _selectedDate);
      if (readings.isNotEmpty) {
        final latest = readings.last.valueC;
        if (!mounted) return;
        setState(() {
          _manualTemp = latest;
          _measuring = false;
        });
        try {
          await _saveToSupabase(readings);
        } catch (e, st) {
          IncidentService.reportUnhandled(
            source: 'temperature_screen',
            error: e,
            stackTrace: st,
            customMessage: '_saveToSupabase failed',
            extraInfo: {'readingsCount': readings.length},
          );
        }
        // The native side persisted the reading to Room and fired a
        // newReading event; re-pull so the today chart/avg/min/max reflect it.
        if (_isToday) {
          try {
            await _fetchTodayFromLocalDb();
          } catch (e, st) {
            IncidentService.reportUnhandled(
              source: 'temperature_screen',
              error: e,
              stackTrace: st,
              customMessage: '_fetchTodayFromLocalDb after manual temp failed',
            );
          }
        }
        if (!mounted) return;
        setState(() => _manualTemp = latest);
      } else {
        IncidentService.reportUnhandled(
          source: 'temperature_screen',
          error: Exception('manual temperature returned no readings'),
          customMessage: 'manual temperature measurement returned empty',
          extraInfo: {'rawData': data},
        );
        if (mounted) {
          setState(() => _measuring = false);
          showGlassPill(context, 'Temperature measurement returned no data — keep ring snug and retry. Raw: $data', type: GlassPillType.error);
        } else {
          setState(() => _measuring = false);
        }
      }
    } catch (e, st) {
      final msg = e.toString();
      // Expected ring states (busy / timeout / disconnected): user-facing
      // pill only, no app_incidents row.
      final expected = msg.contains('BUSY') ||
          msg.contains('TIMEOUT') ||
          msg.contains('NOT_CONNECTED') ||
          msg.contains('RING NOT CONNECTED') ||
          e is TimeoutException;
      if (!expected) {
        IncidentService.reportUnhandled(
          source: 'temperature_screen',
          error: e,
          stackTrace: st,
          customMessage: 'manual temperature measurement failed',
        );
      }
      if (mounted) {
        setState(() => _measuring = false);
        final msg = e.toString().contains('BUSY')
            ? 'Another measurement is in progress — wait and retry.'
            : e.toString().contains('TIMEOUT')
                ? 'Temperature measurement timed out — keep ring on finger (up to 60s).'
                : 'Temperature measurement failed: $e';
        showGlassPill(context, msg, type: GlassPillType.error);
      }
    }
  }

  static List<_TempReading> _parseTempReadings(
    String jsonStr,
    DateTime selectedDate,
  ) {
    return TemperatureEngine.parseTempReadings(jsonStr, selectedDate)
        .map((r) => _TempReading(time: r.time, valueC: r.valueC))
        .toList();
  }

  // ignore: unused_element
  List<TempReading> _demoTempParse(String jsonStr, DateTime d) {
    return TemperatureEngine.parseTempReadings(jsonStr, d);
  }
  // return TemperatureEngine.parseTempReadings(jsonStr, selectedDate);

  Future<void> _saveToSupabase(List<_TempReading> readings) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.insertTempBatch(
        userId: user.id,
        readings: readings
            .map(
              (r) => (measuredAt: r.time, valueC: r.valueC, source: 'manual'),
            )
            .toList(),
      );
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'temperature_screen',
        error: e,
        stackTrace: st,
        customMessage: '_saveToSupabase failed',
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
              shareScreenshot(_screenshotKey, text: 'My Temperature — SUNDR'),
        ),
        GlassMenuItem(
          label: 'Note',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VitalNoteScreen.fromMetric(HealthMetric.temperature),
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
            const Icon(Icons.list_alt_rounded, color: AppTheme.tempColor, size: 18),
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

  void _openMeasurementLog() {
    final entries = <MeasurementEntry>[];
    for (int i = 0; i < _chartValues.length; i++) {
      if (_chartValues[i] <= 0) continue;
      final minutes = i * 30;
      final dt = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, minutes ~/ 60, minutes % 60);
      final v = _chartValues[i];
      final assessment = HealthEngine.instance.assessTemperature(v);
      entries.add(MeasurementEntry(
        time: dt, value: v.toStringAsFixed(1), unit: '°C',
        label: assessment.label, color: assessment.color,
        icon: Icons.thermostat_rounded,
      ));
    }
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => MeasurementLogScreen(
        title: 'Temperature Readings', date: _selectedDate,
        entries: entries, accentColor: AppTheme.tempColor,
      ),
    ));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<String> _trendXLabels() => DateKeys.trendXLabels();

  String _hourLabel(int hour) => Formatters.hourLabel(hour);

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;

    final tempValue = _measuring
        ? '···'
        : _manualTemp > 0
        ? _disp(_manualTemp).toStringAsFixed(1)
        : _displayAvg > 0
        ? _disp(_displayAvg).toStringAsFixed(1)
        : '--';

    final hasChartData = _chartValues.any((v) => v > 0);
    final hasData = hasChartData || _displayAvg > 0 || _manualTemp > 0;

    final dailyRangeLabel = hasData
        ? '${_disp(_displayMin).toStringAsFixed(1)} - ${_disp(_displayMax).toStringAsFixed(1)}'
        : '-- --';

    final trendRangeLabel = _trendMin > 0 && _trendMax > 0
        ? '${_disp(_trendMin).toStringAsFixed(1)} - ${_disp(_trendMax).toStringAsFixed(1)} $_unitLabel'
        : '-- -- $_unitLabel';

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
            'Temperature',
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

              // ── 1. Date row ────────────────────────────────────────────────
              DateScrollRow(
                selectedDate: _selectedDate,
                onDateSelected: _onDateSelected,
              ),
              const SizedBox(height: 22),

              // ── 2. Current temperature value ─────────────────────────────
              Text(
                'CURRENT TEMPERATURE',
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
                    tempValue,
                    style: _inter(
                      52,
                      weight: FontWeight.w300,
                      color: Colors.white,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(_unitLabel, style: _inter(20, color: AppTheme.textTertiary)),
                ],
              ),
              Text(
                _measuring
                    ? 'Measuring…'
                    : HealthEngine.instance.assessTemperature(_manualTemp > 0 ? _manualTemp : _displayAvg).label,
                style: _inter(
                  13,
                  weight: FontWeight.w600,
                  color: _measuring
                      ? AppTheme.textTertiary
                      : HealthEngine.instance.assessTemperature(_manualTemp > 0 ? _manualTemp : _displayAvg).color,
                ),
              ),
              const SizedBox(height: 16),

              // ── 3. Daily chart ────────────────────────────────────────────
              // ── 3-5. Daily section — collapse to single glass card when empty
              if (!hasData && !_loading && !_dayOffline) ...[
                NotEnoughDataCard(
                  metric: 'temperature',
                  date: _selectedDate,
                  isConnected: connected,
                  measuring: _measuring,
                  loading: _loadingDay,
                  onMeasure: _startMeasurement,
                  measureLabel: 'Measure temperature',
                ),
              ] else ...[
                ScrubbableChart(
                  values: _chartValues,
                  maxY: 40,
                  baseline: 34,
                  yLines: const [40, 38, 36, 34],
                  colorFor: (v) => HealthEngine.instance.tempBarColor(v),
                  accent: AppTheme.tempColor,
                  headerLabel: hasData ? 'TODAY' : 'NO DATA YET',
                  rangeLabel: dailyRangeLabel,
                  yLabels: const ['40', '38', '36', '34'],
                  xLabels: const ['12am', '6am', '12pm', '6pm', ''],
                  loading: _loading || _loadingDay,
                  loadingAccent: AppTheme.tempColor,
                  valueLabelBuilder: (i, v) => '${_hourLabel(i)} • ${_disp(v.toDouble()).toStringAsFixed(1)}$_unitLabel',
                ),
                if (_dayOffline && !_isToday) ...[
                  const SizedBox(height: 8),
                  const OfflineNotice(
                    message: 'Connect to WiFi to load this day\'s temperature',
                  ),
                ],
                const SizedBox(height: 10),

                // ── 4. Stats row ──────────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: MetricStatCard(
                        label: 'AVERAGE',
                        value: _displayAvg > 0
                            ? _disp(_displayAvg).toStringAsFixed(1)
                            : '--',
                        unit: _displayAvg > 0 ? _unitLabel : '--',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MetricStatCard(
                        label: 'MINIMUM',
                        value: _displayMin > 0
                            ? _disp(_displayMin).toStringAsFixed(1)
                            : '--',
                        unit: _displayMin > 0 ? _unitLabel : '--',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MetricStatCard(
                        label: 'MAXIMUM',
                        value: _displayMax > 0
                            ? _disp(_displayMax).toStringAsFixed(1)
                            : '--',
                        unit: _displayMax > 0 ? _unitLabel : '--',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // ── 5. Real-time measurement ──────────────────────────────────
                _RealTimeTempCard(
                  latestTemp: _manualTemp > 0 ? _disp(_manualTemp) : 0,
                  unitLabel: _unitLabel,
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

              // ── 6. 7-day trend — also collapse when empty (2+ days)
              if (!TrendMath.hasEnoughTrendData(_trendValues) && !_loadingTrend && !_trendOffline)
                const NotEnoughTrendDataCard(metric: 'temperature')
              else ...[
                ScrubbableChart(
                  values: _trendValues,
                  maxY: 40,
                  baseline: 34,
                  yLines: const [40, 38, 36, 34],
                  colorFor: (v) => HealthEngine.instance.tempBarColor(v),
                  accent: AppTheme.tempColor,
                  headerLabel: 'LAST 7 DAYS TREND',
                  rangeLabel: trendRangeLabel,
                  yLabels: const ['40', '38', '36', '34'],
                  xLabels: _trendXLabels(),
                  loading: _loadingTrend,
                  loadingAccent: AppTheme.tempColor,
                  footer: const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      LegendDot(color: AppTheme.spo2Color, label: 'Low'),
                      LegendDot(color: AppTheme.success, label: 'Normal'),
                      LegendDot(color: AppTheme.tempColor, label: 'Elevated'),
                      LegendDot(color: AppTheme.danger, label: 'Fever'),
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

// ── Data model ─────────────────────────────────────────────────────────────────

class _TempReading {
  final DateTime time;
  final double valueC;
  const _TempReading({required this.time, required this.valueC});
}

// ── Real-time measurement card ────────────────────────────────────────────────

class _RealTimeTempCard extends StatelessWidget {
  final double latestTemp;
  final String unitLabel;
  final bool measuring;
  final bool enabled;
  final VoidCallback? onTap;

  const _RealTimeTempCard({
    required this.latestTemp,
    required this.unitLabel,
    required this.measuring,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tempText = measuring
        ? '···'
        : latestTemp > 0
        ? latestTemp.toStringAsFixed(1)
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
                'Real Time Temperature',
                style: _inter(14, weight: FontWeight.w500),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    tempText,
                    style: _inter(
                      15,
                      weight: FontWeight.w600,
                      color: measuring || latestTemp > 0
                          ? Colors.white
                          : AppTheme.textSec,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(unitLabel, style: _inter(11, color: AppTheme.textTertiary)),
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
                          color: AppTheme.tempColor,
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

