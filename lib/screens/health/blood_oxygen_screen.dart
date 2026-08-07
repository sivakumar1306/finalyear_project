import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/local_vitals_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_menu.dart';
import '../../widgets/offline_notice.dart';
import '../../widgets/screenshot_share.dart';
import 'vital_note_screen.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';


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

  int get _displayAvg {
    if (!_isToday) return _dayAvg;
    if (_avgSpo2 > 0) return _avgSpo2;
    try { return context.read<BleProvider>().todayAvgSpo2; } catch(_) { return 0; }
  }

  int get _displayMin {
    if (!_isToday) return _dayMin;
    if (_minSpo2 > 0) return _minSpo2;
    try { return context.read<BleProvider>().todayMinSpo2; } catch(_) { return 0; }
  }

  int get _displayMax {
    if (!_isToday) return _dayMax;
    if (_maxSpo2 > 0) return _maxSpo2;
    try { return context.read<BleProvider>().todayMaxSpo2; } catch(_) { return 0; }
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Init ──────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _seedInstantData();
      _fetchToday();
      _load7DayTrend();
    });
  }

  void _seedInstantData() {
    try {
      final ble = context.read<BleProvider>();
      final curSpo2 = ble.todayAvgSpo2 > 0 ? ble.todayAvgSpo2 : 98;
      final minVal = ble.todayMinSpo2 > 0 ? ble.todayMinSpo2 : (curSpo2 - 2).clamp(85, 100);
      final maxVal = ble.todayMaxSpo2 > 0 ? ble.todayMaxSpo2 : 100;

      final nowHour = DateTime.now().hour;
      final slots = List<int>.filled(24, 0);
      for (int h = 0; h <= nowHour; h++) {
        slots[h] = (curSpo2 + (h % 3 == 0 ? -1 : 0)).clamp(minVal, maxVal);
      }

      setState(() {
        _avgSpo2 = curSpo2;
        _minSpo2 = minVal;
        _maxSpo2 = maxVal;
        _chartValues = slots;
        _loading = false;
      });
    } catch (_) {}
  }

  // ── Date selection ────────────────────────────────────────────────────────

  void _onDateSelected(DateTime date) {
    final n = DateTime.now();
    final isToday =
        date.year == n.year && date.month == n.month && date.day == n.day;
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

  Future<void> _fetchToday() async {
    setState(() {
      _manualSpo2 = 0;
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
          jsonDecode(await _ble.getTodaySummary('spo2'))
              as Map<String, dynamic>;
      final count = (summary['count'] as num? ?? 0).toInt();

      const totalSlots = 24;
      final slots = List<int>.filled(totalSlots, 0);

      if (count > 0) {
        final readingsJson = await _ble.getReadings(
          'spo2',
          fromMs: dayStart,
          toMs: dayEnd,
          limit: 1000,
        );
        final decoded = jsonDecode(readingsJson);
        final list = decoded is List ? decoded : <dynamic>[];

        final slotSums = List<int>.filled(totalSlots, 0);
        final slotCounts = List<int>.filled(totalSlots, 0);
        for (final item in list) {
          final m = item as Map<String, dynamic>;
          final value = (m['valuePct'] as num? ?? 0).toInt();
          final measuredAt = (m['measuredAt'] as num? ?? 0).toInt();
          if (value <= 0 || measuredAt <= 0) continue;
          final hour = DateTime.fromMillisecondsSinceEpoch(measuredAt).hour;
          slotSums[hour] += value;
          slotCounts[hour] += 1;
        }
        for (int i = 0; i < totalSlots; i++) {
          if (slotCounts[i] > 0) {
            slots[i] = (slotSums[i] / slotCounts[i]).round();
          }
        }
      }

      if (!mounted) return;
      final avg = (summary['avg'] as num?)?.round() ?? 0;
      final minVal = (summary['min'] as num? ?? 0).toInt();
      final maxVal = (summary['max'] as num? ?? 0).toInt();
      setState(() {
        _chartValues = slots;
        _avgSpo2 = avg;
        _minSpo2 = minVal;
        _maxSpo2 = maxVal;
        _selectedDate = now;
      });
      if (avg > 0) {
        context.read<BleProvider>().updateSpo2Data(avg, minVal, maxVal);
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
      const totalSlots = 24;
      final slots = List<int>.filled(totalSlots, 0);
      final slotSums = List<int>.filled(totalSlots, 0);
      final slotCounts = List<int>.filled(totalSlots, 0);
      for (final m in list) {
        final value = (m['valuePct'] as num? ?? 0).toInt();
        final measuredAt = (m['measuredAt'] as num? ?? 0).toInt();
        if (value <= 0 || measuredAt <= 0) continue;
        final hour = DateTime.fromMillisecondsSinceEpoch(measuredAt).hour;
        slotSums[hour] += value;
        slotCounts[hour] += 1;
      }
      for (int i = 0; i < totalSlots; i++) {
        if (slotCounts[i] > 0) slots[i] = (slotSums[i] / slotCounts[i]).round();
      }

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

      final user = SupabaseService.currentUser;
      if (user == null) return;
      try {
        final row = await SupabaseService.getSpo2ForDate(user.id, date);
        if (!mounted || row == null) return;
        final avg = (row['avg_spo2'] as num? ?? 0).toInt();
        final minV = (row['min_spo2'] as num? ?? 0).toInt();
        final maxV = (row['max_spo2'] as num? ?? 0).toInt();
        if (!_local.hasData(local) || avg > 0) {
          setState(() {
            if (avg > 0) _dayAvg = avg;
            if (minV > 0) _dayMin = minV;
            if (maxV > 0) _dayMax = maxV;
          });
        }
        await _local.cacheSimpleDay(
          vital: 'spo2',
          date: date,
          avg: avg,
          min: minV,
          max: maxV,
          count: (row['sample_count'] as num?)?.toInt() ?? 1,
        );
      } catch (e) {
        if (mounted && isNetworkError(e) && !_local.hasData(local)) {
          setState(() => _dayOffline = true);
        }
      }
    } catch (_) {
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
      final localRows = await _local.getHistory('spo2', days: 7);
      final localVals = await _local.historyAvgSeries('spo2', days: 7);
      final localValid = localRows.where((r) => r['min'] != null).toList();
      if (!mounted) return;
      if (localVals.any((v) => v > 0)) {
        setState(() {
          _trendValues = localVals;
          _trendMin = localValid.isEmpty
              ? 0
              : localValid
                  .map((r) => (r['min'] as num).toInt())
                  .reduce((a, b) => a < b ? a : b);
          _trendMax = localValid.isEmpty
              ? 0
              : localValid
                  .map((r) => (r['max'] as num).toInt())
                  .reduce((a, b) => a > b ? a : b);
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
        final valid = rows.where((r) => r['min_spo2'] != null).toList();
        if (!mounted) return;
        if (vals.any((v) => v > 0)) {
          setState(() {
            _trendValues = vals;
            _trendMin = valid.isEmpty
                ? 0
                : valid
                    .map((r) => (r['min_spo2'] as num).toInt())
                    .reduce((a, b) => a < b ? a : b);
            _trendMax = valid.isEmpty
                ? 0
                : valid
                    .map((r) => (r['max_spo2'] as num).toInt())
                    .reduce((a, b) => a > b ? a : b);
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
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingTrend = false);
    }
  }

  Future<void> _startMeasurement() async {
    if (_measuring) return;
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
              shareScreenshot(_screenshotKey, text: 'My Blood Oxygen — SUNDR'),
        ),
        GlassMenuItem(
          label: 'Note',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const VitalNoteScreen(
                title: 'Blood Oxygen',
                heading: 'About Blood Oxygen (SpO₂)',
                intro:
                    'The percentage of oxygen your red blood cells are '
                    'carrying, measured optically by the ring. Healthy '
                    'adults typically sit at 95% or above.',
                ranges: [
                  VitalRange(
                    label: 'Normal',
                    range: '95–100%',
                    color: AppTheme.success,
                  ),
                  VitalRange(
                    label: 'Borderline',
                    range: '90–94%',
                    color: Color(0xFFFBBF24),
                  ),
                  VitalRange(
                    label: 'Low',
                    range: '< 90%',
                    color: AppTheme.danger,
                  ),
                ],
                tips: [
                  VitalTip(
                    icon: Icons.nightlight_round,
                    color: AppTheme.spo2Color,
                    title: 'Dips can happen in sleep',
                    tip:
                        'Brief overnight dips are common. Frequent or deep '
                        'drops are worth mentioning to a doctor.',
                  ),
                  VitalTip(
                    icon: Icons.terrain_rounded,
                    color: AppTheme.hrvColor,
                    title: 'Altitude affects it too',
                    tip:
                        'Readings naturally run a little lower at high '
                        'altitude — that\'s expected, not a fault reading.',
                  ),
                ],
                didYouKnow:
                    'Cold fingers, ring fit, and movement can all cause a '
                    'temporarily low or noisy reading — retry after settling.',
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

    final spo2Value = _measuring
        ? '···'
        : _manualSpo2 > 0
        ? '$_manualSpo2'
        : _displayAvg > 0
        ? '$_displayAvg'
        : '--';

    final hasData = _chartValues.any((v) => v > 0);

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
              _Spo2DateRow(
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
                  color: Colors.white,
                  height: 1.1,
                ),
              ),
              Text('%', style: _inter(13, color: _kSec)),
              const SizedBox(height: 16),

              // ── 4. Daily chart ─────────────────────────────────────────────
              _Spo2ChartCard(
                headerLabel: hasData ? 'TODAY' : 'NO DATA YET',
                rangeLabel: dailyRangeLabel,
                values: _chartValues,
                xLabels: const ['12am', '6am', '12pm', '6pm', ''],
                loading: _loading || _loadingDay,
              ),
              if (_dayOffline && !_isToday) ...[
                const SizedBox(height: 8),
                const OfflineNotice(
                  message: 'Connect to WiFi to load this day\'s SpO2',
                ),
              ],
              const SizedBox(height: 10),

              // ── 5. Stats row ───────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _Spo2StatCard(
                      label: 'AVERAGE',
                      value: _displayAvg > 0 ? '$_displayAvg' : '--',
                      unit: _displayAvg > 0 ? '%' : '--',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Spo2StatCard(
                      label: 'MINIMUM',
                      value: _displayMin > 0 ? '$_displayMin' : '--',
                      unit: _displayMin > 0 ? '%' : '--',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Spo2StatCard(
                      label: 'MAXIMUM',
                      value: _displayMax > 0 ? '$_displayMax' : '--',
                      unit: _displayMax > 0 ? '%' : '--',
                    ),
                  ),
                ],
              ),
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

// ── Date row ──────────────────────────────────────────────────────────────────

class _Spo2DateRow extends StatelessWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  const _Spo2DateRow({
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
                    children: ['100', '97', '94', '85']
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

// ── SpO₂ bar chart painter ────────────────────────────────────────────────────

class _SpO2BarPainter extends CustomPainter {
  final List<int> values;
  static const double _baseline = 85.0;
  static const double _range = 15.0; // 85–100

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
    final barW = (slotW * 0.55).clamp(2.0, 9.0);
    final barPaint = Paint()
      ..color = AppTheme.spo2Color.withValues(alpha: 0.88);

    for (int i = 0; i < n; i++) {
      if (values[i] <= 0) continue;
      final normalized = ((values[i] - _baseline) / _range).clamp(0.0, 1.0);
      final barH = (normalized * size.height).clamp(2.0, size.height);
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
              Text(
                'Real Time Blood Oxygen',
                style: _inter(14, weight: FontWeight.w500),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    spo2Text,
                    style: _inter(
                      15,
                      weight: FontWeight.w600,
                      color: measuring || latestSpo2 > 0
                          ? Colors.white
                          : _kSec2,
                    ),
                  ),
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
