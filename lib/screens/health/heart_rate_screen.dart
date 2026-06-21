import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vital_widgets.dart';

class HeartRateScreen extends StatefulWidget {
  const HeartRateScreen({super.key});
  @override
  State<HeartRateScreen> createState() => _HeartRateScreenState();
}

class _HeartRateScreenState extends State<HeartRateScreen> {
  final _ble = BleService();

  // Period / date selection
  int _period = 0; // 0=Day, 1=Week, 2=Month
  DateTime _selectedDate = DateTime.now();

  // Loading states
  bool _loading = false;         // ring fetch
  bool _loadingHistory = false;  // Supabase fetch
  bool _measuring = false;

  // Raw result card
  String _result = '';

  // Settings
  bool _settingEnabled = true;
  int _settingInterval = 5;

  // Ring / today data (Day tab + today selected)
  List<int> _chartValues = [];
  int _avgHr = 0, _minHr = 0, _maxHr = 0;

  // Supabase data (Week, Month, or past day)
  List<int> _histChartValues = [];
  int _histAvg = 0, _histMin = 0, _histMax = 0;

  // ── Helpers ────────────────────────────────────────────────────────────────

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  bool get _showRingData => _period == 0 && _isToday;

  List<int> get _displayChart => _showRingData ? _chartValues : _histChartValues;
  int get _displayAvg => _showRingData ? _avgHr : _histAvg;
  int get _displayMin => _showRingData ? _minHr : _histMin;
  int get _displayMax => _showRingData ? _maxHr : _histMax;

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Init ───────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.read<BleProvider>().isConnected) {
        _fetchToday();
      }
    });
  }

  // ── Period / date change handlers ──────────────────────────────────────────

  void _onPeriodChanged(int p) {
    setState(() {
      _period = p;
      _result = '';
      _histChartValues = [];
      _histAvg = _histMin = _histMax = 0;
    });
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
      _result = '';
      if (!isToday) {
        _histChartValues = [];
        _histAvg = _histMin = _histMax = 0;
      }
    });
    if (!isToday) _loadDayFromSupabase(date);
  }

  // ── Ring fetch ─────────────────────────────────────────────────────────────

  Future<void> _fetchToday() async {
    setState(() { _loading = true; _result = ''; });
    try {
      final data = await _ble.getTodayHeartRate();
      setState(() => _result = _pretty(data));
      _parseHrData(data);
    } catch (e) {
      setState(() => _result = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _parseHrData(String jsonStr) {
    try {
      final m = jsonDecode(jsonStr) as Map<String, dynamic>;
      final raw = (m['e'] as List<dynamic>? ?? [])
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
        _avgHr = avg;
        _minHr = minVal;
        _maxHr = maxVal;
        _selectedDate = DateTime.now(); // snap to today
      });

      context.read<BleProvider>().updateHrData(avg, minVal, maxVal);
      _saveHrToSupabase(avg, minVal, maxVal, readings.length);
    } catch (e) {
      if (mounted) setState(() => _result = 'Parse error: $e');
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

  // ── Supabase fetches ───────────────────────────────────────────────────────

  Future<void> _loadPeriodFromSupabase(int days) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() => _loadingHistory = true);
    try {
      final now = DateTime.now();
      final rows = await SupabaseService.getHrHistory(
        userId: user.id,
        from: now.subtract(Duration(days: days - 1)),
        to: now,
      );

      // Build per-day avg chart values (0 if no data that day)
      final chartVals = List.generate(days, (i) {
        final day = now.subtract(Duration(days: days - 1 - i));
        final row = rows.firstWhere(
          (r) => r['date'] == _fmt(day),
          orElse: () => {},
        );
        return (row['avg_hr'] as num? ?? 0).toInt();
      });

      // Aggregate stats across all days that have data
      final valid = rows.where((r) => r['avg_hr'] != null).toList();
      if (valid.isEmpty) {
        setState(() {
          _histChartValues = chartVals;
          _histAvg = _histMin = _histMax = 0;
          _loadingHistory = false;
        });
        return;
      }

      final avg = (valid.map((r) => (r['avg_hr'] as num).toInt()).reduce((a, b) => a + b) /
              valid.length)
          .round();
      final minVal =
          valid.map((r) => (r['min_hr'] as num).toInt()).reduce((a, b) => a < b ? a : b);
      final maxVal =
          valid.map((r) => (r['max_hr'] as num).toInt()).reduce((a, b) => a > b ? a : b);

      if (!mounted) return;
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

  Future<void> _loadDayFromSupabase(DateTime date) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() => _loadingHistory = true);
    try {
      final row = await SupabaseService.getHrForDate(user.id, date);
      if (!mounted) return;
      if (row != null) {
        setState(() {
          _histAvg = (row['avg_hr'] as num? ?? 0).toInt();
          _histMin = (row['min_hr'] as num? ?? 0).toInt();
          _histMax = (row['max_hr'] as num? ?? 0).toInt();
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  // ── Settings ───────────────────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    if (!context.read<BleProvider>().isConnected) return;
    try {
      final json = await _ble.getHeartRateSetting();
      final m = jsonDecode(json);
      setState(() {
        _settingEnabled = m['enable'] ?? true;
        _settingInterval = m['interval'] ?? 5;
      });
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      await _ble.setHeartRateSetting(enable: _settingEnabled, interval: _settingInterval);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _toggleManual() async {
    final start = !_measuring;
    setState(() => _measuring = start);
    try {
      final result = await _ble.manualModeHeart(start: start);
      setState(() { _result = _pretty(result); _measuring = false; });
    } catch (e) {
      setState(() { _measuring = false; _result = 'Error: $e'; });
    }
  }

  String _pretty(String raw) {
    try { return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw)); } catch (_) { return raw; }
  }

  // ── Chart helpers ──────────────────────────────────────────────────────────

  String _chartTitle() {
    if (_period == 1) return 'LAST 7 DAYS';
    if (_period == 2) return 'LAST 30 DAYS';
    if (!_isToday) {
      const months = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
      return '${months[_selectedDate.month - 1]} ${_selectedDate.day}';
    }
    return 'TODAY';
  }

  List<String> _chartXLabels() {
    final now = DateTime.now();
    if (_period == 0) return ['12am', '6am', '12pm', '6pm'];
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
      appBar: _darkBar('Heart Rate'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),

            // Date selector only visible in Day view
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

            // Big metric card
            _VitalMetricCard(
              color: AppTheme.hrColor,
              icon: Icons.favorite_rounded,
              label: 'HEART RATE',
              value: _measuring ? '···' : (displayAvg > 0 ? '$displayAvg' : '--'),
              unit: 'bpm',
              status: _measuring
                  ? 'Measuring…'
                  : displayAvg > 0
                      ? (_period == 0
                          ? (_isToday ? "Today's average" : 'Daily average')
                          : (_period == 1 ? '7-day average' : '30-day average'))
                      : 'Tap to load',
            ),
            const SizedBox(height: 16),

            // Chart card
            _ChartCard(
              title: _chartTitle(),
              chart: SizedBox(
                height: 100,
                width: double.infinity,
                child: _buildChartContent(displayChart, anyLoading),
              ),
              xLabels: _chartXLabels(),
            ),
            const SizedBox(height: 16),

            // Stats row — always shown
            VitalStatsRow(
              avg: displayAvg > 0 ? '$displayAvg' : '--',
              min: displayMin > 0 ? '$displayMin' : '--',
              max: displayMax > 0 ? '$displayMax' : '--',
              unit: 'bpm',
            ),
            const SizedBox(height: 24),

            // One-click measurement (Day view only)
            if (_period == 0) ...[
              VitalOneClickButton(
                label: _measuring ? 'Stop Measurement' : 'One Click Measurement',
                isStop: _measuring,
                loading: _loading && _measuring,
                enabled: connected,
                onPressed: _toggleManual,
              ),
              const SizedBox(height: 12),
              _SecondaryButton(
                label: "Today's Data",
                icon: Icons.sync_rounded,
                enabled: connected && !_loading,
                onTap: _fetchToday,
              ),
              const SizedBox(height: 16),
            ],

            _MonitoringCard(
              title: 'Auto Monitoring',
              subtitle: 'Monitors heart rate automatically',
              enabled: _settingEnabled,
              interval: _settingInterval,
              intervalOptions: const [1, 5, 10, 15, 30, 60],
              onToggle: (v) { setState(() => _settingEnabled = v); _saveSettings(); },
              onIntervalChange: (v) => setState(() => _settingInterval = v ?? 5),
              onSave: _saveSettings,
            ),

            if (_loading && !_measuring)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(color: AppTheme.gold, strokeWidth: 2)),
              ),

            if (_result.isNotEmpty && _period == 0)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.card2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.div),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('DATA', style: TextStyle(color: AppTheme.textSec, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text(_result, style: const TextStyle(fontFamily: 'monospace', color: AppTheme.textSec, fontSize: 11)),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildChartContent(List<int> values, bool loading) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.hrColor, strokeWidth: 2),
      );
    }
    final nonZero = values.where((v) => v > 0).toList();
    if (nonZero.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.favorite_border,
              color: AppTheme.textSec.withValues(alpha: 0.3), size: 28),
          const SizedBox(height: 6),
          Text(
            _period == 0 && !_isToday ? 'No data saved for this day' : 'No data yet',
            style: const TextStyle(color: AppTheme.textSec, fontSize: 12),
          ),
        ]),
      );
    }
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    return CustomPaint(
      painter: _HRBarPainter(values: values, maxVal: maxVal),
    );
  }
}

