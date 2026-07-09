import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/offline_notice.dart';

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

class HrvScreen extends StatefulWidget {
  const HrvScreen({super.key});
  @override
  State<HrvScreen> createState() => _HrvScreenState();
}

class _HrvScreenState extends State<HrvScreen> {
  final _ble = BleService();

  bool _loading      = false;
  bool _loadingDay   = false;
  bool _loadingTrend = false;
  bool _measuring    = false;
  bool _dayOffline   = false;
  bool _trendOffline = false;
  int  _manualHrv    = 0;

  DateTime _selectedDate = DateTime.now();

  // Today's local-DB data
  List<int> _chartValues = [];
  int _avgHrv = 0, _minHrv = 0, _maxHrv = 0;

  // Past-day / Supabase data
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

  bool get _hasRingData => _isToday && _chartValues.any((v) => v > 0);

  int get _displayAvg => _hasRingData ? _avgHrv : _dayAvg;
  int get _displayMin => _hasRingData ? _minHrv : _dayMin;
  int get _displayMax => _hasRingData ? _maxHrv : _dayMax;

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _hrvLabel(int v) {
    if (v <= 0) return '--';
    if (v < 20) return 'Very Low';
    if (v < 40) return 'Low';
    if (v < 60) return 'Moderate';
    if (v < 80) return 'Good';
    return 'Excellent';
  }

  static Color _hrvColor(int v) {
    if (v <= 0) return _kSec2;
    if (v < 20) return AppTheme.danger;
    if (v < 40) return AppTheme.stressColor;
    if (v < 60) return const Color(0xFFFBBF24);
    if (v < 80) return AppTheme.success;
    return AppTheme.hrvColor;
  }

