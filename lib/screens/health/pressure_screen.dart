import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';

// ── Local design tokens ───────────────────────────────────────────────────────

const _kCard   = Color(0xFF141414);
const _kBorder = Color(0xFF242424);
const _kGrid   = Color(0xFF222222);
const _kSec    = Color(0xFF666666);
const _kSec2   = Color(0xFF888888);

TextStyle _inter(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = Colors.white,
  double? letterSpacing,
  double? height,
}) =>
    GoogleFonts.inter(
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

  bool _loading      = false;
  bool _loadingDay   = false;
  bool _loadingTrend = false;
  bool _measuring    = false;

  DateTime _selectedDate = DateTime.now();

  int  _manualStress   = 0;
  bool _settingEnabled = true;

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

  int get _displayAvg => _isToday ? _avgStress : _dayAvg;
  int get _displayMin => _isToday ? _minStress : _dayMin;
  int get _displayMax => _isToday ? _maxStress : _dayMax;

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Init ──────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.read<BleProvider>().isConnected) {
        _fetchToday();
      }
      _load7DayTrend();
    });
  }

  // ── Date selection ────────────────────────────────────────────────────────

  void _onDateSelected(DateTime date) {
    final n = DateTime.now();
    final isToday = date.year == n.year &&
        date.month == n.month &&
        date.day == n.day;
    setState(() {
      _selectedDate = date;
      _manualStress = 0;
      if (isToday) { _dayAvg = _dayMin = _dayMax = 0; }
    });
    if (!isToday) _loadDayFromSupabase(date);
  }

  // ── Ring fetch ────────────────────────────────────────────────────────────

  Future<void> _fetchToday() async {
    setState(() { _loading = true; _manualStress = 0; });
    try {
      final data = await _ble.getTodayPressure();
      _parsePressureData(data);
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _parsePressureData(String jsonStr) {
    try {
      final m = jsonDecode(jsonStr) as Map<String, dynamic>;
      final raw = (m['pressureArray'] as List<dynamic>? ?? [])
          .map((v) => (v as num).toInt())
          .toList();
      final readings = raw.where((v) => v > 0).toList();
      if (readings.isEmpty) return;

      final avg = (readings.reduce((a, b) => a + b) / readings.length).round();
      final minVal = readings.reduce((a, b) => a < b ? a : b);
      final maxVal = readings.reduce((a, b) => a > b ? a : b);

      if (!mounted) return;
      setState(() {
        _chartValues = raw;
        _avgStress   = avg;
        _minStress   = minVal;
        _maxStress   = maxVal;
        _selectedDate = DateTime.now();
      });

      context.read<BleProvider>().updateStressLatest(avg);
      _saveRingDataToSupabase(avg);
    } catch (_) {}
  }

  Future<void> _saveRingDataToSupabase(int avgValue) async {
    final user = SupabaseService.currentUser;
    if (user == null || avgValue <= 0) return;
    try {
      final now  = DateTime.now();
      final from = DateTime(now.year, now.month, now.day);
      final to   = DateTime(now.year, now.month, now.day, 23, 59, 59);
      final existing = await SupabaseService.getStressReadings(
        userId: user.id, from: from, to: to);
      final hasRingData = existing.any((r) => r['source'] == 'ring');
      if (!hasRingData) {
        await SupabaseService.insertStress(
          userId: user.id,
          stressValue: avgValue,
          measuredAt: now,
          source: 'ring',
        );
      }
    } catch (_) {}
  }

  // ── Supabase fetches ──────────────────────────────────────────────────────

  Future<void> _loadDayFromSupabase(DateTime date) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() => _loadingDay = true);
    try {
      final from = DateTime(date.year, date.month, date.day);
      final to   = DateTime(date.year, date.month, date.day, 23, 59, 59);
      final rows = await SupabaseService.getStressReadings(
        userId: user.id, from: from, to: to);
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
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingDay = false);
    }
  }

  Future<void> _load7DayTrend() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() => _loadingTrend = true);
    try {
      final now  = DateTime.now();
      final rows = await SupabaseService.getStressReadings(
        userId: user.id,
        from: now.subtract(const Duration(days: 6)),
        to: now,
      );
      // Group readings by day and compute daily averages
      final byDay = <String, List<int>>{};
      for (final r in rows) {
        final dt = DateTime.parse(r['measured_at'] as String).toLocal();
        final v  = (r['stress_value'] as num? ?? 0).toInt();
        if (v > 0) byDay.putIfAbsent(_fmt(dt), () => []).add(v);
      }
      final vals = List.generate(7, (i) {
        final day     = now.subtract(Duration(days: 6 - i));
        final dayVals = byDay[_fmt(day)];
        if (dayVals == null || dayVals.isEmpty) return 0;
        return (dayVals.reduce((a, b) => a + b) / dayVals.length).round();
      });
      final valid = vals.where((v) => v > 0).toList();
      if (!mounted) return;
      setState(() {
        _trendValues = vals;
        _trendMin    = valid.isEmpty ? 0 : valid.reduce((a, b) => a < b ? a : b);
        _trendMax    = valid.isEmpty ? 0 : valid.reduce((a, b) => a > b ? a : b);
      });
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingTrend = false);
    }
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    if (!context.read<BleProvider>().isConnected) return;
    try {
      final json = await _ble
          .getPressureSetting()
          .timeout(const Duration(seconds: 5));
      final m = jsonDecode(json) as Map<String, dynamic>;
      if (mounted) setState(() => _settingEnabled = (m['enable'] as bool?) ?? true);
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      await _ble.setPressureSetting(enable: _settingEnabled);
    } catch (_) {}
  }

  // ── Manual measurement ────────────────────────────────────────────────────

  Future<void> _startMeasurement() async {
    if (_measuring) return;
    setState(() { _measuring = true; _manualStress = 0; });
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

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<String> _trendXLabels() {
    final now  = DateTime.now();
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
        _manualStress > 0 ? _manualStress : _displayAvg);

    final hasData = _isToday && _chartValues.any((v) => v > 0);

    final trendRangeLabel = _trendMin > 0 && _trendMax > 0
        ? '$_trendMin - $_trendMax'
        : '-- --';

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Stress', style: _inter(17, weight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () {},
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

            // ── 1. Stress Detection toggle ─────────────────────────────────
            _StressDetectionCard(
              enabled: _settingEnabled,
              onToggle: (v) {
                setState(() => _settingEnabled = v);
                _saveSettings();
              },
            ),
            const SizedBox(height: 20),

            // ── 2. Date row ────────────────────────────────────────────────
            _StressDateRow(
              selectedDate: _selectedDate,
              onDateSelected: _onDateSelected,
            ),
            const SizedBox(height: 22),

            // ── 3. Current stress value ────────────────────────────────────
            Text(
              'CURRENT STRESS LEVEL',
              style: _inter(11,
                  weight: FontWeight.w600,
                  color: AppTheme.gold,
                  letterSpacing: 1.2),
            ),
            const SizedBox(height: 2),
            Text(
              currentValue,
              style: _inter(52,
                  weight: FontWeight.w300,
                  color: Colors.white,
                  height: 1.1),
            ),
            Text(
              currentLabel,
              style: _inter(13, color: currentLabelColor),
            ),
            const SizedBox(height: 16),

            // ── 4. Daily chart ─────────────────────────────────────────────
            _StressChartCard(
              headerLabel: hasData ? 'TODAY' : 'NO DATA YET',
              rangeLabel: hasData
                  ? '$_displayMin - $_displayMax'
                  : '-- --',
              values: _isToday ? _chartValues : [],
              xLabels: const ['12am', '6am', '12pm', '6pm'],
              loading: _loading || _loadingDay,
            ),
            const SizedBox(height: 10),

            // ── 5. Stats row ───────────────────────────────────────────────
            Row(children: [
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
            ]),
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
            ),
            const SizedBox(height: 12),

            // ── 8. Legend ──────────────────────────────────────────────────
            Row(children: [
              _LegendDot(color: AppTheme.success, label: 'Relaxed'),
              const SizedBox(width: 10),
              _LegendDot(color: const Color(0xFFFBBF24), label: 'Normal'),
              const SizedBox(width: 10),
              _LegendDot(color: AppTheme.stressColor, label: 'Elevated'),
              const SizedBox(width: 10),
              _LegendDot(color: AppTheme.danger, label: 'High'),
            ]),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

