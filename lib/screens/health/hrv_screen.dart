import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vital_widgets.dart';

class HrvScreen extends StatefulWidget {
  const HrvScreen({super.key});
  @override
  State<HrvScreen> createState() => _HrvScreenState();
}

class _HrvScreenState extends State<HrvScreen> {
  final _ble = BleService();

  int _period = 0;
  DateTime _selectedDate = DateTime.now();

  bool _loading = false;
  bool _loadingHistory = false;

  // Ring data: 48 slots × 30 min = 24 h
  List<int> _chartValues = [];
  int _avgHrv = 0, _minHrv = 0, _maxHrv = 0;

  // Supabase history
  List<int> _histChartValues = [];
  int _histAvg = 0, _histMin = 0, _histMax = 0;

  // ── Helpers ────────────────────────────────────────────────────────────────

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  bool get _showRingData =>
      _period == 0 && _isToday && _chartValues.isNotEmpty;

  List<int> get _displayChart =>
      _showRingData ? _chartValues : _histChartValues;
  int get _displayAvg => _showRingData ? _avgHrv : _histAvg;
  int get _displayMin => _showRingData ? _minHrv : _histMin;
  int get _displayMax => _showRingData ? _maxHrv : _histMax;

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _fmtTime(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = h < 12 ? 'AM' : 'PM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$m $ampm';
  }

  static String _hrvLabel(int v) {
    if (v <= 0) return 'No data';
    if (v < 20) return 'Very Low';
    if (v < 40) return 'Low';
    if (v < 60) return 'Moderate';
    if (v < 80) return 'Good';
    return 'Excellent';
  }

  static Color _hrvColor(int v) {
    if (v <= 0) return AppTheme.textSec;
    if (v < 20) return AppTheme.danger;
    if (v < 40) return AppTheme.stressColor;
    if (v < 60) return const Color(0xFFFBBF24);
    if (v < 80) return AppTheme.success;
    return AppTheme.hrvColor;
  }

