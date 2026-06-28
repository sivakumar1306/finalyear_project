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

// ── Screen ────────────────────────────────────────────────────────────────────

class BloodOxygenScreen extends StatefulWidget {
  const BloodOxygenScreen({super.key});
  @override
  State<BloodOxygenScreen> createState() => _BloodOxygenScreenState();
}

class _BloodOxygenScreenState extends State<BloodOxygenScreen> {
  final _ble = BleService();

  bool _loading       = false;
  bool _loadingDay    = false;
  bool _loadingTrend  = false;
  bool _measuring     = false;

  DateTime _selectedDate = DateTime.now();

  int _manualSpo2 = 0;
  bool _settingEnabled  = true;
  int  _settingInterval = 5;

  // Today's ring data
  List<int> _chartValues = [];
  int _avgSpo2 = 0, _minSpo2 = 0, _maxSpo2 = 0;

  // Past-day Supabase data
  int _dayAvg = 0, _dayMin = 0, _dayMax = 0;

  // 7-day trend (always loaded on open)
  List<int> _trendValues = [];
  int _trendMin = 0, _trendMax = 0;

  // ── Computed ──────────────────────────────────────────────────────────────

  bool get _isToday {
    final n = DateTime.now();
    return _selectedDate.year == n.year &&
        _selectedDate.month == n.month &&
        _selectedDate.day == n.day;
  }