// ── Stress Detection card ─────────────────────────────────────────────────────

class _StressDetectionCard extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onToggle;
  const _StressDetectionCard({required this.enabled, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Stress Detection',
                    style: _inter(15, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                Text(
                  'Enable continuous stress monitoring. '
                  'The ring tracks your stress levels throughout the day automatically.',
                  style: _inter(12, color: _kSec2, height: 1.45),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            onChanged: onToggle,
          ),
        ],
      ),
    );
  }
}

// ── Date row ──────────────────────────────────────────────────────────────────

class _StressDateRow extends StatelessWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  const _StressDateRow({required this.selectedDate, required this.onDateSelected});

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  Widget build(BuildContext context) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
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
    final isToday    = d == today;
    final isFuture   = d.isAfter(today);
    final sel        = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
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
          style: _inter(15,
              color: isFuture ? const Color(0xFF333333) : _kSec2),
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

  const _StressChartCard({
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
              Text(headerLabel,
                  style: _inter(11,
                      weight: FontWeight.w600,
                      color: _kSec,
                      letterSpacing: 0.6)),
              Text(rangeLabel,
                  style: _inter(11,
                      weight: FontWeight.w500,
                      color: const Color(0xFF999999))),
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
                        .map((l) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Text(l, style: _inter(10, color: _kSec)),
                            ))
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
          // X-axis labels (offset to align with chart area)
          Padding(
            padding: const EdgeInsets.only(left: _yAxisW),
            child: Row(
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

// ── Stress Bar Painter ────────────────────────────────────────────────────────

class _StressBarPainter extends CustomPainter {
  final List<int> values;
  const _StressBarPainter({required this.values});

  static const _maxY   = 100.0;
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
    final n    = values.length;
    final slotW = size.width / n;
    final barW  = (slotW * 0.55).clamp(2.0, 9.0);

    for (int i = 0; i < n; i++) {
      if (values[i] <= 0) continue;
      final ratio = (values[i] / _maxY).clamp(0.0, 1.0);
      final barH  = (ratio * size.height).clamp(2.0, size.height);
      final x     = i * slotW + (slotW - barW) / 2;
      canvas.drawRRect(
        RRect.fromLTRBR(
            x, size.height - barH, x + barW, size.height,
            const Radius.circular(3)),
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
          Text(label,
              style: _inter(10,
                  weight: FontWeight.w600,
                  color: _kSec,
                  letterSpacing: 0.7)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: _inter(17, weight: FontWeight.w600)),
              const SizedBox(width: 4),
              Text(level > 0 ? '/100' : '--',
                  style: _inter(11, color: _kSec)),
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
              Text('Real Time Stress',
                  style: _inter(14, weight: FontWeight.w500)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    stressText,
                    style: _inter(15,
                        weight: FontWeight.w600,
                        color: measuring || latestStress > 0
                            ? Colors.white
                            : _kSec2),
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
                        style: _inter(14,
                            weight: FontWeight.w500,
                            color: enabled ? Colors.white70 : _kSec),
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