  // ── Init ───────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final connected = context.read<BleProvider>().isConnected;
      if (connected) {
        _fetchTodayFromRing();
      } else {
        _loadTodayFromSupabase();
      }
    });
  }

  // ── Period / date handlers ─────────────────────────────────────────────────

  void _onPeriodChanged(int p) {
    setState(() {
      _period = p;
      _histChartValues = [];
      _histAvg = _histMin = _histMax = 0;
    });
    if (p == 0) _loadTodayFromSupabase();
    if (p == 1) _loadPeriodFromSupabase(7);
    if (p == 2) _loadPeriodFromSupabase(30);
  }

  void _onDateSelected(DateTime date) {
    final now = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
    setState(() {
      _selectedDate = date;
      if (!isToday) {
        _histChartValues = [];
        _histAvg = _histMin = _histMax = 0;
      }
    });
    if (!isToday) _loadDayFromSupabase(date);
  }

  // ── Ring fetch ─────────────────────────────────────────────────────────────

  Future<void> _fetchTodayFromRing() async {
    setState(() => _loading = true);
    try {
      final data = await _ble.getTodayHrv();
      _parseHrvData(data);
    } catch (_) {
      _loadTodayFromSupabase();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _parseHrvData(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded == null || decoded is! Map<String, dynamic>) {
        _loadTodayFromSupabase();
        return;
      }

      final offset = (decoded['offset'] as num? ?? 0).toInt();
      // SDK: HRVRsp key 'd' — one value per 30-min slot; 0 = no reading.
      final raw = (decoded['d'] as List<dynamic>? ?? [])
          .map((v) => (v as num).toInt())
          .toList();

      final readings = raw.where((v) => v > 0).toList();
      if (readings.isEmpty) {
        _loadTodayFromSupabase();
        return;
      }

      final avg = (readings.reduce((a, b) => a + b) / readings.length).round();
      final maxVal = readings.reduce((a, b) => a > b ? a : b);
      final minVal = readings.reduce((a, b) => a < b ? a : b);

      // Expand to the full 48-slot (24 h) array so bar positions and the
      // readings list timestamps both reflect correct clock times.
      // Slot i = midnight + i*30 min.
      const totalSlots = 48;
      final fullDay = List<int>.filled(totalSlots, 0);
      for (int i = 0; i < raw.length; i++) {
        final slot = offset + i;
        if (slot < totalSlots) fullDay[slot] = raw[i];
      }

      // Ring firmware pre-fills the entire day — zero out future slots.
      final nowMins = DateTime.now().hour * 60 + DateTime.now().minute;
      final currentSlot = nowMins ~/ 30;
      for (int i = currentSlot + 1; i < totalSlots; i++) {
        fullDay[i] = 0;
      }

      if (!mounted) return;
      setState(() {
        _chartValues = fullDay;
        _avgHrv = avg;
        _minHrv = minVal;
        _maxHrv = maxVal;
        _selectedDate = DateTime.now();
      });

      context.read<BleProvider>().updateHrvLatest(avg);
      _saveToSupabase(avg, minVal, maxVal, readings.length);
    } catch (_) {
      _loadTodayFromSupabase();
    }
  }

  Future<void> _saveToSupabase(
      int avg, int min, int max, int count) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.upsertHrv(
        userId: user.id,
        date: DateTime.now(),
        avgHrv: avg,
        minHrv: min,
        maxHrv: max,
        sampleCount: count,
      );
    } catch (_) {}
  }

  // ── Supabase fetches ───────────────────────────────────────────────────────

  Future<void> _loadTodayFromSupabase() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() => _loadingHistory = true);
    try {
      final row =
          await SupabaseService.getHrvForDate(user.id, DateTime.now());
      if (!mounted) return;
      if (row != null) {
        setState(() {
          _histAvg = (row['avg_hrv'] as num? ?? 0).toInt();
          _histMin = (row['min_hrv'] as num? ?? 0).toInt();
          _histMax = (row['max_hrv'] as num? ?? 0).toInt();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _loadDayFromSupabase(DateTime date) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() => _loadingHistory = true);
    try {
      final row = await SupabaseService.getHrvForDate(user.id, date);
      if (!mounted) return;
      if (row != null) {
        setState(() {
          _histAvg = (row['avg_hrv'] as num? ?? 0).toInt();
          _histMin = (row['min_hrv'] as num? ?? 0).toInt();
          _histMax = (row['max_hrv'] as num? ?? 0).toInt();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _loadPeriodFromSupabase(int days) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() => _loadingHistory = true);
    try {
      final now = DateTime.now();
      final rows = await SupabaseService.getHrvHistory(
        userId: user.id,
        from: now.subtract(Duration(days: days - 1)),
        to: now,
      );

      final chartVals = List.generate(days, (i) {
        final day = now.subtract(Duration(days: days - 1 - i));
        final row = rows.firstWhere(
          (r) => r['date'] == _fmtDate(day),
          orElse: () => {},
        );
        return (row['avg_hrv'] as num? ?? 0).toInt();
      });

      final valid = rows.where((r) => (r['avg_hrv'] as num? ?? 0) > 0).toList();
      if (!mounted) return;
      if (valid.isEmpty) {
        setState(() {
          _histChartValues = chartVals;
          _histAvg = _histMin = _histMax = 0;
          _loadingHistory = false;
        });
        return;
      }

      final avg = (valid
                  .map((r) => (r['avg_hrv'] as num).toInt())
                  .reduce((a, b) => a + b) /
              valid.length)
          .round();
      final minVal = valid
          .map((r) => (r['min_hrv'] as num).toInt())
          .reduce((a, b) => a < b ? a : b);
      final maxVal = valid
          .map((r) => (r['max_hrv'] as num).toInt())
          .reduce((a, b) => a > b ? a : b);

      setState(() {
        _histChartValues = chartVals;
        _histAvg = avg;
        _histMin = minVal;
        _histMax = maxVal;
        _loadingHistory = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  // ── Chart label helpers ────────────────────────────────────────────────────

  String _chartTitle() {
    if (_period == 1) return 'LAST 7 DAYS';
    if (_period == 2) return 'LAST 30 DAYS';
    if (!_isToday) {
      const months = [
        'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
        'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
      ];
      return '${months[_selectedDate.month - 1]} ${_selectedDate.day}';
    }
    return 'TODAY';
  }

  List<String> _chartXLabels() {
    final now = DateTime.now();
    if (_period == 0) return ['12am', '6am', '12pm', '6pm', ''];
    if (_period == 1) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return List.generate(7, (i) {
        final d = now.subtract(Duration(days: 6 - i));
        return days[d.weekday - 1];
      });
    }
    return ['1', '5', '10', '15', '20', '25', '30'];
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;
    final anyLoading = _loading || _loadingHistory;
    final displayAvg = _displayAvg;
    final displayMin = _displayMin;
    final displayMax = _displayMax;
    final displayChart = _displayChart;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _darkBar('HRV'),
      body: RefreshIndicator(
        color: AppTheme.gold,
        backgroundColor: AppTheme.card,
        onRefresh: () async {
          if (connected) await _fetchTodayFromRing();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              if (_period == 0) ...[
                VitalDateSelector(
                  selectedDate: _selectedDate,
                  onDateSelected: _onDateSelected,
                ),
                const SizedBox(height: 12),
              ] else
                const SizedBox(height: 4),

              VitalPeriodTabs(onChanged: _onPeriodChanged),
              const SizedBox(height: 24),

              _metricCard(displayAvg),
              const SizedBox(height: 16),

              _chartCard(displayChart, anyLoading),
              const SizedBox(height: 16),

              VitalStatsRow(
                avg: displayAvg > 0 ? '$displayAvg' : '--',
                min: displayMin > 0 ? '$displayMin' : '--',
                max: displayMax > 0 ? '$displayMax' : '--',
                unit: 'ms',
              ),
              const SizedBox(height: 16),

              if (_period == 0 && _showRingData) ...[
                _slotReadingsList(displayChart),
                const SizedBox(height: 16),
              ],

              if (anyLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.gold, strokeWidth: 2)),
                ),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  // ── Widgets ────────────────────────────────────────────────────────────────

  Widget _metricCard(int displayAvg) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: AppTheme.hrvColor.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
                color: AppTheme.hrvColor.withValues(alpha: 0.15),
                shape: BoxShape.circle),
            child: const Icon(Icons.monitor_heart_rounded,
                color: AppTheme.hrvColor, size: 30),
          ),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('HEART RATE VARIABILITY',
                style: TextStyle(
                    color: AppTheme.hrvColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5)),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  _loading
                      ? '···'
                      : (displayAvg > 0 ? '$displayAvg' : '--'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 52,
                      fontWeight: FontWeight.w700,
                      height: 1.0),
                ),
                const SizedBox(width: 8),
                const Text('ms',
                    style:
                        TextStyle(color: AppTheme.textSec, fontSize: 16)),
              ],
            ),
            Text(
              _loading ? 'Syncing…' : _hrvLabel(displayAvg),
              style: TextStyle(
                  color: _loading
                      ? AppTheme.textSec
                      : _hrvColor(displayAvg),
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ]),
        ]),
      );

  Widget _chartCard(List<int> values, bool loading) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_chartTitle(),
                style: const TextStyle(
                    color: AppTheme.textSec,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
            const SizedBox(height: 12),
            SizedBox(
              height: 100,
              width: double.infinity,
              child: _buildChartContent(values, loading),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: _chartXLabels()
                  .map((l) => Text(l,
                      style: const TextStyle(
                          color: Color(0xFF555555), fontSize: 10)))
                  .toList(),
            ),
            const SizedBox(height: 10),
            const Row(children: [
              _LegendDot(color: AppTheme.danger, label: 'Very Low'),
              SizedBox(width: 10),
              _LegendDot(color: AppTheme.stressColor, label: 'Low'),
              SizedBox(width: 10),
              _LegendDot(
                  color: Color(0xFFFBBF24), label: 'Moderate'),
              SizedBox(width: 10),
              _LegendDot(color: AppTheme.success, label: 'Good'),
              SizedBox(width: 10),
              _LegendDot(color: AppTheme.hrvColor, label: 'Excellent'),
            ]),
          ],
        ),
      );

  Widget _buildChartContent(List<int> values, bool loading) {
    if (loading) {
      return const Center(
          child: CircularProgressIndicator(
              color: AppTheme.hrvColor, strokeWidth: 2));
    }
    final nonZero = values.where((v) => v > 0).toList();
    if (nonZero.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.monitor_heart_outlined,
              color: AppTheme.textSec.withValues(alpha: 0.3), size: 28),
          const SizedBox(height: 6),
          Text(
            _period == 0 && !_isToday
                ? 'No data saved for this day'
                : 'No data yet',
            style: const TextStyle(color: AppTheme.textSec, fontSize: 12),
          ),
        ]),
      );
    }
    return CustomPaint(painter: _HrvBarPainter(values: values));
  }

  Widget _slotReadingsList(List<int> values) {
    final entries = <(String, int)>[];
    for (int i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final minutes = i * 30;
      final dt = DateTime(_selectedDate.year, _selectedDate.month,
          _selectedDate.day, minutes ~/ 60, minutes % 60);
      entries.add((_fmtTime(dt), values[i]));
    }
    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
          color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text('READINGS',
              style: TextStyle(
                  color: AppTheme.textSec,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
        ),
        ...entries.asMap().entries.map((e) {
          final time = e.value.$1;
          final v = e.value.$2;
          final color = _hrvColor(v);
          final label = _hrvLabel(v);
          final isLast = e.key == entries.length - 1;
          return Column(children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.monitor_heart_rounded,
                      color: color, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(time,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                        Text(label,
                            style: TextStyle(color: color, fontSize: 11)),
                      ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('$v',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 22)),
                  const Text('ms',
                      style: TextStyle(
                          color: AppTheme.textSec, fontSize: 10)),
                ]),
              ]),
            ),
            if (!isLast)
              const Divider(color: AppTheme.div, height: 0.5, indent: 66),
          ]);
        }),
      ]),
    );
  }
}

