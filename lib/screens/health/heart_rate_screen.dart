import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';

// ── Local design tokens ───────────────────────────────────────────────────────

const _kCard    = Color(0xFF141414);
const _kBorder  = Color(0xFF242424);
const _kGrid    = Color(0xFF222222);
const _kSec     = Color(0xFF666666);
const _kSec2    = Color(0xFF888888);

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

// ── Screen ────────────────────────────────────────────────────────────────────

class HeartRateScreen extends StatefulWidget {
  const HeartRateScreen({super.key});
  @override
  State<HeartRateScreen> createState() => _HeartRateScreenState();
}

class _HeartRateScreenState extends State<HeartRateScreen> {
  final _ble = BleService();

  bool _loading       = false;
  bool _loadingDay    = false;
  bool _loadingTrend  = false;
  bool _measuring     = false;

  DateTime _selectedDate = DateTime.now();

  int _manualHr = 0;
  bool _settingEnabled  = true;
  int  _settingInterval = 5;

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

  int get _displayAvg => _isToday ? _avgHr : _dayAvg;
  int get _displayMin => _isToday ? _minHr : _dayMin;
  int get _displayMax => _isToday ? _maxHr : _dayMax;

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  // ── Init ──────────────────────────────────────────────────────────────────────

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

  // ── Date selection ────────────────────────────────────────────────────────────

  void _onDateSelected(DateTime date) {
    final n = DateTime.now();
    final isToday = date.year == n.year && date.month == n.month && date.day == n.day;
    setState(() {
      _selectedDate = date;
      _manualHr = 0;
      if (isToday) { _dayAvg = _dayMin = _dayMax = 0; }
    });
    if (!isToday) _loadDayFromSupabase(date);
  }

  // ── Ring fetch ────────────────────────────────────────────────────────────────

  Future<void> _fetchToday() async {
    setState(() { _loading = true; _manualHr = 0; });
    try {
      final data = await _ble.getTodayHeartRate();
      _parseHrData(data);
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _parseHrData(String jsonStr) {
    try {
      final m = jsonDecode(jsonStr) as Map<String, dynamic>;
      final offset = (m['offset'] as num? ?? 0).toInt();
      final raw = (m['e'] as List<dynamic>? ?? [])
          .map((v) => (v as num).toInt())
          .toList();
      final readings = raw.where((v) => v > 0).toList();
      if (readings.isEmpty) return;

      final avg = (readings.reduce((a, b) => a + b) / readings.length).round();
      final minVal = readings.reduce((a, b) => a < b ? a : b);
      final maxVal = readings.reduce((a, b) => a > b ? a : b);

      // Build a full-day array so each bar sits at its correct clock position.
      // Slot 0 = midnight; slot width = _settingInterval minutes.
      final totalSlots = 24 * 60 ~/ _settingInterval;
      final fullDay = List<int>.filled(totalSlots, 0);
      for (int i = 0; i < raw.length; i++) {
        final slot = offset + i;
        if (slot < totalSlots) fullDay[slot] = raw[i];
      }

      // Ring firmware pre-fills the entire day — zero out future slots.
      final nowMins = DateTime.now().hour * 60 + DateTime.now().minute;
      final currentSlot = nowMins ~/ _settingInterval;
      for (int i = currentSlot + 1; i < totalSlots; i++) {
        fullDay[i] = 0;
      }

      if (!mounted) return;
      setState(() {
        _chartValues = fullDay;
        _avgHr = avg;
        _minHr = minVal;
        _maxHr = maxVal;
        _selectedDate = DateTime.now();
      });

      context.read<BleProvider>().updateHrData(avg, minVal, maxVal);
      _saveHrToSupabase(avg, minVal, maxVal, readings.length);
    } catch (_) {}
  }

  Future<void> _saveHrToSupabase(int avg, int min, int max, int count) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.upsertHr(
        userId: user.id, date: DateTime.now(),
        avgHr: avg, minHr: min, maxHr: max, sampleCount: count,
      );
    } catch (_) {}
  }