  int get _displayAvg => _isToday ? _avgSpo2 : _dayAvg;
  int get _displayMin => _isToday ? _minSpo2 : _dayMin;
  int get _displayMax => _isToday ? _maxSpo2 : _dayMax;

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
    final isToday = date.year == n.year && date.month == n.month && date.day == n.day;
    setState(() {
      _selectedDate = date;
      _manualSpo2 = 0;
      if (isToday) { _dayAvg = _dayMin = _dayMax = 0; }
    });
    if (!isToday) _loadDayFromSupabase(date);
  }

  // ── Ring fetch ────────────────────────────────────────────────────────────

  Future<void> _fetchToday() async {
    setState(() { _loading = true; _manualSpo2 = 0; });
    try {
      final data = await _ble.getTodayBloodOxygen();
      _parseSpo2Data(data);
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _parseSpo2Data(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded == null || decoded is! Map<String, dynamic>) return;

      final offset = (decoded['offset'] as num? ?? 0).toInt();
      final maxRaw = (decoded['maxArray'] as List<dynamic>? ?? [])
          .map((v) => (v as num).toInt())
          .toList();
      final minRaw = (decoded['minArray'] as List<dynamic>? ?? [])
          .map((v) => (v as num).toInt())
          .toList();

      // Build full 24-slot array placed at correct clock positions.
      const totalSlots = 24;
      final fullDay = List<int>.filled(totalSlots, 0);
      for (int i = 0; i < maxRaw.length; i++) {
        final slot = offset + i;
        if (slot < totalSlots) fullDay[slot] = maxRaw[i];
      }

      // Ring firmware pre-fills entire day — zero out future slots.
      final currentSlot = DateTime.now().hour;
      for (int i = currentSlot + 1; i < totalSlots; i++) {
        fullDay[i] = 0;
      }

      final readings = fullDay.where((v) => v > 0).toList();
      if (readings.isEmpty) return;

      final avg = (readings.reduce((a, b) => a + b) / readings.length).round();
      final maxVal = readings.reduce((a, b) => a > b ? a : b);

      // Use minArray for min reading
      final minFull = List<int>.filled(totalSlots, 0);
      for (int i = 0; i < minRaw.length; i++) {
        final slot = offset + i;
        if (slot < totalSlots) minFull[slot] = minRaw[i];
      }
      for (int i = currentSlot + 1; i < totalSlots; i++) {
        minFull[i] = 0;
      }
      final minReadings = minFull.where((v) => v > 0).toList();
      final minVal = minReadings.isNotEmpty
          ? minReadings.reduce((a, b) => a < b ? a : b)
          : readings.reduce((a, b) => a < b ? a : b);

      if (!mounted) return;
      setState(() {
        _chartValues  = fullDay;
        _avgSpo2 = avg;
        _minSpo2 = minVal;
        _maxSpo2 = maxVal;
        _selectedDate = DateTime.now();
      });

      context.read<BleProvider>().updateSpo2Data(avg, minVal, maxVal);
      _saveToSupabase(avg, minVal, maxVal, readings.length);
    } catch (_) {}
  }

  Future<void> _saveToSupabase(int avg, int min, int max, int count) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.upsertSpo2(
        userId: user.id,
        date: DateTime.now(),
        avgSpo2: avg,
        minSpo2: min,
        maxSpo2: max,
        sampleCount: count,
      );
    } catch (_) {}
  }

  // ── Supabase fetches ──────────────────────────────────────────────────────

  Future<void> _loadDayFromSupabase(DateTime date) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() => _loadingDay = true);
    try {
      final row = await SupabaseService.getSpo2ForDate(user.id, date);
      if (!mounted) return;
      if (row != null) {
        setState(() {
          _dayAvg = (row['avg_spo2'] as num? ?? 0).toInt();
          _dayMin = (row['min_spo2'] as num? ?? 0).toInt();
          _dayMax = (row['max_spo2'] as num? ?? 0).toInt();
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
      final rows = await SupabaseService.getSpo2History(
        userId: user.id,
        from: now.subtract(const Duration(days: 6)),
        to: now,
      );
      final vals = List.generate(7, (i) {
        final day = now.subtract(Duration(days: 6 - i));
        final row = rows.firstWhere((r) => r['date'] == _fmt(day), orElse: () => {});
        return (row['avg_spo2'] as num? ?? 0).toInt();
      });
      final valid = rows.where((r) => r['min_spo2'] != null).toList();
      if (!mounted) return;
      setState(() {
        _trendValues = vals;
        _trendMin = valid.isEmpty
            ? 0
            : valid.map((r) => (r['min_spo2'] as num).toInt()).reduce((a, b) => a < b ? a : b);
        _trendMax = valid.isEmpty
            ? 0
            : valid.map((r) => (r['max_spo2'] as num).toInt()).reduce((a, b) => a > b ? a : b);
      });
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingTrend = false);
    }
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    if (!context.read<BleProvider>().isConnected) return;
    try {
      final json = await _ble.getBloodOxygenSetting();
      final m = jsonDecode(json);
      setState(() {
        _settingEnabled  = m['enable']   ?? true;
        _settingInterval = m['interval'] ?? 5;
      });
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      await _ble.setBloodOxygenSetting(enable: _settingEnabled, interval: _settingInterval);
    } catch (_) {}
  }

  Future<void> _startMeasurement() async {
    if (_measuring) return;
    setState(() { _measuring = true; _manualSpo2 = 0; });
    try {
      final result = await _ble.manualModeBloodOxygen(start: true);
      int liveVal = 0;
      try {
        final m = jsonDecode(result) as Map<String, dynamic>;
        liveVal = (m['spo2'] as num?)?.toInt() ?? 0;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _measuring = false;
        if (liveVal > 0) _manualSpo2 = liveVal;
      });
      if (liveVal > 0) await _saveSingleMeasurement(liveVal);
    } catch (_) {
      if (mounted) setState(() => _measuring = false);
    }
  }

  Future<void> _saveSingleMeasurement(int spo2) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      final existing = await SupabaseService.getSpo2ForDate(user.id, DateTime.now());
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
    } catch (_) {}
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

    final spo2Value = _measuring
        ? '···'
        : _manualSpo2 > 0
            ? '$_manualSpo2'
            : _displayAvg > 0
                ? '$_displayAvg'
                : '--';

    final hasData = _isToday && _chartValues.any((v) => v > 0);

    final dailyRangeLabel = hasData
        ? '$_displayMin – $_displayMax'
        : '-- --';

    final trendRangeLabel = _trendMin > 0 && _trendMax > 0
        ? '$_trendMin – $_trendMax %'
        : '-- -- %';

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
        title: Text('Blood Oxygen', style: _inter(17, weight: FontWeight.w600)),
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

            // ── 1. SpO₂ Detection toggle ───────────────────────────────────
            _Spo2DetectionCard(
              enabled: _settingEnabled,
              interval: _settingInterval,
              onToggle: (v) {
                setState(() => _settingEnabled = v);
                _saveSettings();
              },
              onIntervalChanged: (v) {
                setState(() => _settingInterval = v);
                _saveSettings();
              },
            ),
            const SizedBox(height: 20),

            // ── 2. Date row ────────────────────────────────────────────────
            _Spo2DateRow(
              selectedDate: _selectedDate,
              onDateSelected: _onDateSelected,
            ),
            const SizedBox(height: 22),

            // ── 3. Current SpO₂ value ──────────────────────────────────────
            Text(
              'CURRENT BLOOD OXYGEN',
              style: _inter(11,
                  weight: FontWeight.w600,
                  color: AppTheme.spo2Color,
                  letterSpacing: 1.2),
            ),
            const SizedBox(height: 2),
            Text(
              spo2Value,
              style: _inter(52,
                  weight: FontWeight.w300,
                  color: Colors.white,
                  height: 1.1),
            ),
            Text(
              '%',
              style: _inter(13, color: _kSec),
            ),
            const SizedBox(height: 16),

            // ── 4. Daily chart ─────────────────────────────────────────────
            _Spo2ChartCard(
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
                child: _Spo2StatCard(
                  label: 'AVERAGE',
                  value: _displayAvg > 0 ? '$_displayAvg' : '--',
                  unit:  _displayAvg > 0 ? '%' : '--',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Spo2StatCard(
                  label: 'MINIMUM',
                  value: _displayMin > 0 ? '$_displayMin' : '--',
                  unit:  _displayMin > 0 ? '%' : '--',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Spo2StatCard(
                  label: 'MAXIMUM',
                  value: _displayMax > 0 ? '$_displayMax' : '--',
                  unit:  _displayMax > 0 ? '%' : '--',
                ),
              ),
            ]),
            const SizedBox(height: 10),

            // ── 6. Real-time measurement ───────────────────────────────────
            _RealTimeCard(
              latestSpo2: _manualSpo2,
              measuring: _measuring,
              enabled: connected && !_measuring,
              onTap: _startMeasurement,
            ),
            const SizedBox(height: 20),

            // ── 7. 7-day trend ─────────────────────────────────────────────
            _Spo2ChartCard(
              headerLabel: 'LAST 7 DAYS TREND',
              rangeLabel: trendRangeLabel,
              values: _trendValues,
              xLabels: _trendXLabels(),
              loading: _loadingTrend,
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

// ── SpO₂ Detection card ───────────────────────────────────────────────────────

class _Spo2DetectionCard extends StatelessWidget {
  final bool enabled;
  final int interval;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onIntervalChanged;

  const _Spo2DetectionCard({
    required this.enabled,
    required this.interval,
    required this.onToggle,
    required this.onIntervalChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Blood Oxygen Detection',
                        style: _inter(15, weight: FontWeight.w600)),
                    const SizedBox(height: 5),
                    Text(
                      'Automatically monitor SpO₂ throughout the day at set intervals.',
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
          if (enabled) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text('Interval', style: _inter(13, color: _kSec2)),
                const Spacer(),
                DropdownButton<int>(
                  value: interval,
                  dropdownColor: const Color(0xFF1A1A1A),
                  style: _inter(13),
                  underline: const SizedBox(),
                  items: [1, 5, 10, 15, 30]
                      .map((e) => DropdownMenuItem(value: e, child: Text('$e min')))
                      .toList(),
                  onChanged: (v) { if (v != null) onIntervalChanged(v); },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Date row ──────────────────────────────────────────────────────────────────

class _Spo2DateRow extends StatelessWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  const _Spo2DateRow({required this.selectedDate, required this.onDateSelected});

  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'
  ];

  @override
  Widget build(BuildContext context) {
    final now  = DateTime.now();
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
          style: _inter(15, color: isFuture ? const Color(0xFF333333) : _kSec2),
        ),
      ),
    );
  }
}

