import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/supabase_service.dart';
import '../../services/unit_prefs.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_menu.dart';
import '../../widgets/offline_notice.dart';
import '../../widgets/screenshot_share.dart';
import 'vital_note_screen.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';


// ── Local design tokens — same system as heart_rate_screen.dart / blood_oxygen_screen.dart ──

const _kCard = AppTheme.card;
const _kBorder = AppTheme.div;
const _kGrid = Color(0xFF222222);
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

class TemperatureScreen extends StatefulWidget {
  const TemperatureScreen({super.key});
  @override
  State<TemperatureScreen> createState() => _TemperatureScreenState();
}

class _TemperatureScreenState extends State<TemperatureScreen> {
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

  bool get _isToday {
    final n = DateTime.now();
    return _selectedDate.year == n.year &&
        _selectedDate.month == n.month &&
        _selectedDate.day == n.day;
  }

  double get _displayAvg {
    if (!_isToday) return _dayAvg;
    if (_avgTemp > 0) return _avgTemp;
    try { return context.read<BleProvider>().latestTempC; } catch(_) { return 0.0; }
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

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _tempLabel(double v) {
    if (v <= 0) return '--';
    if (v < 36.0) return 'Low';
    if (v <= 37.2) return 'Normal';
    if (v <= 38.0) return 'Elevated';
    return 'Fever';
  }

  static Color _tempStatusColor(double v) {
    if (v <= 0) return _kSec2;
    if (v < 36.0) return AppTheme.spo2Color;
    if (v <= 37.2) return AppTheme.success;
    if (v <= 38.0) return const Color(0xFFFBBF24);
    return AppTheme.danger;
  }

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
    final n = DateTime.now();
    final isToday =
        date.year == n.year && date.month == n.month && date.day == n.day;
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
          jsonDecode(await _ble.getTodaySummary('temperature'))
              as Map<String, dynamic>;
      final count = (summary['count'] as num? ?? 0).toInt();

      final hourly = List<double>.filled(24, 0);
      if (count > 0) {
        final readingsJson = await _ble.getReadings(
          'temperature',
          fromMs: dayStart,
          toMs: dayEnd,
          limit: 1000,
        );
        final decoded = jsonDecode(readingsJson);
        final list = decoded is List ? decoded : <dynamic>[];
        final sums = List<double>.filled(24, 0);
        final counts = List<int>.filled(24, 0);
        for (final item in list) {
          final m = item as Map<String, dynamic>;
          final v = (m['valueC'] as num? ?? 0).toDouble();
          final measuredAt = (m['measuredAt'] as num? ?? 0).toInt();
          if (v <= 0 || measuredAt <= 0) continue;
          final h = DateTime.fromMillisecondsSinceEpoch(measuredAt).hour;
          sums[h] += v;
          counts[h] += 1;
        }
        for (int h = 0; h < 24; h++) {
          if (counts[h] > 0) hourly[h] = sums[h] / counts[h];
        }
      }

      if (!mounted) return;
      final avg = (summary['avg'] as num?)?.toDouble() ?? 0;
      final minVal = (summary['min'] as num?)?.toDouble() ?? 0;
      final maxVal = (summary['max'] as num?)?.toDouble() ?? 0;
      setState(() {
        _chartValues = hourly;
        _avgTemp = avg;
        _minTemp = minVal;
        _maxTemp = maxVal;
        _selectedDate = DateTime.now();
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Supabase fetches ──────────────────────────────────────────────────────

  Future<void> _loadDayFromSupabase(DateTime date) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() {
      _loadingDay = true;
      _dayOffline = false;
    });
    try {
      final rows = await SupabaseService.getTempReadings(
        userId: user.id,
        from: DateTime(date.year, date.month, date.day),
        to: DateTime(date.year, date.month, date.day, 23, 59, 59),
      );

      final dayStart = DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
      final dayEnd = DateTime(date.year, date.month, date.day, 23, 59, 59, 999).millisecondsSinceEpoch;
      final readingsJson = await _ble.getReadings('temperature', fromMs: dayStart, toMs: dayEnd, limit: 1000);
      final decoded = jsonDecode(readingsJson);
      final list = decoded is List ? decoded : <dynamic>[];
      
      final hourly = List<double>.filled(24, 0);
      final sums = List<double>.filled(24, 0);
      final counts = List<int>.filled(24, 0);
      for (final item in list) {
        final m = item as Map<String, dynamic>;
        final v = (m['valueC'] as num? ?? 0).toDouble();
        final measuredAt = (m['measuredAt'] as num? ?? 0).toInt();
        if (v <= 0 || measuredAt <= 0) continue;
        final h = DateTime.fromMillisecondsSinceEpoch(measuredAt).hour;
        sums[h] += v;
        counts[h] += 1;
      }
      for (int h = 0; h < 24; h++) {
        if (counts[h] > 0) hourly[h] = sums[h] / counts[h];
      }

      final vals = rows
          .map((r) => (r['value_c'] as num? ?? 0).toDouble())
          .where((v) => v > 0)
          .toList();
      if (!mounted) return;
      setState(() {
        _dayAvg = vals.isEmpty ? 0 : vals.reduce((a, b) => a + b) / vals.length;
        _dayMin = vals.isEmpty ? 0 : vals.reduce((a, b) => a < b ? a : b);
        _dayMax = vals.isEmpty ? 0 : vals.reduce((a, b) => a > b ? a : b);
        if (_selectedDate == date) _chartValues = hourly;
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
      final rows = await SupabaseService.getTempReadings(
        userId: user.id,
        from: now.subtract(const Duration(days: 6)),
        to: now,
      );
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
        final key = _fmt(now.subtract(Duration(days: 6 - i)));
        final c = counts[key];
        if (c == null || c == 0) return 0.0;
        return sums[key]! / c;
      });
      final nonZero = vals.where((v) => v > 0).toList();
      if (!mounted) return;
      setState(() {
        _trendValues = vals;
        _trendMin = nonZero.isEmpty
            ? 0
            : nonZero.reduce((a, b) => a < b ? a : b);
        _trendMax = nonZero.isEmpty
            ? 0
            : nonZero.reduce((a, b) => a > b ? a : b);
      });
    } catch (e) {
      if (mounted && isNetworkError(e)) setState(() => _trendOffline = true);
    } finally {
      if (mounted) setState(() => _loadingTrend = false);
    }
  }

  // ── Manual measurement ────────────────────────────────────────────────────

  Future<void> _startMeasurement() async {
    if (_measuring) return;
    setState(() {
      _measuring = true;
      _manualTemp = 0;
    });
    try {
      final data = await _ble.syncManualTemperature();
      final readings = _parseTempReadings(data, _selectedDate);
      if (readings.isNotEmpty) {
        final latest = readings.last.valueC;
        setState(() {
          _manualTemp = latest;
          _measuring = false;
        });
        await _saveToSupabase(readings);
        // The native side persisted the reading to Room and fired a
        // newReading event; re-pull so the today chart/avg/min/max reflect it.
        if (_isToday) await _fetchTodayFromLocalDb();
        setState(() => _manualTemp = latest);
      } else {
        setState(() => _measuring = false);
      }
    } catch (_) {
      if (mounted) setState(() => _measuring = false);
    }
  }

  static List<_TempReading> _parseTempReadings(
    String jsonStr,
    DateTime selectedDate,
  ) {
    final readings = <_TempReading>[];
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is List && decoded.isNotEmpty) {
        for (final item in decoded) {
          final m = item as Map<String, dynamic>;
          final ts = (m['mTime'] as num?)?.toInt() ?? (m['a'] as num?)?.toInt();
          var val =
              (m['mValue'] as num?)?.toDouble() ?? (m['b'] as num?)?.toDouble();
          if (ts == null || val == null || val <= 0) continue;
          if (val > 100) val /= 10;
          readings.add(
            _TempReading(
              time: DateTime.fromMillisecondsSinceEpoch(ts * 1000).toLocal(),
              valueC: val,
            ),
          );
        }
      } else if (decoded is Map<String, dynamic>) {
        final rawVals =
            (decoded['mValues'] as List<dynamic>?) ??
            (decoded['d'] as List<dynamic>?);
        final spanSec =
            (decoded['mTimeSpan'] as num?)?.toInt() ??
            (decoded['b'] as num?)?.toInt() ??
            5;
        if (rawVals != null) {
          final base = DateTime(
            selectedDate.year,
            selectedDate.month,
            selectedDate.day,
          );
          for (int i = 0; i < rawVals.length; i++) {
            var v = (rawVals[i] as num).toDouble();
            if (v <= 0) continue;
            if (v > 100) v /= 10;
            readings.add(
              _TempReading(
                time: base.add(Duration(seconds: i * spanSec)),
                valueC: v,
              ),
            );
          }
        }
      }
    } catch (_) {}
    return readings;
  }

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
    } catch (_) {}
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
              builder: (_) => const VitalNoteScreen(
                title: 'Temperature',
                heading: 'About Temperature',
                intro:
                    'Skin temperature measured by the ring — most useful as '
                    'a deviation from your own baseline, not as an absolute '
                    'clinical reading.',
                ranges: [
                  VitalRange(
                    label: 'Low',
                    range: '< 36.0°C',
                    color: AppTheme.spo2Color,
                  ),
                  VitalRange(
                    label: 'Normal',
                    range: '36.0–37.2°C',
                    color: AppTheme.success,
                  ),
                  VitalRange(
                    label: 'Elevated',
                    range: '37.2–38.0°C',
                    color: Color(0xFFFBBF24),
                  ),
                  VitalRange(
                    label: 'Fever',
                    range: '> 38.0°C',
                    color: AppTheme.danger,
                  ),
                ],
                tips: [
                  VitalTip(
                    icon: Icons.show_chart_rounded,
                    color: AppTheme.tempColor,
                    title: 'Track your baseline',
                    tip:
                        'Skin temperature varies person to person — a rise '
                        'of 0.5°C+ from your usual baseline matters more '
                        'than the absolute number.',
                  ),
                  VitalTip(
                    icon: Icons.schedule_rounded,
                    color: AppTheme.hrvColor,
                    title: 'It has a daily rhythm',
                    tip:
                        'Temperature naturally dips overnight and rises '
                        'through the day — that\'s expected, not a fever.',
                  ),
                ],
                didYouKnow:
                    'Skin temperature runs cooler than core body '
                    'temperature — don\'t compare it directly to an oral '
                    'thermometer reading.',
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

    final tempValue = _measuring
        ? '···'
        : _manualTemp > 0
        ? _disp(_manualTemp).toStringAsFixed(1)
        : _displayAvg > 0
        ? _disp(_displayAvg).toStringAsFixed(1)
        : '--';

    final hasData = _chartValues.any((v) => v > 0);

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
            child: Container(color: _kBorder, height: 0.5),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // ── 1. Date row ────────────────────────────────────────────────
              _TempDateRow(
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
                  Text(_unitLabel, style: _inter(20, color: _kSec)),
                ],
              ),
              Text(
                _measuring
                    ? 'Measuring…'
                    : _tempLabel(_manualTemp > 0 ? _manualTemp : _displayAvg),
                style: _inter(
                  13,
                  weight: FontWeight.w600,
                  color: _measuring
                      ? _kSec
                      : _tempStatusColor(
                          _manualTemp > 0 ? _manualTemp : _displayAvg,
                        ),
                ),
              ),
              const SizedBox(height: 16),

              // ── 3. Daily chart ────────────────────────────────────────────
              _TempChartCard(
                headerLabel: hasData ? 'TODAY' : 'NO DATA YET',
                rangeLabel: dailyRangeLabel,
                values: _chartValues,
                xLabels: const ['12am', '6am', '12pm', '6pm', ''],
                loading: _loading || _loadingDay,
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
                    child: _TempStatCard(
                      label: 'AVERAGE',
                      value: _displayAvg > 0
                          ? _disp(_displayAvg).toStringAsFixed(1)
                          : '--',
                      unit: _displayAvg > 0 ? _unitLabel : '--',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _TempStatCard(
                      label: 'MINIMUM',
                      value: _displayMin > 0
                          ? _disp(_displayMin).toStringAsFixed(1)
                          : '--',
                      unit: _displayMin > 0 ? _unitLabel : '--',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _TempStatCard(
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
              const SizedBox(height: 20),

              // ── 6. 7-day trend ────────────────────────────────────────────
              _TempChartCard(
                headerLabel: 'LAST 7 DAYS TREND',
                rangeLabel: trendRangeLabel,
                values: _trendValues,
                xLabels: _trendXLabels(),
                loading: _loadingTrend,
                showLegend: true,
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

// ── Data model ─────────────────────────────────────────────────────────────────

class _TempReading {
  final DateTime time;
  final double valueC;
  const _TempReading({required this.time, required this.valueC});
}

// ── Date row ──────────────────────────────────────────────────────────────────

class _TempDateRow extends StatelessWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  const _TempDateRow({
    required this.selectedDate,
    required this.onDateSelected,
  });

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dates = List.generate(7, (i) => today.add(Duration(days: i - 3)));

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < dates.length; i++) ...[
                  if (i > 0) const SizedBox(width: 16),
                  _buildItem(dates[i], today),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildItem(DateTime d, DateTime today) {
    final isToday = d == today;
    final isFuture = d.isAfter(today);
    final sel = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    final isSelected = d == sel;

    if (isSelected) {
      return GestureDetector(
        onTap: null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF202020),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF363636)),
          ),
          child: Text(
            isToday
                ? 'Today, ${d.day} ${_months[d.month - 1]}'
                : '${d.day} ${_months[d.month - 1]}',
            style: _inter(13, weight: FontWeight.w500),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: isFuture ? null : () => onDateSelected(d),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text(
          '${d.day}',
          style: _inter(15, color: isFuture ? const Color(0xFF333333) : (isToday ? Colors.white : _kSec2)),
        ),
      ),
    );
  }
}

// ── Temperature chart card ──────────────────────────────────────────────────

class _TempChartCard extends StatelessWidget {
  final String headerLabel;
  final String rangeLabel;
  final List<double> values;
  final List<String> xLabels;
  final bool loading;
  final bool showLegend;

  const _TempChartCard({
    required this.headerLabel,
    required this.rangeLabel,
    required this.values,
    required this.xLabels,
    required this.loading,
    this.showLegend = false,
  });

  static const _yAxisW = 30.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                headerLabel,
                style: _inter(
                  11,
                  weight: FontWeight.w600,
                  color: _kSec,
                  letterSpacing: 0.6,
                ),
              ),
              Text(
                rangeLabel,
                style: _inter(
                  11,
                  weight: FontWeight.w500,
                  color: const Color(0xFF999999),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 128,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: _yAxisW,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: ['40', '38', '36', '34']
                        .map(
                          (l) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(l, style: _inter(10, color: _kSec)),
                          ),
                        )
                        .toList(),
                  ),
                ),
                Expanded(
                  child: loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppTheme.tempColor,
                            strokeWidth: 2,
                          ),
                        )
                      : CustomPaint(
                          painter: _TempBarPainter(values: values),
                          child: const SizedBox.expand(),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: _yAxisW),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: xLabels
                  .map((l) => Text(l, style: _inter(10, color: _kSec)))
                  .toList(),
            ),
          ),
          if (showLegend) ...[
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _LegendDot(color: AppTheme.spo2Color, label: 'Low'),
                _LegendDot(color: AppTheme.success, label: 'Normal'),
                _LegendDot(color: Color(0xFFFBBF24), label: 'Elevated'),
                _LegendDot(color: AppTheme.danger, label: 'Fever'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Temperature bar painter ─────────────────────────────────────────────────

class _TempBarPainter extends CustomPainter {
  final List<double> values;
  const _TempBarPainter({required this.values});

  static const _minY = 34.0;
  static const _maxY = 40.0;
  static const _range = _maxY - _minY;
  static const _yLines = [40.0, 38.0, 36.0, 34.0];

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = _kGrid
      ..strokeWidth = 0.5;
    for (final y in _yLines) {
      final yPos = size.height - ((y - _minY) / _range) * size.height;
      canvas.drawLine(Offset(0, yPos), Offset(size.width, yPos), gridPaint);
    }

    if (values.isEmpty) return;
    final n = values.length;
    final slotW = size.width / n;
    final barW = (slotW * 0.55).clamp(2.0, 9.0);

    for (int i = 0; i < n; i++) {
      if (values[i] <= 0) continue;
      final ratio = ((values[i] - _minY) / _range).clamp(0.0, 1.0);
      final barH = (ratio * size.height).clamp(2.0, size.height);
      final x = i * slotW + (slotW - barW) / 2;
      canvas.drawRRect(
        RRect.fromLTRBR(
          x,
          size.height - barH,
          x + barW,
          size.height,
          const Radius.circular(3),
        ),
        Paint()..color = _tempBarColor(values[i]),
      );
    }
  }

  @override
  bool shouldRepaint(_TempBarPainter old) => old.values != values;
}

Color _tempBarColor(double v) {
  if (v < 36.0) return AppTheme.spo2Color;
  if (v <= 37.2) return AppTheme.success;
  if (v <= 38.0) return const Color(0xFFFBBF24);
  return AppTheme.danger;
}

// ── Stat cards ────────────────────────────────────────────────────────────────

class _TempStatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  const _TempStatCard({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: _inter(
              10,
              weight: FontWeight.w600,
              color: _kSec,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: _inter(17, weight: FontWeight.w600)),
              const SizedBox(width: 4),
              Text(unit, style: _inter(11, color: _kSec)),
            ],
          ),
        ],
      ),
    );
  }
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
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
                          : _kSec2,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(unitLabel, style: _inter(11, color: _kSec)),
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
                          color: enabled ? AppTheme.tempColor : _kSec,
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
    );
  }
}

// ── Legend ───────────────────────────────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: _inter(11, color: _kSec2)),
    ],
  );
}