// ── Chart painter ─────────────────────────────────────────────────────────────

class _HrvBarPainter extends CustomPainter {
  final List<int> values;
  const _HrvBarPainter({required this.values});

  static Color _barColor(int v) {
    if (v < 20) return AppTheme.danger;
    if (v < 40) return AppTheme.stressColor;
    if (v < 60) return const Color(0xFFFBBF24);
    if (v < 80) return AppTheme.success;
    return AppTheme.hrvColor;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final nonZero = values.where((v) => v > 0).toList();
    if (nonZero.isEmpty) return;

    final maxVal = nonZero.reduce((a, b) => a > b ? a : b).toDouble();
    final n = values.length;
    final slotW = size.width / n;
    final barW = (slotW * 0.7).clamp(1.0, 8.0);
    final gap = slotW - barW;

    for (int i = 0; i < n; i++) {
      if (values[i] <= 0) continue;
      final normalized = (values[i] / maxVal).clamp(0.0, 1.0);
      final barH =
          (normalized * size.height * 0.9).clamp(2.0, size.height);
      final x = i * slotW + gap / 2;
      canvas.drawRRect(
        RRect.fromLTRBR(x, size.height - barH, x + barW, size.height,
            const Radius.circular(2)),
        Paint()
          ..color = _barColor(values[i])
              .withValues(alpha: (0.5 + normalized * 0.5).clamp(0.5, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(_HrvBarPainter old) => old.values != values;
}

// ── Supporting widgets ────────────────────────────────────────────────────────

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
          Text(label,
              style:
                  const TextStyle(color: AppTheme.textSec, fontSize: 9)),
        ],
      );
}

AppBar _darkBar(String title) => AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600)),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Container(color: AppTheme.div, height: 0.5),
      ),
    );