// ── HR bar chart painter ─────────────────────────────────────────────────────

class _HRBarPainter extends CustomPainter {
  final List<int> values;
  final int maxVal;

  const _HRBarPainter({required this.values, required this.maxVal});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || maxVal == 0) return;
    final n = values.length;
    final slotW = size.width / n;
    final barW = (slotW * 0.7).clamp(1.0, 8.0);
    final gap = slotW - barW;

    for (int i = 0; i < n; i++) {
      if (values[i] <= 0) continue;
      final ratio = values[i] / maxVal;
      final barH = (ratio * size.height * 0.9).clamp(2.0, size.height);
      final x = i * slotW + gap / 2;
      canvas.drawRRect(
        RRect.fromLTRBR(x, size.height - barH, x + barW, size.height, const Radius.circular(2)),
        Paint()..color = AppTheme.hrColor.withValues(alpha: (0.35 + ratio * 0.65).clamp(0.35, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(_HRBarPainter old) => old.values != values || old.maxVal != maxVal;
}

// ── Shared file-scope helpers ────────────────────────────────────────────────

AppBar _darkBar(String title) => AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      actions: [IconButton(icon: const Icon(Icons.more_vert, color: Colors.white), onPressed: () {})],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Container(color: AppTheme.div, height: 0.5),
      ),
    );

// ── Private widgets ──────────────────────────────────────────────────────────

class _VitalMetricCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final String status;

  const _VitalMetricCard({
    required this.color, required this.icon, required this.label,
    required this.value, required this.unit, required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value, style: const TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w700, height: 1.0)),
                  const SizedBox(width: 8),
                  Text(unit, style: const TextStyle(color: AppTheme.textSec, fontSize: 16)),
                ],
              ),
              Text(status, style: const TextStyle(color: AppTheme.textSec, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final Widget chart;
  final List<String> xLabels;

  const _ChartCard({required this.title, required this.chart, required this.xLabels});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppTheme.textSec, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 12),
          chart,
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: xLabels.map((l) => Text(l, style: const TextStyle(color: Color(0xFF555555), fontSize: 10))).toList(),
          ),
        ],
      ),
    );
  }
}

