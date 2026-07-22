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

const _kCard    = Color(0xFF141414);
const _kBorder  = Color(0xFF242424);
const _kGrid    = Color(0xFF222222);
const _kSec     = Color(0xFF666666);
const _kSec2    = Color(0xFF888888);
// DBP uses a contrasting violet so both series are visually distinct.
const _dbpColor = Color(0xFFC084FC);

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

String _bpStatus(int sbp, int dbp) {
  if (sbp <= 0 || dbp <= 0) return '';
  if (sbp < 120 && dbp < 80) return 'Normal';
  if (sbp < 130 && dbp < 80) return 'Elevated';
  if (sbp < 140 || dbp < 90) return 'Stage 1';
  return 'Stage 2';
}

Color _bpStatusColor(int sbp, int dbp) {
  if (sbp <= 0 || dbp <= 0) return _kSec2;
  if (sbp < 120 && dbp < 80) return AppTheme.success;
  if (sbp < 130 && dbp < 80) return const Color(0xFFFBBF24);
  if (sbp < 140 || dbp < 90) return AppTheme.stressColor;
  return AppTheme.danger;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class BloodPressureScreen extends StatefulWidget {
  const BloodPressureScreen({super.key});
  @override
  State<BloodPressureScreen> createState() => _BloodPressureScreenState();
}

class _BloodPressureScreenState extends State<BloodPressureScreen> {
  final _ble = BleService();

  bool _loading      = false;
  bool _loadingDay   = false;
  bool _loadingTrend = false;
  bool _measuring    = false;
  bool _dayOffline   = false;
  bool _trendOffline = false;

  DateTime _selectedDate = DateTime.now();

  int _manualSbp = 0, _manualDbp = 0;
  bool _settingEnabled  = true;
  int  _settingInterval = 30;

  // Today's local-DB data
  List<int> _chartSbp = [];
  List<int> _chartDbp = [];
  int _avgSbp = 0, _minSbp = 0, _maxSbp = 0;
  int _avgDbp = 0, _minDbp = 0, _maxDbp = 0;

  // Past-day Supabase data
  int _daySbpAvg = 0, _daySbpMin = 0, _daySbpMax = 0;
  int _dayDbpAvg = 0, _dayDbpMin = 0, _dayDbpMax = 0;

  // 7-day trend
  List<int> _trendSbp = [];
  List<int> _trendDbp = [];

  // ── Computed ──────────────────────────────────────────────────────────────────

  bool get _isToday {
    final n = DateTime.now();
    return _selectedDate.year == n.year &&
        _selectedDate.month == n.month &&
        _selectedDate.day == n.day;
  }

  int get _displaySbpAvg => _isToday ? _avgSbp : _daySbpAvg;
  int get _displaySbpMin => _isToday ? _minSbp : _daySbpMin;
  int get _displaySbpMax => _isToday ? _maxSbp : _daySbpMax;
  int get _displayDbpAvg => _isToday ? _avgDbp : _dayDbpAvg;
  int get _displayDbpMin => _isToday ? _minDbp : _dayDbpMin;
  int get _displayDbpMax => _isToday ? _maxDbp : _dayDbpMax;

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Init ──────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Local DB read — doesn't need a live ring connection.
      _fetchTodayFromLocalDb();
      _load7DayTrend();
    });
  }

  // ── Date selection ────────────────────────────────────────────────────────────

  void _onDateSelected(DateTime date) {
    final n = DateTime.now();
    final isToday = date.year == n.year && date.month == n.month && date.day == n.day;
    setState(() {
      _selectedDate = date;
      _manualSbp = 0;
      _manualDbp = 0;
      if (isToday) {
        _daySbpAvg = _daySbpMin = _daySbpMax = 0;
        _dayDbpAvg = _dayDbpMin = _dayDbpMax = 0;
      }
    });
    if (!isToday) _loadDayFromSupabase(date);
  }

  // ── Local DB fetch (today) ──────────────────────────────────────────────────
  // Reads from the local Room DB the background streaming loop writes to,
  // instead of hitting the ring directly — works even when the ring isn't
  // currently connected, and stays consistent with the home screen's card.

  Future<void> _fetchTodayFromLocalDb() async {
    setState(() { _loading = true; _manualSbp = 0; _manualDbp = 0; });
    try {
      final now = DateTime.now();
      final dayStart = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
      final dayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999)
          .millisecondsSinceEpoch;

      final summary =
          jsonDecode(await _ble.getTodaySummary('blood_pressure')) as Map<String, dynamic>;
      final count = (summary['count'] as num? ?? 0).toInt();

      final sbpHourly = List<int>.filled(24, 0);
      final dbpHourly = List<int>.filled(24, 0);
      if (count > 0) {
        final readingsJson = await _ble.getReadings('blood_pressure',
            fromMs: dayStart, toMs: dayEnd, limit: 1000);
        final decoded = jsonDecode(readingsJson);
        final list = decoded is List ? decoded : <dynamic>[];
        final sbpSums = List<int>.filled(24, 0);
        final dbpSums = List<int>.filled(24, 0);
        final counts = List<int>.filled(24, 0);
        for (final item in list) {
          final m = item as Map<String, dynamic>;
          final sbp = (m['systolic'] as num? ?? 0).toInt();
          final dbp = (m['diastolic'] as num? ?? 0).toInt();
          final measuredAt = (m['measuredAt'] as num? ?? 0).toInt();
          if (sbp <= 0 || dbp <= 0 || measuredAt <= 0) continue;
          final h = DateTime.fromMillisecondsSinceEpoch(measuredAt).hour;
          sbpSums[h] += sbp;
          dbpSums[h] += dbp;
          counts[h] += 1;
        }
        for (int h = 0; h < 24; h++) {
          if (counts[h] > 0) {
            sbpHourly[h] = (sbpSums[h] / counts[h]).round();
            dbpHourly[h] = (dbpSums[h] / counts[h]).round();
          }
        }
      }

      if (!mounted) return;
      final avgSbp = (summary['avgSbp'] as num?)?.round() ?? 0;
      final minSbp = (summary['minSbp'] as num?)?.toInt() ?? 0;
      final maxSbp = (summary['maxSbp'] as num?)?.toInt() ?? 0;
      final avgDbp = (summary['avgDbp'] as num?)?.round() ?? 0;
      final minDbp = (summary['minDbp'] as num?)?.toInt() ?? 0;
      final maxDbp = (summary['maxDbp'] as num?)?.toInt() ?? 0;
      setState(() {
        _chartSbp = sbpHourly;
        _chartDbp = dbpHourly;
        _avgSbp = avgSbp; _minSbp = minSbp; _maxSbp = maxSbp;
        _avgDbp = avgDbp; _minDbp = minDbp; _maxDbp = maxDbp;
        _selectedDate = DateTime.now();
      });
      final lastSbp = (summary['lastSbp'] as num?)?.toInt() ?? avgSbp;
      final lastDbp = (summary['lastDbp'] as num?)?.toInt() ?? avgDbp;
      if (lastSbp > 0 && lastDbp > 0) {
        context.read<BleProvider>().updateBpLatest(lastSbp, lastDbp);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Supabase fetches (past days / trend — historical data predates local DB) ─

  Future<void> _loadDayFromSupabase(DateTime date) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() { _loadingDay = true; _dayOffline = false; });
    try {
      final from = DateTime(date.year, date.month, date.day);
      final to = DateTime(date.year, date.month, date.day, 23, 59, 59);
      final rows = await SupabaseService.getBpReadings(userId: user.id, from: from, to: to);
      if (!mounted) return;
      final sbps = rows.map((r) => (r['systolic'] as num? ?? 0).toInt()).where((v) => v > 0).toList();
      final dbps = rows.map((r) => (r['diastolic'] as num? ?? 0).toInt()).where((v) => v > 0).toList();
      setState(() {
        if (sbps.isNotEmpty) {
          _daySbpAvg = (sbps.reduce((a, b) => a + b) / sbps.length).round();
          _daySbpMin = sbps.reduce((a, b) => a < b ? a : b);
          _daySbpMax = sbps.reduce((a, b) => a > b ? a : b);
        }
        if (dbps.isNotEmpty) {
          _dayDbpAvg = (dbps.reduce((a, b) => a + b) / dbps.length).round();
          _dayDbpMin = dbps.reduce((a, b) => a < b ? a : b);
          _dayDbpMax = dbps.reduce((a, b) => a > b ? a : b);
        }
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
    setState(() { _loadingTrend = true; _trendOffline = false; });
    try {
      final now = DateTime.now();
      final rows = await SupabaseService.getBpReadings(
        userId: user.id,
        from: now.subtract(const Duration(days: 6)),
        to: now,
      );
      final byDaySbp = <String, List<int>>{};
      final byDayDbp = <String, List<int>>{};
      for (final r in rows) {
        final dt = DateTime.parse(r['measured_at'] as String).toLocal();
        final key = _fmt(dt);
        final sbp = (r['systolic'] as num? ?? 0).toInt();
        final dbp = (r['diastolic'] as num? ?? 0).toInt();
        if (sbp > 0) byDaySbp.putIfAbsent(key, () => []).add(sbp);
        if (dbp > 0) byDayDbp.putIfAbsent(key, () => []).add(dbp);
      }
      final sbpVals = List.generate(7, (i) {
        final day = now.subtract(Duration(days: 6 - i));
        final vals = byDaySbp[_fmt(day)];
        if (vals == null || vals.isEmpty) return 0;
        return (vals.reduce((a, b) => a + b) / vals.length).round();
      });
      final dbpVals = List.generate(7, (i) {
        final day = now.subtract(Duration(days: 6 - i));
        final vals = byDayDbp[_fmt(day)];
        if (vals == null || vals.isEmpty) return 0;
        return (vals.reduce((a, b) => a + b) / vals.length).round();
      });
      if (!mounted) return;
      setState(() {
        _trendSbp = sbpVals;
        _trendDbp = dbpVals;
      });
    } catch (e) {
      if (mounted && isNetworkError(e)) setState(() => _trendOffline = true);
    } finally {
      if (mounted) setState(() => _loadingTrend = false);
    }
  }

  // ── Settings ──────────────────────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    if (!context.read<BleProvider>().isConnected) return;
    try {
      final json = await _ble.getBloodPressureSetting();
      final m = jsonDecode(json) as Map<String, dynamic>;
      setState(() {
        _settingEnabled  = m['enable']   ?? true;
        _settingInterval = m['interval'] ?? 30;
      });
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      await _ble.setBloodPressureSetting(enable: _settingEnabled, interval: _settingInterval);
    } catch (_) {}
  }

  // ── Manual measurement ────────────────────────────────────────────────────────

  Future<void> _startMeasurement() async {
    if (_measuring) return;
    setState(() { _measuring = true; _manualSbp = 0; _manualDbp = 0; });
    try {
      final result = await _ble.manualModeBP(start: true);
      final m = jsonDecode(result) as Map<String, dynamic>;
      final sbp = (m['sbp'] as num? ?? 0).toInt();
      final dbp = (m['dbp'] as num? ?? 0).toInt();
      if (!mounted) return;
      setState(() => _measuring = false);
      if (sbp > 0 && dbp > 0) {
        setState(() { _manualSbp = sbp; _manualDbp = dbp; });
        await _saveMeasurement(sbp, dbp);
      }
    } catch (_) {
      if (mounted) setState(() => _measuring = false);
    }
  }

  Future<void> _saveMeasurement(int sbp, int dbp) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.insertBp(
        userId: user.id, systolic: sbp, diastolic: dbp, measuredAt: DateTime.now(),
      );
      if (mounted) context.read<BleProvider>().updateBpLatest(sbp, dbp);
    } catch (_) {}
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

    final sbpText = _measuring
        ? '···'
        : _manualSbp > 0
            ? '$_manualSbp'
            : _displaySbpAvg > 0
                ? '$_displaySbpAvg'
                : '--';
    final dbpText = _measuring
        ? '···'
        : _manualDbp > 0
            ? '$_manualDbp'
            : _displayDbpAvg > 0
                ? '$_displayDbpAvg'
                : '--';

    final currentSbp = _manualSbp > 0 ? _manualSbp : _displaySbpAvg;
    final currentDbp = _manualDbp > 0 ? _manualDbp : _displayDbpAvg;
    final currentLabel = _measuring ? 'Measuring…' : _bpStatus(currentSbp, currentDbp);
    final currentLabelColor = _bpStatusColor(currentSbp, currentDbp);

    final hasData = _isToday && (_chartSbp.any((v) => v > 0) || _chartDbp.any((v) => v > 0));

    final dailyRangeLabel = hasData
        ? '$_displaySbpMin-$_displaySbpMax / $_displayDbpMin-$_displayDbpMax'
        : '-- --';

    final trendNonZeroSbp = _trendSbp.where((v) => v > 0).toList();
    final trendRangeLabel = trendNonZeroSbp.isNotEmpty
        ? '${trendNonZeroSbp.reduce((a, b) => a < b ? a : b)} - ${trendNonZeroSbp.reduce((a, b) => a > b ? a : b)} mmHg'
        : '-- -- mmHg';

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
        title: Text('Blood Pressure', style: _inter(17, weight: FontWeight.w600)),
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

            // ── 1. BP Detection toggle ─────────────────────────────────────
            _BPDetectionCard(
              enabled: _settingEnabled,
              onToggle: (v) {
                setState(() => _settingEnabled = v);
                _saveSettings();
              },
            ),
            const SizedBox(height: 20),

            // ── 2. Date row ────────────────────────────────────────────────
            _BPDateRow(
              selectedDate: _selectedDate,
              onDateSelected: _onDateSelected,
            ),
            const SizedBox(height: 22),

            // ── 3. Current BP value ────────────────────────────────────────
            Text(
              'CURRENT BLOOD PRESSURE',
              style: _inter(11, weight: FontWeight.w600, color: AppTheme.gold, letterSpacing: 1.2),
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(sbpText, style: _inter(52, weight: FontWeight.w300, color: Colors.white, height: 1.1)),
                Text('/', style: _inter(36, weight: FontWeight.w300, color: _kSec)),
                Text(dbpText, style: _inter(52, weight: FontWeight.w300, color: Colors.white, height: 1.1)),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('mmHg', style: _inter(13, color: _kSec)),
                if (currentLabel.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: currentLabelColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(currentLabel,
                        style: _inter(11, weight: FontWeight.w600, color: currentLabelColor)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // ── 4. Daily chart ─────────────────────────────────────────────
            _BPChartCard(
              headerLabel: hasData ? 'TODAY' : 'NO DATA YET',
              rangeLabel: dailyRangeLabel,
              sbpValues: _isToday ? _chartSbp : [],
              dbpValues: _isToday ? _chartDbp : [],
              xLabels: const ['12am', '6am', '12pm', '6pm', ''],
              loading: _loading || _loadingDay,
            ),
            if (_dayOffline && !_isToday) ...[
              const SizedBox(height: 8),
              const OfflineNotice(message: 'Connect to WiFi to load this day\'s blood pressure'),
            ],
            const SizedBox(height: 10),

            // ── 5. Stats row ───────────────────────────────────────────────
            Row(children: [
              Expanded(
                child: _BPStatCard(
                  label: 'AVERAGE',
                  value: (_displaySbpAvg > 0 && _displayDbpAvg > 0)
                      ? '$_displaySbpAvg/$_displayDbpAvg'
                      : '--',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BPStatCard(
                  label: 'MINIMUM',
                  value: (_displaySbpMin > 0 && _displayDbpMin > 0)
                      ? '$_displaySbpMin/$_displayDbpMin'
                      : '--',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BPStatCard(
                  label: 'MAXIMUM',
                  value: (_displaySbpMax > 0 && _displayDbpMax > 0)
                      ? '$_displaySbpMax/$_displayDbpMax'
                      : '--',
                ),
              ),
            ]),
            const SizedBox(height: 10),

            // ── 6. Real-time measurement ───────────────────────────────────
            _RealTimeBPCard(
              sbp: _manualSbp,
              dbp: _manualDbp,
              measuring: _measuring,
              enabled: connected && !_measuring,
              onTap: _startMeasurement,
            ),
            const SizedBox(height: 20),

            // ── 7. 7-day trend ─────────────────────────────────────────────
            _BPChartCard(
              headerLabel: 'LAST 7 DAYS TREND',
              rangeLabel: trendRangeLabel,
              sbpValues: _trendSbp,
              dbpValues: _trendDbp,
              xLabels: _trendXLabels(),
              loading: _loadingTrend,
            ),
            if (_trendOffline) ...[
              const SizedBox(height: 8),
              const OfflineNotice(message: 'Connect to WiFi to load your 7-day trend'),
            ],
            const SizedBox(height: 10),

            // ── 8. Legend ──────────────────────────────────────────────────
            Row(children: [
              _LegendDot(color: AppTheme.bpColor, label: 'Systolic'),
              const SizedBox(width: 14),
              _LegendDot(color: _dbpColor, label: 'Diastolic'),
            ]),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

// ── BP Detection card ──────────────────────────────────────────────────────────

class _BPDetectionCard extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onToggle;
  const _BPDetectionCard({required this.enabled, required this.onToggle});

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
                Text('Blood Pressure Detection', style: _inter(15, weight: FontWeight.w600)),
                const SizedBox(height: 5),
                Text(
                  'Enable continuous blood pressure monitoring throughout the day.',
                  style: _inter(12, color: _kSec2, height: 1.45),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Switch(value: enabled, onChanged: onToggle),
        ],
      ),
    );
  }
}

// ── Date row ──────────────────────────────────────────────────────────────────

class _BPDateRow extends StatelessWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  const _BPDateRow({required this.selectedDate, required this.onDateSelected});

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
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
            isToday ? 'Today, ${d.day} ${_months[d.month - 1]}' : '${d.day} ${_months[d.month - 1]}',
            style: _inter(13, weight: FontWeight.w500),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: isFuture ? null : () => onDateSelected(d),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text('${d.day}', style: _inter(15, color: isFuture ? const Color(0xFF333333) : _kSec2)),
      ),
    );
  }
}

