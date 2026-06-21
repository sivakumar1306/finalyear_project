import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vital_widgets.dart';

class BloodOxygenScreen extends StatefulWidget {
  const BloodOxygenScreen({super.key});
  @override
  State<BloodOxygenScreen> createState() => _BloodOxygenScreenState();
}

class _BloodOxygenScreenState extends State<BloodOxygenScreen> {
  final _ble = BleService();

  // Period / date selection
  int _period = 0;
  DateTime _selectedDate = DateTime.now();

  // Loading states
  bool _loading = false;
  bool _loadingHistory = false;
  bool _measuring = false;

  // Raw result
  String _result = '';

  // Settings
  bool _settingEnabled = true;
  int _settingInterval = 5;

  // Ring / today data
  List<int> _chartValues = [];
  int _avgSpo2 = 0, _minSpo2 = 0, _maxSpo2 = 0;

  // Supabase / historical data
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
  int get _displayAvg => _showRingData ? _avgSpo2 : _histAvg;
  int get _displayMin => _showRingData ? _minSpo2 : _histMin;
  int get _displayMax => _showRingData ? _maxSpo2 : _histMax;

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Init ───────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.read<BleProvider>().isConnected) {
        // Fetch data first; load settings only after the data command completes
        // so BloodOxygenSettingReq doesn't block the CommandHandle queue before
        // getTodayBloodOxygen is dispatched.
        _fetchToday().then((_) {
          if (mounted) _loadSettings();
        });
      }
    });
  }

  // ── Period / date handlers ─────────────────────────────────────────────────

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
      final data = await _ble.getTodayBloodOxygen();
      setState(() => _result = _pretty(data));
      _parseSpo2Data(data);
    } catch (e) {
      setState(() => _result = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _parseSpo2Data(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded == null || decoded is! Map<String, dynamic>) return;

      // BloodOxygenEntity fields (not ProGuard-obfuscated):
      // maxArray: List<int> size 24 (one per hour), minArray: List<int> size 24
      final maxRaw = (decoded['maxArray'] as List<dynamic>? ?? [])
          .map((v) => (v as num).toInt())
          .toList();
      final minRaw = (decoded['minArray'] as List<dynamic>? ?? [])
          .map((v) => (v as num).toInt())
          .toList();

      final readings = maxRaw.where((v) => v > 0).toList();
      if (readings.isEmpty) return;

      final avg = (readings.reduce((a, b) => a + b) / readings.length).round();
      final maxVal = readings.reduce((a, b) => a > b ? a : b);
      final minReadings = minRaw.where((v) => v > 0).toList();
      final minVal = minReadings.isNotEmpty
          ? minReadings.reduce((a, b) => a < b ? a : b)
          : readings.reduce((a, b) => a < b ? a : b);

      if (!mounted) return;
      setState(() {
        _chartValues = maxRaw;
        _avgSpo2 = avg;
        _minSpo2 = minVal;
        _maxSpo2 = maxVal;
        _selectedDate = DateTime.now();
      });

      context.read<BleProvider>().updateSpo2Data(avg, minVal, maxVal);
      _saveToSupabase(avg, minVal, maxVal, readings.length);
    } catch (e) {
      if (mounted) setState(() => _result = 'Parse error: $e');
    }
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

  // ── Supabase fetches ───────────────────────────────────────────────────────

  Future<void> _loadPeriodFromSupabase(int days) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() => _loadingHistory = true);
    try {
      final now = DateTime.now();
      final rows = await SupabaseService.getSpo2History(
        userId: user.id,
        from: now.subtract(Duration(days: days - 1)),
        to: now,
      );

      final chartVals = List.generate(days, (i) {
        final day = now.subtract(Duration(days: days - 1 - i));
        final row = rows.firstWhere(
          (r) => r['date'] == _fmt(day),
          orElse: () => {},
        );
        return (row['avg_spo2'] as num? ?? 0).toInt();
      });

      final valid = rows.where((r) => r['avg_spo2'] != null).toList();
      if (valid.isEmpty) {
        setState(() {
          _histChartValues = chartVals;
          _histAvg = _histMin = _histMax = 0;
          _loadingHistory = false;
        });
        return;
      }

      final avg = (valid.map((r) => (r['avg_spo2'] as num).toInt()).reduce((a, b) => a + b) /
              valid.length)
          .round();
      final minVal =
          valid.map((r) => (r['min_spo2'] as num).toInt()).reduce((a, b) => a < b ? a : b);
      final maxVal =
          valid.map((r) => (r['max_spo2'] as num).toInt()).reduce((a, b) => a > b ? a : b);

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
      final row = await SupabaseService.getSpo2ForDate(user.id, date);
      if (!mounted) return;
      if (row != null) {
        setState(() {
          _histAvg = (row['avg_spo2'] as num? ?? 0).toInt();
          _histMin = (row['min_spo2'] as num? ?? 0).toInt();
          _histMax = (row['max_spo2'] as num? ?? 0).toInt();
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
      final json = await _ble.getBloodOxygenSetting();
      final m = jsonDecode(json);
      setState(() {
        _settingEnabled = m['enable'] ?? true;
        _settingInterval = m['interval'] ?? 5;
      });
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      await _ble.setBloodOxygenSetting(enable: _settingEnabled, interval: _settingInterval);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _toggleManual() async {
    final start = !_measuring;
    setState(() => _measuring = start);
    try {
      final result = await _ble.manualModeBloodOxygen(start: start);
      final pretty = _pretty(result);
      int liveVal = 0;
      try {
        final m = jsonDecode(result) as Map<String, dynamic>;
        liveVal = (m['spo2'] as num?)?.toInt() ?? 0;
      } catch (_) {}
      setState(() {
        _result = pretty;
        _measuring = false;
        if (liveVal > 0 && _period == 0 && _isToday) _avgSpo2 = liveVal;
      });
    } catch (e) {
      final msg = e.toString().contains('TIMEOUT')
          ? 'Measurement timed out. Make sure the ring is worn properly.'
          : 'Error: $e';
      setState(() { _measuring = false; _result = msg; });
    }
  }

  String _pretty(String raw) {
    try { return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw)); } catch (_) { return raw; }
  }

  // ── Chart label helpers ────────────────────────────────────────────────────

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
      appBar: _darkBar('Blood Oxygen'),
      body: SingleChildScrollView(
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

            // Metric card
            _metricCard(displayAvg),
            const SizedBox(height: 16),

            // Chart card
            _chartCard(displayChart, anyLoading),
            const SizedBox(height: 16),

            // Stats row
            VitalStatsRow(
              avg: displayAvg > 0 ? '$displayAvg' : '--',
              min: displayMin > 0 ? '$displayMin' : '--',
              max: displayMax > 0 ? '$displayMax' : '--',
              unit: '%',
            ),
            const SizedBox(height: 24),

            // Measurement buttons (Day view only)
            if (_period == 0) ...[
              VitalOneClickButton(
                label: _measuring ? 'Stop Measurement' : 'One Click Measurement',
                isStop: _measuring,
                loading: _loading && _measuring,
                enabled: connected,
                onPressed: _toggleManual,
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _Btn(
                  label: "Today's Data",
                  icon: Icons.sync_rounded,
                  enabled: connected && !_loading,
                  onTap: _fetchToday,
                )),
                const SizedBox(width: 10),
                Expanded(child: _Btn(
                  label: 'Sync Interval',
                  icon: Icons.download_rounded,
                  enabled: connected && !_loading,
                  onTap: _syncInterval,
                )),
              ]),
              const SizedBox(height: 16),
            ],

            _monitorCard(),

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

  Future<void> _syncInterval() async {
    setState(() { _loading = true; _result = ''; });
    try {
      final data = await _ble.syncIntervalBloodOxygen();
      setState(() => _result = _pretty(data));
    } catch (e) {
      setState(() => _result = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _metricCard(int displayAvg) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.spo2Color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                  color: AppTheme.spo2Color.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: const Icon(Icons.bloodtype_rounded, color: AppTheme.spo2Color, size: 30),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('BLOOD OXYGEN (SpO₂)',
                    style: TextStyle(
                        color: AppTheme.spo2Color,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5)),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      _measuring ? '···' : (displayAvg > 0 ? '$displayAvg' : '--'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 52,
                          fontWeight: FontWeight.w700,
                          height: 1.0),
                    ),
                    const SizedBox(width: 8),
                    const Text('%', style: TextStyle(color: AppTheme.textSec, fontSize: 16)),
                  ],
                ),
                Text(
                  _measuring
                      ? 'Measuring…'
                      : displayAvg > 0
                          ? (_period == 0
                              ? (_isToday ? "Today's average" : 'Daily average')
                              : (_period == 1 ? '7-day average' : '30-day average'))
                          : 'Oxygen saturation',
                  style: const TextStyle(color: AppTheme.textSec, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _chartCard(List<int> values, bool loading) => Container(
        padding: const EdgeInsets.all(16),
        decoration:
            BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
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
                      style: const TextStyle(color: Color(0xFF555555), fontSize: 10)))
                  .toList(),
            ),
          ],
        ),
      );

  Widget _buildChartContent(List<int> values, bool loading) {
    if (loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.spo2Color, strokeWidth: 2));
    }
    final nonZero = values.where((v) => v > 0).toList();
    if (nonZero.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.bloodtype_outlined,
              color: AppTheme.textSec.withValues(alpha: 0.3), size: 28),
          const SizedBox(height: 6),
          Text(
            _period == 0 && !_isToday ? 'No data saved for this day' : 'No data yet',
            style: const TextStyle(color: AppTheme.textSec, fontSize: 12),
          ),
        ]),
      );
    }
    return CustomPaint(painter: _SpO2BarPainter(values: values));
  }

  Widget _monitorCard() => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.div)),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Auto Monitoring',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    SizedBox(height: 2),
                    Text('Monitors SpO₂ automatically',
                        style: TextStyle(color: AppTheme.textSec, fontSize: 12)),
                  ],
                )),
                Switch.adaptive(
                    value: _settingEnabled,
                    onChanged: (v) {
                      setState(() => _settingEnabled = v);
                      _saveSettings();
                    }),
              ],
            ),
            if (_settingEnabled) ...[
              const Divider(color: AppTheme.div, height: 16),
              Row(
                children: [
                  const Text('Interval',
                      style: TextStyle(color: Colors.white, fontSize: 14)),
                  const Spacer(),
                  DropdownButton<int>(
                    value: _settingInterval,
                    dropdownColor: AppTheme.card2,
                    style: const TextStyle(color: Colors.white),
                    underline: const SizedBox(),
                    items: [1, 5, 10, 15, 30]
                        .map((e) => DropdownMenuItem(value: e, child: Text('$e min')))
                        .toList(),
                    onChanged: (v) => setState(() => _settingInterval = v ?? 5),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                      onPressed: _saveSettings,
                      child: const Text('Save',
                          style: TextStyle(color: AppTheme.gold))),
                ],
              ),
            ],
          ],
        ),
      );
}