class _MonitoringCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool enabled;
  final int interval;
  final List<int> intervalOptions;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int?> onIntervalChange;
  final VoidCallback onSave;

  const _MonitoringCard({
    required this.title, required this.subtitle, required this.enabled,
    required this.interval, required this.intervalOptions,
    required this.onToggle, required this.onIntervalChange, required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.div),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: AppTheme.textSec, fontSize: 12)),
                  ],
                ),
              ),
              Switch.adaptive(value: enabled, onChanged: onToggle),
            ],
          ),
          if (enabled) ...[
            const Divider(color: AppTheme.div, height: 16),
            Row(
              children: [
                const Text('Interval', style: TextStyle(color: Colors.white, fontSize: 14)),
                const Spacer(),
                DropdownButton<int>(
                  value: interval,
                  dropdownColor: AppTheme.card2,
                  style: const TextStyle(color: Colors.white),
                  underline: const SizedBox(),
                  items: intervalOptions.map((e) => DropdownMenuItem(value: e, child: Text('$e min'))).toList(),
                  onChanged: onIntervalChange,
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onSave,
                  child: const Text('Save', style: TextStyle(color: AppTheme.gold)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  const _SecondaryButton({required this.label, required this.icon, required this.enabled, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.div),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: enabled ? AppTheme.gold : AppTheme.textSec, size: 18),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: enabled ? Colors.white : AppTheme.textSec, fontWeight: FontWeight.w500, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