  static String _fmtTime(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = h < 12 ? 'AM' : 'PM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$m $ampm';
  }

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
    final isToday = date.year == n.year && date.month == n.month && date.day == n.day;
    setState(() {
      _selectedDate = date;
      if (isToday) {
        _dayAvg = _dayMin = _dayMax = 0;
      }
    });
    if (!isToday) _loadDayFromSupabase(date);
  }

  // ── Local DB fetch (today) ───────────────────────────────────────────────
  // Reads from the local Room DB the background measurement loop (and the
  // manual "Measure Now" auto-cycle writes) actually populate, instead of the
  // ring's own onboard "today" SDK buffer — which never reflected our
  // manualModeHrv-driven readings and was why the chart stayed blank even
  // after real auto-loop cycles completed. Mirrors blood_pressure_screen's
  // proven local-DB pattern: works even when the ring isn't connected, and
  // stays consistent with whatever's actually in reading_hrv.

  Future<void> _fetchTodayFromLocalDb() async {
    setState(() => _loading = true);
    try {
      final now = DateTime.now();
      final dayStart = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
      final dayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999)
          .millisecondsSinceEpoch;

      final summary = jsonDecode(await _ble.getTodaySummary('hrv')) as Map<String, dynamic>;
      final count = (summary['count'] as num? ?? 0).toInt();

      const totalSlots = 48;
      final slots = List<int>.filled(totalSlots, 0);

      if (count > 0) {
        final readingsJson = await _ble.getReadings('hrv',
            fromMs: dayStart, toMs: dayEnd, limit: 1000);
        final decoded = jsonDecode(readingsJson);
        final list = decoded is List ? decoded : <dynamic>[];

        final slotSums = List<int>.filled(totalSlots, 0);
        final slotCounts = List<int>.filled(totalSlots, 0);
        for (final item in list) {
          final m = item as Map<String, dynamic>;
          final value = (m['valueMs'] as num? ?? 0).toInt();
          final measuredAt = (m['measuredAt'] as num? ?? 0).toInt();
          if (value <= 0 || measuredAt <= 0) continue;
          final dt = DateTime.fromMillisecondsSinceEpoch(measuredAt);
          final slot = (dt.hour * 60 + dt.minute) ~/ 30;
          if (slot >= 0 && slot < totalSlots) {
            slotSums[slot] += value;
            slotCounts[slot] += 1;
          }
        }
        for (int i = 0; i < totalSlots; i++) {
          if (slotCounts[i] > 0) slots[i] = (slotSums[i] / slotCounts[i]).round();
        }
      }

      if (!mounted) return;
      final avg = (summary['avg'] as num?)?.round() ?? 0;
      setState(() {
        _chartValues = slots;
        _avgHrv = avg;
        _minHrv = (summary['min'] as num? ?? 0).toInt();
        _maxHrv = (summary['max'] as num? ?? 0).toInt();
        _selectedDate = now;
      });
      if (avg > 0 && mounted) context.read<BleProvider>().updateHrvLatest(avg);
    } catch (_) {
      // Local DB read failing isn't worth surfacing loudly — chart just stays blank.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Manual "Measure Now" (for debugging the one-click HRV path) ───────────

  Future<void> _startMeasurement() async {
    if (_measuring) return;
    setState(() { _measuring = true; _manualHrv = 0; });
    try {
      final result = await _ble.manualModeHrv(start: true);
      int liveVal = 0;
      try {
        final m = jsonDecode(result) as Map<String, dynamic>;
        liveVal = (m['value'] as num?)?.toInt() ?? 0;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _measuring = false;
        if (liveVal > 0) _manualHrv = liveVal;
      });
      if (liveVal > 0) await _saveSingleMeasurement(liveVal);
    } catch (e) {
      if (!mounted) return;
      setState(() => _measuring = false);
      // Real HRV readings take ~50s on-device (confirmed against the official QRing
      // app) — surface the actual error instead of failing silently so a timeout is
      // distinguishable from e.g. a disconnect.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('HRV measurement failed: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  Future<void> _saveSingleMeasurement(int hrv) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      final existing = await SupabaseService.getHrvForDate(user.id, DateTime.now());
      int newAvg, newMin, newMax, newCount;
      final prevCount = (existing?['sample_count'] as num? ?? 0).toInt();
      if (existing != null && prevCount > 0) {
        final prevAvg = (existing['avg_hrv'] as num).toInt();
        final prevMin = (existing['min_hrv'] as num).toInt();
        final prevMax = (existing['max_hrv'] as num).toInt();
        newCount = prevCount + 1;
        newAvg = ((prevAvg * prevCount + hrv) / newCount).round();
        newMin = hrv < prevMin ? hrv : prevMin;
        newMax = hrv > prevMax ? hrv : prevMax;
      } else {
        newAvg = newMin = newMax = hrv;
        newCount = 1;
      }
      await SupabaseService.upsertHrv(
        userId: user.id,
        date: DateTime.now(),
        avgHrv: newAvg,
        minHrv: newMin,
        maxHrv: newMax,
        sampleCount: newCount,
      );
      if (mounted) {
        context.read<BleProvider>().updateHrvLatest(newAvg);
        setState(() {
          _avgHrv = newAvg;
          _minHrv = newMin;
          _maxHrv = newMax;
        });
      }
    } catch (_) {}
  }

  // ── Supabase fetches ──────────────────────────────────────────────────────

  Future<void> _loadDayFromSupabase(DateTime date) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() { _loadingDay = true; _dayOffline = false; });
    try {
      final row = await SupabaseService.getHrvForDate(user.id, date);
      if (!mounted) return;
      if (row != null) {
        setState(() {
          _dayAvg = (row['avg_hrv'] as num? ?? 0).toInt();
          _dayMin = (row['min_hrv'] as num? ?? 0).toInt();
          _dayMax = (row['max_hrv'] as num? ?? 0).toInt();
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
    setState(() { _loadingTrend = true; _trendOffline = false; });
    try {
      final now = DateTime.now();
      final rows = await SupabaseService.getHrvHistory(
        userId: user.id,
        from: now.subtract(const Duration(days: 6)),
        to: now,
      );
      final vals = List.generate(7, (i) {
        final day = now.subtract(Duration(days: 6 - i));
        final row = rows.firstWhere((r) => r['date'] == _fmt(day), orElse: () => {});
        return (row['avg_hrv'] as num? ?? 0).toInt();
      });
      final valid = rows.where((r) => r['min_hrv'] != null).toList();
      if (!mounted) return;
      setState(() {
        _trendValues = vals;
        _trendMin = valid.isEmpty
            ? 0
            : valid.map((r) => (r['min_hrv'] as num).toInt()).reduce((a, b) => a < b ? a : b);
        _trendMax = valid.isEmpty
            ? 0
            : valid.map((r) => (r['max_hrv'] as num).toInt()).reduce((a, b) => a > b ? a : b);
      });
    } catch (e) {
      if (mounted && isNetworkError(e)) setState(() => _trendOffline = true);
    } finally {
      if (mounted) setState(() => _loadingTrend = false);
    }
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

    final displayAvg = _displayAvg;
    final displayMin = _displayMin;
    final displayMax = _displayMax;

    final hrvText = _loading
        ? '···'
        : displayAvg > 0
            ? '$displayAvg'
            : '--';

    final hasData = _hasRingData;
    final dailyRangeLabel = hasData
        ? '$displayMin - $displayMax ms'
        : '-- -- ms';

    final trendRangeLabel = _trendMin > 0 && _trendMax > 0
        ? '$_trendMin - $_trendMax ms'
        : '-- -- ms';

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
        title: Text('HRV', style: _inter(17, weight: FontWeight.w600)),
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
      body: RefreshIndicator(
        color: AppTheme.hrvColor,
        backgroundColor: _kCard,
        onRefresh: () async {
          await _fetchTodayFromLocalDb();
          await _load7DayTrend();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // ── 1. Date row ────────────────────────────────────────────
              _HRVDateRow(
                selectedDate: _selectedDate,
                onDateSelected: _onDateSelected,
              ),
              const SizedBox(height: 22),

              // ── 2. Current HRV value ───────────────────────────────────
              Text(
                'CURRENT HRV',
                style: _inter(11,
                    weight: FontWeight.w600,
                    color: AppTheme.gold,
                    letterSpacing: 1.2),
              ),
              const SizedBox(height: 2),
              Text(
                hrvText,
                style: _inter(52, weight: FontWeight.w300, height: 1.1),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('ms', style: _inter(13, color: _kSec)),
                  const SizedBox(width: 10),
                  if (!_loading && displayAvg > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _hrvColor(displayAvg).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _hrvLabel(displayAvg),
                        style: _inter(11,
                            weight: FontWeight.w600,
                            color: _hrvColor(displayAvg)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // ── 3. Daily chart ─────────────────────────────────────────
              _HRVChartCard(
                headerLabel: hasData ? 'TODAY' : (_isToday ? 'NO DATA YET' : _dateLabel()),
                rangeLabel: dailyRangeLabel,
                values: _isToday ? _chartValues : [],
                xLabels: const ['12am', '6am', '12pm', '6pm', ''],
                loading: _loading || _loadingDay,
              ),
              if (_dayOffline && !_isToday) ...[
                const SizedBox(height: 8),
                const OfflineNotice(message: 'Connect to WiFi to load this day\'s HRV'),
              ],
              const SizedBox(height: 10),

              // ── 4. Stats row ───────────────────────────────────────────
              Row(children: [
                Expanded(
                  child: _HRVStatCard(
                    label: 'AVERAGE',
                    value: displayAvg > 0 ? '$displayAvg' : '--',
                    unit: displayAvg > 0 ? 'ms' : '--',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _HRVStatCard(
                    label: 'MINIMUM',
                    value: displayMin > 0 ? '$displayMin' : '--',
                    unit: displayMin > 0 ? 'ms' : '--',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _HRVStatCard(
                    label: 'MAXIMUM',
                    value: displayMax > 0 ? '$displayMax' : '--',
                    unit: displayMax > 0 ? 'ms' : '--',
                  ),
                ),
              ]),
              const SizedBox(height: 10),

              // ── 4b. Real-time measurement ───────────────────────────────
              _RealTimeCard(
                latestHrv: _manualHrv,
                measuring: _measuring,
                enabled: connected && !_measuring,
                onTap: _startMeasurement,
              ),
              const SizedBox(height: 20),

              // ── 5. 7-day trend ─────────────────────────────────────────
              _HRVChartCard(
                headerLabel: 'LAST 7 DAYS TREND',
                rangeLabel: trendRangeLabel,
                values: _trendValues,
                xLabels: _trendXLabels(),
                loading: _loadingTrend,
              ),
              if (_trendOffline) ...[
                const SizedBox(height: 8),
                const OfflineNotice(message: 'Connect to WiFi to load your 7-day trend'),
              ],
              const SizedBox(height: 10),

              // ── 6. Color legend ────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _kBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _LegendDot(color: AppTheme.danger, label: 'Very Low'),
                    _LegendDot(color: AppTheme.stressColor, label: 'Low'),
                    _LegendDot(color: const Color(0xFFFBBF24), label: 'Moderate'),
                    _LegendDot(color: AppTheme.success, label: 'Good'),
                    _LegendDot(color: AppTheme.hrvColor, label: 'Excellent'),
                  ],
                ),
              ),

              // ── 7. Slot readings (today only) ──────────────────────────
              if (hasData) ...[
                const SizedBox(height: 10),
                _slotReadingsList(_chartValues),
              ],

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  String _dateLabel() {
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    return '${months[_selectedDate.month - 1]} ${_selectedDate.day}';
  }

  Widget _slotReadingsList(List<int> values) {
    final entries = <(String, int)>[];
    for (int i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final minutes = i * 30;
      final dt = DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day,
        minutes ~/ 60, minutes % 60,
      );
      entries.add((_fmtTime(dt), values[i]));
    }
    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              'READINGS',
              style: _inter(10, weight: FontWeight.w600, color: _kSec, letterSpacing: 0.7),
            ),
          ),
          ...entries.asMap().entries.map((e) {
            final time = e.value.$1;
            final v = e.value.$2;
            final color = _hrvColor(v);
            final label = _hrvLabel(v);
            final isLast = e.key == entries.length - 1;
            return Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.monitor_heart_rounded, color: color, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(time,
                            style: _inter(14, weight: FontWeight.w600)),
                        Text(label,
                            style: _inter(11, color: color)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$v', style: _inter(22, weight: FontWeight.w700)),
                      Text('ms', style: _inter(10, color: _kSec)),
                    ],
                  ),
                ]),
              ),
              if (!isLast)
                const Divider(color: _kBorder, height: 0.5, indent: 66),
            ]);
          }),
        ],
      ),
    );
  }
}