// ── BP Chart Card (dual series: systolic + diastolic) ─────────────────────────

class _BPChartCard extends StatelessWidget {
  final String headerLabel;
  final String rangeLabel;
  final List<int> sbpValues;
  final List<int> dbpValues;
  final List<String> xLabels;
  final bool loading;

  const _BPChartCard({
    required this.headerLabel,
    required this.rangeLabel,
    required this.sbpValues,
    required this.dbpValues,
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
                  style: _inter(11, weight: FontWeight.w600, color: _kSec, letterSpacing: 0.6)),
              Text(rangeLabel,
                  style: _inter(11, weight: FontWeight.w500, color: const Color(0xFF999999))),
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
                    children: ['160', '120', '80', '40']
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
                          child: CircularProgressIndicator(color: AppTheme.bpColor, strokeWidth: 2),
                        )
                      : CustomPaint(
                          painter: _BPBarPainter(sbpValues: sbpValues, dbpValues: dbpValues),
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
              children: xLabels.map((l) => Text(l, style: _inter(10, color: _kSec))).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── BP Bar Painter ─────────────────────────────────────────────────────────────

class _BPBarPainter extends CustomPainter {
  final List<int> sbpValues;
  final List<int> dbpValues;
  const _BPBarPainter({required this.sbpValues, required this.dbpValues});

  static const _maxY = 160.0;
  static const _yLines = [160, 120, 80, 40];

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = _kGrid
      ..strokeWidth = 0.5;
    for (final y in _yLines) {
      final yPos = size.height - (y / _maxY) * size.height;
      canvas.drawLine(Offset(0, yPos), Offset(size.width, yPos), gridPaint);
    }

    final n = sbpValues.length;
    if (n == 0) return;
    final slotW = size.width / n;
    final barW = (slotW * 0.3).clamp(1.5, 5.0);
    final sbpPaint = Paint()..color = AppTheme.bpColor.withValues(alpha: 0.88);
    final dbpPaint = Paint()..color = _dbpColor.withValues(alpha: 0.88);

    for (int i = 0; i < n; i++) {
      final cx = i * slotW + slotW / 2;

      final sbp = sbpValues[i];
      if (sbp > 0) {
        final ratio = (sbp / _maxY).clamp(0.0, 1.0);
        final barH = (ratio * size.height).clamp(2.0, size.height);
        canvas.drawRRect(
          RRect.fromLTRBR(cx - barW - 1, size.height - barH, cx - 1, size.height,
              const Radius.circular(2)),
          sbpPaint,
        );
      }

      final dbp = i < dbpValues.length ? dbpValues[i] : 0;
      if (dbp > 0) {
        final ratio = (dbp / _maxY).clamp(0.0, 1.0);
        final barH = (ratio * size.height).clamp(2.0, size.height);
        canvas.drawRRect(
          RRect.fromLTRBR(cx + 1, size.height - barH, cx + barW + 1, size.height,
              const Radius.circular(2)),
          dbpPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BPBarPainter old) =>
      old.sbpValues != sbpValues || old.dbpValues != dbpValues;
}

// ── Stat card ─────────────────────────────────────────────────────────────────

class _BPStatCard extends StatelessWidget {
  final String label;
  final String value;
  const _BPStatCard({required this.label, required this.value});

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
              style: _inter(10, weight: FontWeight.w600, color: _kSec, letterSpacing: 0.7)),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: _inter(17, weight: FontWeight.w600)),
                const SizedBox(width: 4),
                Text(value != '--' ? 'mmHg' : '', style: _inter(11, color: _kSec)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text('know more >', style: _inter(11, color: _kSec)),
        ],
      ),
    );
  }
}

// ── Real-time measurement card ────────────────────────────────────────────────

class _RealTimeBPCard extends StatelessWidget {
  final int sbp;
  final int dbp;
  final bool measuring;
  final bool enabled;
  final VoidCallback? onTap;

  const _RealTimeBPCard({
    required this.sbp,
    required this.dbp,
    required this.measuring,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bpText = measuring
        ? '···'
        : (sbp > 0 && dbp > 0)
            ? '$sbp/$dbp'
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
              Text('Real Time Blood Pressure', style: _inter(14, weight: FontWeight.w500)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(bpText,
                      style: _inter(15,
                          weight: FontWeight.w600,
                          color: measuring || (sbp > 0 && dbp > 0) ? Colors.white : _kSec2)),
                  const SizedBox(width: 4),
                  Text('mmHg', style: _inter(11, color: _kSec)),
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
                          color: enabled ? AppTheme.bpColor : _kSec,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Click to start measurement',
                        style: _inter(14, weight: FontWeight.w500, color: enabled ? Colors.white70 : _kSec),
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
          CircleAvatar(radius: 4, backgroundColor: color),
          const SizedBox(width: 4),
          Text(label, style: _inter(10, color: _kSec)),
        ],
      );
}