// ── SpO₂ Chart Card ───────────────────────────────────────────────────────────

class _Spo2ChartCard extends StatelessWidget {
  final String headerLabel;
  final String rangeLabel;
  final List<int> values;
  final List<String> xLabels;
  final bool loading;

  const _Spo2ChartCard({
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
                    children: ['100', '97', '94', '85']
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
                            color: AppTheme.spo2Color,
                            strokeWidth: 2,
                          ),
                        )
                      : CustomPaint(
                          painter: _SpO2BarPainter(values: values),
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
        ],
      ),
    );
  }
}

// ── SpO₂ bar chart painter ────────────────────────────────────────────────────

class _SpO2BarPainter extends CustomPainter {
  final List<int> values;
  static const double _baseline = 85.0;
  static const double _range    = 15.0; // 85–100

  const _SpO2BarPainter({required this.values});

  static const _yLines = [100, 97, 94, 85];

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = _kGrid
      ..strokeWidth = 0.5;
    for (final y in _yLines) {
      final yPos = size.height - ((y - _baseline) / _range) * size.height;
      canvas.drawLine(Offset(0, yPos), Offset(size.width, yPos), gridPaint);
    }

    if (values.isEmpty) return;
    final n = values.length;
    final slotW = size.width / n;
    final barW  = (slotW * 0.55).clamp(2.0, 9.0);
    final barPaint = Paint()
      ..color = AppTheme.spo2Color.withValues(alpha: 0.88);