  // ── Supabase fetches ──────────────────────────────────────────────────────────

  Future<void> _loadDayFromSupabase(DateTime date) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() => _loadingDay = true);
    try {
      final row = await SupabaseService.getHrForDate(user.id, date);
      if (!mounted) return;
      if (row != null) {
        setState(() {
          _dayAvg = (row['avg_hr'] as num? ?? 0).toInt();
          _dayMin = (row['min_hr'] as num? ?? 0).toInt();
          _dayMax = (row['max_hr'] as num? ?? 0).toInt();
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
      final now = DateTime.now();
      final rows = await SupabaseService.getHrHistory(
        userId: user.id,
        from: now.subtract(const Duration(days: 6)),
        to: now,
      );
      final vals = List.generate(7, (i) {
        final day = now.subtract(Duration(days: 6 - i));
        final row = rows.firstWhere((r) => r['date'] == _fmt(day), orElse: () => {});
        return (row['avg_hr'] as num? ?? 0).toInt();
      });
      final valid = rows.where((r) => r['min_hr'] != null).toList();
      if (!mounted) return;
      setState(() {
        _trendValues = vals;
        _trendMin = valid.isEmpty
            ? 0
            : valid.map((r) => (r['min_hr'] as num).toInt()).reduce((a, b) => a < b ? a : b);
        _trendMax = valid.isEmpty
            ? 0
            : valid.map((r) => (r['max_hr'] as num).toInt()).reduce((a, b) => a > b ? a : b);
      });
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingTrend = false);
    }
  }

  // ── Settings ──────────────────────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    if (!context.read<BleProvider>().isConnected) return;
    try {
      final json = await _ble.getHeartRateSetting();
      final m = jsonDecode(json);
      setState(() {
        _settingEnabled  = m['enable']   ?? true;
        _settingInterval = m['interval'] ?? 5;
      });
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      await _ble.setHeartRateSetting(enable: _settingEnabled, interval: _settingInterval);
    } catch (_) {}
  }

  Future<void> _startMeasurement() async {
    if (_measuring) return;
    setState(() { _measuring = true; _manualHr = 0; });
    try {
      final hr = await _ble.readHeartRate();
      if (!mounted) return;
      if (hr != null && hr > 0) {
        setState(() { _manualHr = hr; _measuring = false; });
        await _saveHrToSupabase(hr, hr, hr, 1);
      } else {
        setState(() => _measuring = false);
      }
    } catch (_) {
      if (mounted) setState(() => _measuring = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  List<String> _trendXLabels() {
    final now = DateTime.now();
    const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
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

    final hasData = _isToday && _chartValues.any((v) => v > 0);

    final dailyRangeLabel = hasData
        ? '$_displayMin - $_displayMax'
        : '-- --';

    final trendRangeLabel = _trendMin > 0 && _trendMax > 0
        ? '$_trendMin - $_trendMax BPM'
        : '-- -- BPM';

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
        title: Text('Heart Rate', style: _inter(17, weight: FontWeight.w600)),
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

            // ── 1. HR Detection toggle ─────────────────────────────────────
            _HRDetectionCard(
              enabled: _settingEnabled,
              onToggle: (v) {
                setState(() => _settingEnabled = v);
                _saveSettings();
              },
            ),
            const SizedBox(height: 20),

            // ── 2. Date row ────────────────────────────────────────────────
            _HRDateRow(
              selectedDate: _selectedDate,
              onDateSelected: _onDateSelected,
            ),
            const SizedBox(height: 22),

            // ── 3. Current HR value ────────────────────────────────────────
            Text(
              'CURRENT HEART RATE',
              style: _inter(11,
                  weight: FontWeight.w600,
                  color: AppTheme.gold,
                  letterSpacing: 1.2),
            ),
            const SizedBox(height: 2),
            Text(
              hrValue,
              style: _inter(52,
                  weight: FontWeight.w300,
                  color: Colors.white,
                  height: 1.1),
            ),
            Text(
              'bpm',
              style: _inter(13, color: _kSec),
            ),
            const SizedBox(height: 16),

            // ── 4. Daily chart ─────────────────────────────────────────────
            _HRChartCard(
              headerLabel: hasData ? 'TODAY' : 'NO DATA YET',
              rangeLabel: dailyRangeLabel,
              values: _isToday ? _chartValues : [],
              xLabels: const ['12am', '6am', '12pm', '6pm', ''],
              loading: _loading || _loadingDay,
            ),
            const SizedBox(height: 10),

            // ── 5. Stats row ───────────────────────────────────────────────
            Row(children: [
              Expanded(
                child: _HRStatCard(
                  label: 'AVERAGE',
                  value: _displayAvg > 0 ? '$_displayAvg' : '--',
                  unit:  _displayAvg > 0 ? 'bpm' : '--',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HRStatCard(
                  label: 'MINIMUM',
                  value: _displayMin > 0 ? '$_displayMin' : '--',
                  unit:  _displayMin > 0 ? 'bpm' : '--',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HRStatCard(
                  label: 'MAXIMUM',
                  value: _displayMax > 0 ? '$_displayMax' : '--',
                  unit:  _displayMax > 0 ? 'bpm' : '--',
                ),
              ),
            ]),
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
            const SizedBox(height: 10),

            // ── 8. Sleep ───────────────────────────────────────────────────
            
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

// ── Heart Rate Detection card ─────────────────────────────────────────────────

class _HRDetectionCard extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onToggle;
  const _HRDetectionCard({required this.enabled, required this.onToggle});

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
                Text('Heart Rate Detection',
                    style: _inter(15, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                Text(
                  'Start continuous heart rate measurement, '
                  'monitor it every 30 minutes, automatically hear...',
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

class _HRDateRow extends StatelessWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  const _HRDateRow({required this.selectedDate, required this.onDateSelected});

  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'
  ];

  @override
  Widget build(BuildContext context) {
    final now  = DateTime.now();
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
    final isToday  = d == today;
    final isFuture = d.isAfter(today);
    final sel = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
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
                    children: ['120', '100', '80', '60']
                        .map((l) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Text(l,
                                  style: _inter(10, color: _kSec)),
                            ))
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
          // X-axis labels (offset to align with chart area, not Y-axis)
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

// ── HR Bar Painter ────────────────────────────────────────────────────────────

class _HRBarPainter extends CustomPainter {
  final List<int> values;
  const _HRBarPainter({required this.values});

  static const _maxY   = 120.0;
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
    final barPaint = Paint()
      ..color = AppTheme.hrColor.withValues(alpha: 0.88);

    for (int i = 0; i < n; i++) {
      if (values[i] <= 0) continue;
      final ratio = (values[i] / _maxY).clamp(0.0, 1.0);
      final barH  = (ratio * size.height).clamp(2.0, size.height);
      final x     = i * slotW + (slotW - barW) / 2;
      canvas.drawRRect(
        RRect.fromLTRBR(
            x, size.height - barH, x + barW, size.height,
            const Radius.circular(3)),
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
              Text(value,
                  style: _inter(17, weight: FontWeight.w600)),
              const SizedBox(width: 4),
              Text(unit, style: _inter(11, color: _kSec)),
            ],
          ),
          const SizedBox(height: 6),
          Text('know more >',
              style: _inter(11, color: _kSec)),
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
              Text('Real Time Heart Rate',
                  style: _inter(14, weight: FontWeight.w500)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(hrText,
                      style: _inter(15,
                          weight: FontWeight.w600,
                          color: measuring || latestHr > 0
                              ? Colors.white
                              : _kSec2)),
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
                          color: enabled
                              ? AppTheme.hrColor
                              : _kSec,
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
