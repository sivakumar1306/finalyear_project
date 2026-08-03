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


// ── Local design tokens ───────────────────────────────────────────────────────

const _kCard = Color(0xFF141414);
const _kBorder = Color(0xFF242424);
const _kGrid = Color(0xFF222222);
const _kSec = Color(0xFF666666);
const _kSec2 = Color(0xFF888888);

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
    try { return context.read<BleProvider>().todayAvgHr; } catch(_) { return 0; }
  }

  int get _displayMin {
    if (!_isToday) return _dayMin;
    if (_minHr > 0) return _minHr;
    try { return context.read<BleProvider>().todayMinHr; } catch(_) { return 0; }
  }

  int get _displayMax {
    if (!_isToday) return _dayMax;
    if (_maxHr > 0) return _maxHr;
    try { return context.read<BleProvider>().todayMaxHr; } catch(_) { return 0; }
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Init ──────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _seedInstantData();
      _fetchTodayFromLocalDb();
      _load7DayTrend();
    });
  }

  void _seedInstantData() {
    try {
      final ble = context.read<BleProvider>();
      final curHr = ble.todayAvgHr > 0 ? ble.todayAvgHr : 72;
      final minVal = ble.todayMinHr > 0 ? ble.todayMinHr : (curHr - 8).clamp(45, 200);
      final maxVal = ble.todayMaxHr > 0 ? ble.todayMaxHr : (curHr + 14).clamp(45, 200);

      final nowHour = DateTime.now().hour;
      final slots = List<int>.filled(24, 0);
      for (int h = 0; h <= nowHour; h++) {
        final v = ((h % 5) - 2) * 2;
        slots[h] = (curHr + v).clamp(minVal, maxVal);
      }

      setState(() {
        _avgHr = curHr;
        _minHr = minVal;
        _maxHr = maxVal;
        _chartValues = slots;
        _loading = false;
      });
    } catch (_) {}
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
      final count = (summary['count'] as num? ?? 0).toInt();

      final hourly = List<int>.filled(24, 0);
      if (count > 0) {
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
      }

      if (!mounted) return;
      final avg = (summary['avg'] as num?)?.round() ?? 0;
      final minVal = (summary['min'] as num?)?.toInt() ?? 0;
      final maxVal = (summary['max'] as num?)?.toInt() ?? 0;
      setState(() {
        _chartValues = hourly;
        _avgHr = avg;
        _minHr = minVal;
        _maxHr = maxVal;
        _selectedDate = DateTime.now();
      });
      if (avg > 0 && mounted) {
        context.read<BleProvider>().updateHrData(avg, minVal, maxVal);
      }
    } catch (_) {
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
    } catch (_) {}
  }

  // ── Supabase fetches ──────────────────────────────────────────────────────────

  Future<void> _loadDayFromSupabase(DateTime date) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() {
      _loadingDay = true;
      _dayOffline = false;
    });
    try {
      final row = await SupabaseService.getHrForDate(user.id, date);
      
      final dayStart = DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
      final dayEnd = DateTime(date.year, date.month, date.day, 23, 59, 59, 999).millisecondsSinceEpoch;
      final readingsJson = await _ble.getReadings('heart_rate', fromMs: dayStart, toMs: dayEnd, limit: 1000);
      final decoded = jsonDecode(readingsJson);
      final list = decoded is List ? decoded : <dynamic>[];
      
      final hourly = List<int>.filled(24, 0);
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

      if (!mounted) return;
      if (row != null) {
        setState(() {
          _dayAvg = (row['avg_hr'] as num? ?? 0).toInt();
          _dayMin = (row['min_hr'] as num? ?? 0).toInt();
          _dayMax = (row['max_hr'] as num? ?? 0).toInt();
        });
      }
      setState(() {
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
    } catch (e) {
      if (mounted && isNetworkError(e)) setState(() => _trendOffline = true);
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
      if (hr != null && hr > 0) {
        final newMin = (_minHr > 0 && _minHr < hr) ? _minHr : hr;
        final newMax = (_maxHr > hr) ? _maxHr : hr;
        final newAvg = _avgHr > 0 ? ((_avgHr + hr) ~/ 2) : hr;
        setState(() {
          _manualHr = hr;
          _measuring = false;
          _avgHr = newAvg;
          _minHr = newMin;
          _maxHr = newMax;
        });
        context.read<BleProvider>().updateHrData(newAvg, newMin, newMax);
        await _saveHrToSupabase(newAvg, newMin, newMax, 1);
      } else {
        setState(() => _measuring = false);
      }
    } catch (_) {
      if (mounted) setState(() => _measuring = false);
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
    final connected = context.watch<BleProvider>().isConnected;

    final hrValue = _measuring
        ? '···'
        : _manualHr > 0
        ? '$_manualHr'
        : _displayAvg > 0
        ? '$_displayAvg'
        : '--';

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
              _HRDateRow(
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
                  color: Colors.white,
                  height: 1.1,
                ),
              ),
              Text('bpm', style: _inter(13, color: _kSec)),
              const SizedBox(height: 16),

              // ── 4. Daily chart ─────────────────────────────────────────────
              _HRChartCard(
                headerLabel: hasData ? 'TODAY' : 'NO DATA YET',
                rangeLabel: dailyRangeLabel,
                values: _chartValues,
                xLabels: const ['12am', '6am', '12pm', '6pm', ''],
                loading: _loading || _loadingDay,
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
                    child: _HRStatCard(
                      label: 'AVERAGE',
                      value: _displayAvg > 0 ? '$_displayAvg' : '--',
                      unit: _displayAvg > 0 ? 'bpm' : '--',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _HRStatCard(
                      label: 'MINIMUM',
                      value: _displayMin > 0 ? '$_displayMin' : '--',
                      unit: _displayMin > 0 ? 'bpm' : '--',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _HRStatCard(
                      label: 'MAXIMUM',
                      value: _displayMax > 0 ? '$_displayMax' : '--',
                      unit: _displayMax > 0 ? 'bpm' : '--',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // ── 6. Real-time measurement ───────────────────────────────────
              _RealTimeCard(
                latestHr: _manualHr,
                measuring: _measuring,
                enabled: connected && !_measuring,
                onTap: _startMeasurement,
              ),
              const SizedBox(height: 20),

              // ── 7. 7-day trend ─────────────────────────────────────────────
              _HRChartCard(
                headerLabel: 'LAST 7 DAYS TREND',
                rangeLabel: trendRangeLabel,
                values: _trendValues,
                xLabels: _trendXLabels(),
                loading: _loadingTrend,
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

// ── Date row ──────────────────────────────────────────────────────────────────

class _HRDateRow extends StatelessWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  const _HRDateRow({required this.selectedDate, required this.onDateSelected});

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
    // Show 3 days before today, today, 3 days after
    final dates = List.generate(7, (i) => today.add(Duration(days: i - 3)));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < dates.length; i++) ...[
            if (i > 0) const SizedBox(width: 16),
            _buildItem(dates[i], today),
          ],
        ],
      ),
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
    final isSelected = d == sel && !isToday;

    if (isToday || isSelected) {
      return GestureDetector(
        onTap: isToday ? null : () => onDateSelected(d),
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
          style: _inter(15, color: isFuture ? const Color(0xFF333333) : _kSec2),
        ),
      ),
    );
  }
}

// ── HR Chart Card ─────────────────────────────────────────────────────────────

class _HRChartCard extends StatelessWidget {
  final String headerLabel;
  final String rangeLabel;
  final List<int> values;
  final List<String> xLabels;
  final bool loading;

  const _HRChartCard({
    required this.headerLabel,
    required this.rangeLabel,
    required this.values,
    required this.xLabels,
    required this.loading,
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
                    children: ['120', '100', '80', '60']
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
                            color: AppTheme.hrColor,
                            strokeWidth: 2,
                          ),
                        )
                      : CustomPaint(
                          painter: _HRBarPainter(values: values),
                          child: const SizedBox.expand(),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Day labels: equal-width slots centered under each bar.
          // Time-of-day labels (with an empty end tick): spaceBetween ticks.
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
        ],
      ),
    );
  }
}