    for (int i = 0; i < n; i++) {
      if (values[i] <= 0) continue;
      final normalized = ((values[i] - _baseline) / _range).clamp(0.0, 1.0);
      final barH = (normalized * size.height).clamp(2.0, size.height);
      final x = i * slotW + (slotW - barW) / 2;
      canvas.drawRRect(
        RRect.fromLTRBR(
            x, size.height - barH, x + barW, size.height,
            const Radius.circular(3)),
        barPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_SpO2BarPainter old) => old.values != values;
}

// ── Stat cards ────────────────────────────────────────────────────────────────

class _Spo2StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _Spo2StatCard({
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
              Text(value, style: _inter(17, weight: FontWeight.w600)),
              const SizedBox(width: 4),
              Text(unit, style: _inter(11, color: _kSec)),
            ],
          ),
          const SizedBox(height: 6),
          Text('know more >', style: _inter(11, color: _kSec)),
        ],
      ),
    );
  }
}

// ── Real-time measurement card ────────────────────────────────────────────────

class _RealTimeCard extends StatelessWidget {
  final int latestSpo2;
  final bool measuring;
  final bool enabled;
  final VoidCallback? onTap;

  const _RealTimeCard({
    required this.latestSpo2,
    required this.measuring,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final spo2Text = measuring
        ? '···'
        : latestSpo2 > 0
            ? '$latestSpo2'
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
              Text('Real Time Blood Oxygen',
                  style: _inter(14, weight: FontWeight.w500)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(spo2Text,
                      style: _inter(15,
                          weight: FontWeight.w600,
                          color: measuring || latestSpo2 > 0
                              ? Colors.white
                              : _kSec2)),
                  const SizedBox(width: 4),
                  Text('%', style: _inter(11, color: _kSec)),
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
                          color: enabled ? AppTheme.spo2Color : _kSec,
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