// ── SpO2 bar chart painter ────────────────────────────────────────────────────
// Uses a 85–100% baseline so small variations are clearly visible.

class _SpO2BarPainter extends CustomPainter {
  final List<int> values;
  static const double _baseline = 85.0;
  static const double _range = 15.0; // 85–100

  const _SpO2BarPainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final n = values.length;
    final slotW = size.width / n;
    final barW = (slotW * 0.7).clamp(1.0, 8.0);
    final gap = slotW - barW;

    for (int i = 0; i < n; i++) {
      if (values[i] <= 0) continue;
      final normalized = ((values[i] - _baseline) / _range).clamp(0.0, 1.0);
      final barH = (normalized * size.height * 0.9).clamp(2.0, size.height);
      final x = i * slotW + gap / 2;
      canvas.drawRRect(
        RRect.fromLTRBR(x, size.height - barH, x + barW, size.height, const Radius.circular(2)),
        Paint()
          ..color = AppTheme.spo2Color.withValues(alpha: (0.4 + normalized * 0.6).clamp(0.4, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(_SpO2BarPainter old) => old.values != values;
}

// ── Shared helpers ────────────────────────────────────────────────────────────

AppBar _darkBar(String title) => AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      actions: [
        IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white), onPressed: () {})
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Container(color: AppTheme.div, height: 0.5),
      ),
    );

class _Btn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  const _Btn({required this.label, required this.icon, required this.enabled, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.div)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: enabled ? AppTheme.gold : AppTheme.textSec, size: 18),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      color: enabled ? Colors.white : AppTheme.textSec,
                      fontWeight: FontWeight.w500,
                      fontSize: 14)),
            ],
          ),
        ),
      );
}