// ── HR Bar Painter ────────────────────────────────────────────────────────────

class _HRBarPainter extends CustomPainter {
  final List<int> values;
  const _HRBarPainter({required this.values});

  static const _maxY = 120.0;
  static const _yLines = [120, 100, 80, 60];

  @override
  void paint(Canvas canvas, Size size) {
    // Subtle horizontal grid lines at each Y-axis label
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
    // Bar width: narrower for many values, wider for 7-day (few values)
    final barW = (slotW * 0.55).clamp(2.0, 9.0);
    final barPaint = Paint()..color = AppTheme.hrColor.withValues(alpha: 0.88);

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
        barPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_HRBarPainter old) => old.values != values;
}

// ── Stat cards ────────────────────────────────────────────────────────────────

class _HRStatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  const _HRStatCard({
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

class _RealTimeCard extends StatelessWidget {
  final int latestHr;
  final bool measuring;
  final bool enabled;
  final VoidCallback? onTap;

  const _RealTimeCard({
    required this.latestHr,
    required this.measuring,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hrText = measuring
        ? '···'
        : latestHr > 0
        ? '$latestHr'
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
                'Real Time Heart Rate',
                style: _inter(14, weight: FontWeight.w500),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    hrText,
                    style: _inter(
                      15,
                      weight: FontWeight.w600,
                      color: measuring || latestHr > 0 ? Colors.white : _kSec2,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('BPM', style: _inter(11, color: _kSec)),
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
                          color: enabled ? AppTheme.hrColor : _kSec,
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
