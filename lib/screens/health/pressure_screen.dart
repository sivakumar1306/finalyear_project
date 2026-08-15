import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_menu.dart';
import '../../widgets/offline_notice.dart';
import '../../widgets/screenshot_share.dart';
import 'vital_note_screen.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/date_scroll_row.dart';


// ── Local design tokens ───────────────────────────────────────────────────────

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

// ── Stress label / color helpers ──────────────────────────────────────────────

String _stressLabel(int v) {
  if (v <= 0) return '';
  if (v < 40) return 'Relaxed';
  if (v < 60) return 'Normal';
  if (v < 80) return 'Elevated';
  return 'High';
}

Color _stressLevelColor(int v) {
  if (v <= 0) return _kSec2;
  if (v < 40) return AppTheme.success;
  if (v < 60) return const Color(0xFFFBBF24);
  if (v < 80) return AppTheme.stressColor;
  return AppTheme.danger;
}

Color _barColor(int v) {
  if (v < 40) return AppTheme.success;
  if (v < 60) return const Color(0xFFFBBF24);
  if (v < 80) return AppTheme.stressColor;
  return AppTheme.danger;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class PressureScreen extends StatefulWidget {
  const PressureScreen({super.key});
  @override
  State<PressureScreen> createState() => _PressureScreenState();
}

class _PressureScreenState extends State<PressureScreen> {
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

  bool get _isToday {
    final n = DateTime.now();
    return _selectedDate.year == n.year &&
        _selectedDate.month == n.month &&
        _selectedDate.day == n.day;
  }

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

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
        final sums = List<int>.filled(24, 0);
        final counts = List<int>.filled(24, 0);
        for (final item in list) {
          final m = item as Map<String, dynamic>;
          final value = (m['value'] as num? ?? 0).toInt();
          final measuredAt = (m['measuredAt'] as num? ?? 0).toInt();
          if (value <= 0 || measuredAt <= 0) continue;
          final h = DateTime.fromMillisecondsSinceEpoch(measuredAt).hour;
          sums[h] += value;
          counts[h] += 1;
        }
        for (int h = 0; h < 24; h++) {
          if (counts[h] > 0) hourly[h] = (sums[h] / counts[h]).round();
        }
      } catch (_) {}

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
      final from = DateTime(date.year, date.month, date.day);
      final to = DateTime(date.year, date.month, date.day, 23, 59, 59);
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
      if (vals.isNotEmpty) {
        setState(() {
          _dayAvg = (vals.reduce((a, b) => a + b) / vals.length).round();
          _dayMin = vals.reduce((a, b) => a < b ? a : b);
          _dayMax = vals.reduce((a, b) => a > b ? a : b);
        });
      }
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
      final rows = await SupabaseService.getStressReadings(
        userId: user.id,
        from: now.subtract(const Duration(days: 6)),
        to: now,
      );
      // Group readings by day and compute daily averages
      final byDay = <String, List<int>>{};
      for (final r in rows) {
        final dt = DateTime.parse(r['measured_at'] as String).toLocal();
        final v = (r['stress_value'] as num? ?? 0).toInt();
        if (v > 0) byDay.putIfAbsent(_fmt(dt), () => []).add(v);
      }
      final vals = List.generate(7, (i) {
        final day = now.subtract(Duration(days: 6 - i));
        final dayVals = byDay[_fmt(day)];
        if (dayVals == null || dayVals.isEmpty) return 0;
        return (dayVals.reduce((a, b) => a + b) / dayVals.length).round();
      });
      final valid = vals.where((v) => v > 0).toList();
      if (!mounted) return;
      setState(() {
        _trendValues = vals;
        _trendMin = valid.isEmpty ? 0 : valid.reduce((a, b) => a < b ? a : b);
        _trendMax = valid.isEmpty ? 0 : valid.reduce((a, b) => a > b ? a : b);
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
      _manualStress = 0;
    });
    try {
      final result = await _ble.manualModePressure(start: true);
      if (!mounted) return;
      final m = jsonDecode(result) as Map<String, dynamic>;
      final v = (m['value'] as num? ?? 0).toInt();
      setState(() => _measuring = false);
      if (v > 0) {
        setState(() => _manualStress = v);
        await _saveMeasurement(v);
      }
    } catch (_) {
      if (mounted) setState(() => _measuring = false);
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
              shareScreenshot(_screenshotKey, text: 'My Stress — SUNDR'),
        ),
        GlassMenuItem(
          label: 'Note',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const VitalNoteScreen(
                title: 'Stress',
                heading: 'About Stress',
                intro:
                    'Your ring estimates stress from heart-rate variability — '
                    'how activated your nervous system is right now, not just '
                    'how you feel.',
                ranges: [
                  VitalRange(
                    label: 'Relaxed',
                    range: '0–39',
                    color: AppTheme.success,
                  ),
                  VitalRange(
                    label: 'Normal',
                    range: '40–59',
                    color: Color(0xFFFBBF24),
                  ),
                  VitalRange(
                    label: 'Elevated',
                    range: '60–79',
                    color: AppTheme.stressColor,
                  ),
                  VitalRange(
                    label: 'High',
                    range: '80–100',
                    color: AppTheme.danger,
                  ),
                ],
                tips: [
                  VitalTip(
                    icon: Icons.self_improvement_rounded,
                    color: AppTheme.success,
                    title: 'Lower it fast',
                    tip:
                        'A 2-minute slow-breathing break (4s in, 6s out) can '
                        'visibly bring down an elevated reading.',
                  ),
                  VitalTip(
                    icon: Icons.bedtime_rounded,
                    color: AppTheme.sleepColor,
                    title: 'Sleep debt shows up here',
                    tip:
                        'A poor night\'s sleep often reads as elevated '
                        'stress the next day, even on a calm one.',
                  ),
                ],
                didYouKnow:
                    'A brief spike during focused work isn\'t a problem — '
                    'it\'s staying elevated for hours that matters.',
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

    final currentValue = _measuring
        ? '···'
        : _manualStress > 0
        ? '$_manualStress'
        : _displayAvg > 0
        ? '$_displayAvg'
        : '--';

    final currentLabel = _measuring
        ? 'Measuring…'
        : _stressLabel(_manualStress > 0 ? _manualStress : _displayAvg);

    final currentLabelColor = _stressLevelColor(
      _manualStress > 0 ? _manualStress : _displayAvg,
    );

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
              _StressChartCard(
                headerLabel: hasData ? 'TODAY' : 'NO DATA YET',
                rangeLabel: hasData ? '$_displayMin - $_displayMax' : '-- --',
                values: _chartValues,
                xLabels: const ['12am', '6am', '12pm', '6pm'],
                loading: _loading || _loadingDay,
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
                    child: _StressStatCard(
                      label: 'AVERAGE',
                      value: _displayAvg > 0 ? '$_displayAvg' : '--',
                      level: _displayAvg,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StressStatCard(
                      label: 'MINIMUM',
                      value: _displayMin > 0 ? '$_displayMin' : '--',
                      level: _displayMin,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StressStatCard(
                      label: 'MAXIMUM',
                      value: _displayMax > 0 ? '$_displayMax' : '--',
                      level: _displayMax,
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
              const SizedBox(height: 20),

              // ── 7. 7-day trend ─────────────────────────────────────────────
              _StressChartCard(
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


// ── Stress Chart Card ─────────────────────────────────────────────────────────

class _StressChartCard extends StatelessWidget {
  final String headerLabel;
  final String rangeLabel;
  final List<int> values;
  final List<String> xLabels;
  final bool loading;
  final bool showLegend;

  const _StressChartCard({
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
          // Header row
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
          // Y-axis + chart
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
                    children: ['100', '75', '50', '25']
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
                            color: AppTheme.stressColor,
                            strokeWidth: 2,
                          ),
                        )
                      : CustomPaint(
                          painter: _StressBarPainter(values: values),
                          child: const SizedBox.expand(),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Day labels: equal-width slots centered under each bar.
          // Time-of-day labels: spaceBetween axis ticks.
          Padding(
            padding: const EdgeInsets.only(left: _yAxisW),
            child: xLabels.length == values.length &&
                    xLabels.isNotEmpty &&
                    xLabels.every((l) => l.isNotEmpty)
                ? Row(
                    children: [
                      for (final label in xLabels)
                        Expanded(
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: _inter(10, color: _kSec),
                          ),
                        ),
                    ],
                  )
                : Row(
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
                _LegendDot(color: AppTheme.success, label: 'Relaxed'),
                _LegendDot(color: Color(0xFFFBBF24), label: 'Normal'),
                _LegendDot(color: AppTheme.stressColor, label: 'Elevated'),
                _LegendDot(color: AppTheme.danger, label: 'High'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Stress Bar Painter ────────────────────────────────────────────────────────

class _StressBarPainter extends CustomPainter {
  final List<int> values;
  const _StressBarPainter({required this.values});

  static const _maxY = 100.0;
  static const _yLines = [100, 75, 50, 25];

  @override
  void paint(Canvas canvas, Size size) {
    // Horizontal grid lines
    final gridPaint = Paint()
      ..color = _kGrid
      ..strokeWidth = 0.5;
    for (final y in _yLines) {
      final yPos = size.height - (y / _maxY) * size.height;
      canvas.drawLine(Offset(0, yPos), Offset(size.width, yPos), gridPaint);
    }

    if (values.isEmpty) return;
    final n = values.length;
    final slotW = size.width / n;
    final barW = (slotW * 0.55).clamp(2.0, 9.0);

    for (int i = 0; i < n; i++) {
      if (values[i] <= 0) continue;
      final ratio = (values[i] / _maxY).clamp(0.0, 1.0);
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
        Paint()..color = _barColor(values[i]).withValues(alpha: 0.88),
      );
    }
  }

  @override
  bool shouldRepaint(_StressBarPainter old) => old.values != values;
}

// ── Stat card ─────────────────────────────────────────────────────────────────

class _StressStatCard extends StatelessWidget {
  final String label;
  final String value;
  final int level;

  const _StressStatCard({
    required this.label,
    required this.value,
    required this.level,
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
              Text(level > 0 ? '/100' : '--', style: _inter(11, color: _kSec)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            level > 0 ? _stressLabel(level) : '--',
            style: _inter(11, color: _stressLevelColor(level)),
          ),
        ],
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
                          color: enabled ? AppTheme.stressColor : _kSec,
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

// ── Legend dot ────────────────────────────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      CircleAvatar(radius: 3.5, backgroundColor: color),
      const SizedBox(width: 3),
      Text(label, style: _inter(10, color: _kSec)),
    ],
  );
}