// ── Date row ──────────────────────────────────────────────────────────────────

class _HRVDateRow extends StatelessWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  const _HRVDateRow({required this.selectedDate, required this.onDateSelected});

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
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
    final isToday = d == today;
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

// ── HRV Chart Card ────────────────────────────────────────────────────────────

class _HRVChartCard extends StatelessWidget {
  final String headerLabel;
  final String rangeLabel;
  final List<int> values;
  final List<String> xLabels;
  final bool loading;

  const _HRVChartCard({
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
                    children: ['100', '80', '60', '40']
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
                            color: AppTheme.hrvColor,
                            strokeWidth: 2,
                          ),
                        )
                      : CustomPaint(
                          painter: _HRVBarPainter(values: values),
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

// ── HRV Bar Painter ───────────────────────────────────────────────────────────

class _HRVBarPainter extends CustomPainter {
  final List<int> values;
  const _HRVBarPainter({required this.values});

  static const _maxY   = 100.0;
  static const _yLines = [100, 80, 60, 40, 20];

  static Color _barColor(int v) {
    if (v < 20) return AppTheme.danger;
    if (v < 40) return AppTheme.stressColor;
    if (v < 60) return const Color(0xFFFBBF24);
    if (v < 80) return AppTheme.success;
    return AppTheme.hrvColor;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = _kGrid
      ..strokeWidth = 0.5;
    for (final y in _yLines) {
      final yPos = size.height - (y / _maxY) * size.height;
      canvas.drawLine(Offset(0, yPos), Offset(size.width, yPos), gridPaint);
    }

    if (values.isEmpty) return;
    final nonZero = values.where((v) => v > 0).toList();
    if (nonZero.isEmpty) {
      return;
    }

    final n = values.length;
    final slotW = size.width / n;
    final barW = (slotW * 0.55).clamp(2.0, 9.0);

    for (int i = 0; i < n; i++) {
      if (values[i] <= 0) continue;
      final ratio = (values[i] / _maxY).clamp(0.0, 1.2);
      final barH = (ratio * size.height).clamp(2.0, size.height);
      final x = i * slotW + (slotW - barW) / 2;
      canvas.drawRRect(
        RRect.fromLTRBR(
            x, size.height - barH, x + barW, size.height,
            const Radius.circular(3)),
        Paint()..color = _barColor(values[i]).withValues(alpha: 0.88),
      );
    }
  }

  @override
  bool shouldRepaint(_HRVBarPainter old) => old.values != values;
}

// ── Stat card ─────────────────────────────────────────────────────────────────

class _HRVStatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  const _HRVStatCard({
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
  final int latestHrv;
  final bool measuring;
  final bool enabled;
  final VoidCallback? onTap;

  const _RealTimeCard({
    required this.latestHrv,
    required this.measuring,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hrvText = measuring
        ? '···'
        : latestHrv > 0
            ? '$latestHrv'
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
              Text('Real Time HRV',
                  style: _inter(14, weight: FontWeight.w500)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(hrvText,
                      style: _inter(15,
                          weight: FontWeight.w600,
                          color: measuring || latestHrv > 0
                              ? Colors.white
                              : _kSec2)),
                  const SizedBox(width: 4),
                  Text('ms', style: _inter(11, color: _kSec)),
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
                          color: enabled ? AppTheme.hrvColor : _kSec,
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
          const SizedBox(width: 4),
          Text(label, style: _inter(9, color: _kSec2)),
        ],
      );
}

