import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vital_widgets.dart';
import '../../widgets/offline_notice.dart';

class TemperatureScreen extends StatefulWidget {
  const TemperatureScreen({super.key});
  @override
  State<TemperatureScreen> createState() => _TemperatureScreenState();
}

class _TemperatureScreenState extends State<TemperatureScreen> {
  final _ble = BleService();

  int _period = 0;
  DateTime _selectedDate = DateTime.now();

  bool _syncing = false;
  bool _loadingHistory = false;
  bool _historyOffline = false;

  // Ring-derived readings for today (before Supabase save)
  List<_TempReading> _ringReadings = [];
  double _ringAvg = 0, _ringMin = 0, _ringMax = 0;

  // Supabase readings
  List<Map<String, dynamic>> _dbReadings = [];
  double _histAvg = 0, _histMin = 0, _histMax = 0;

  // Settings
  bool _settingEnabled = true;
  int _settingIntervalSec = 5;

  // Raw JSON for debug viewer
  String _rawJson = '';
  bool _jsonExpanded = true;

  // ── Helpers ────────────────────────────────────────────────────────────────

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  bool get _showRingData =>
      _period == 0 && _isToday && _ringReadings.isNotEmpty;

  double get _displayAvg => _showRingData ? _ringAvg : _histAvg;
  double get _displayMin => _showRingData ? _ringMin : _histMin;
  double get _displayMax => _showRingData ? _ringMax : _histMax;

  static String _tempLabel(double v) {
    if (v <= 0) return 'No data';
    if (v < 36.0) return 'Low';
    if (v <= 37.2) return 'Normal';
    if (v <= 38.0) return 'Elevated';
    return 'Fever';
  }

  static Color _tempColor(double v) {
    if (v <= 0) return AppTheme.textSec;
    if (v < 36.0) return AppTheme.spo2Color;
    if (v <= 37.2) return AppTheme.success;
    if (v <= 38.0) return const Color(0xFFFBBF24);
    return AppTheme.danger;
  }

  static String _fmtTime(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = h < 12 ? 'AM' : 'PM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$m $ampm';
  }

  // ── Init ───────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadTodayFromSupabase();
      if (context.read<BleProvider>().isConnected) {
        _loadSettings();
        _syncAuto(); // fetch live from ring and populate JSON viewer
      }
    });
  }

  // ── Period / date handlers ─────────────────────────────────────────────────

  void _onPeriodChanged(int p) {
    setState(() {
      _period = p;
      _dbReadings = [];
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
        _dbReadings = [];
        _histAvg = _histMin = _histMax = 0;
      }
    });
    if (!isToday) _loadDayFromSupabase(date);
  }

  // ── Ring fetch ─────────────────────────────────────────────────────────────

  Future<void> _fetchTodayData() async {
    setState(() => _syncing = true);
    try {
      final data = await _ble.getTodayTemperature();
      _setRawJson('getTodayTemperature', data);
      _parseTempPayload(data, source: 'auto');
    } catch (e) {
      _setRawJson('getTodayTemperature ERROR', e.toString());
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _syncAuto() async {
    setState(() => _syncing = true);
    try {
      final data = await _ble.syncAutoTemperature();
      _setRawJson('syncAutoTemperature (TemperatureEntity)', data);
      _parseTempPayload(data, source: 'auto');
    } catch (e) {
      _setRawJson('syncAutoTemperature ERROR', e.toString());
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _syncManual() async {
    setState(() => _syncing = true);
    try {
      final data = await _ble.syncManualTemperature();
      _setRawJson('syncManualTemperature (TemperatureOnceEntity[])', data);
      _parseTempPayload(data, source: 'manual');
    } catch (e) {
      _setRawJson('syncManualTemperature ERROR', e.toString());
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _setRawJson(String label, String raw) {
    String pretty = raw;
    try {
      final decoded = jsonDecode(raw);
      pretty = const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {}
    if (mounted) setState(() => _rawJson = '// $label\n$pretty');
  }

  // ── Payload parsing ────────────────────────────────────────────────────────

  void _parseTempPayload(String jsonStr, {required String source}) {
    try {
      final decoded = jsonDecode(jsonStr);
      final readings = <_TempReading>[];

      if (decoded is List && decoded.isNotEmpty) {
        // TemperatureOnceEntity list: [{mTime, mValue}, ...]
        for (final item in decoded) {
          final m = item as Map<String, dynamic>;
          final ts = (m['mTime'] as num?)?.toInt() ?? (m['a'] as num?)?.toInt();
          var val = (m['mValue'] as num?)?.toDouble() ?? (m['b'] as num?)?.toDouble();
          if (ts == null || val == null || val <= 0) continue;
          // SDK: value from StartHeartRateRsp needs /10; TemperatureOnceEntity is already °C
          if (val > 100) val /= 10;
          readings.add(_TempReading(
            time: DateTime.fromMillisecondsSinceEpoch(ts * 1000).toLocal(),
            valueC: val,
            source: source,
          ));
        }
      } else if (decoded is Map<String, dynamic>) {
        // TemperatureEntity: {mValues, mTimeSpan, mIndex} or obfuscated {d, b, a}
        final rawVals = (decoded['mValues'] as List<dynamic>?)
            ?? (decoded['d'] as List<dynamic>?);
        final spanSec = (decoded['mTimeSpan'] as num?)?.toInt()
            ?? (decoded['b'] as num?)?.toInt()
            ?? 5;
        if (rawVals != null) {
          final base = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
          for (int i = 0; i < rawVals.length; i++) {
            var v = (rawVals[i] as num).toDouble();
            if (v <= 0) continue;
            if (v > 100) v /= 10;
            readings.add(_TempReading(
              time: base.add(Duration(seconds: i * spanSec)),
              valueC: v,
              source: source,
            ));
          }
        }
      }

      if (readings.isEmpty) return;

      final vals = readings.map((r) => r.valueC).toList();
      final avg = vals.reduce((a, b) => a + b) / vals.length;
      final minVal = vals.reduce((a, b) => a < b ? a : b);
      final maxVal = vals.reduce((a, b) => a > b ? a : b);

      if (!mounted) return;
      setState(() {
        _ringReadings = readings;
        _ringAvg = avg;
        _ringMin = minVal;
        _ringMax = maxVal;
        _selectedDate = DateTime.now();
      });

      _saveToSupabase(readings);
    } catch (_) {}
  }

  Future<void> _saveToSupabase(List<_TempReading> readings) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.insertTempBatch(
        userId: user.id,
        readings: readings
            .map((r) => (measuredAt: r.time, valueC: r.valueC, source: r.source))
            .toList(),
      );
      await _loadTodayFromSupabase();
    } catch (_) {}
  }

  // ── Supabase fetches ───────────────────────────────────────────────────────

  Future<void> _loadTodayFromSupabase() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() { _loadingHistory = true; _historyOffline = false; });
    try {
      final now = DateTime.now();
      final rows = await SupabaseService.getTempReadings(
        userId: user.id,
        from: DateTime(now.year, now.month, now.day),
        to: DateTime(now.year, now.month, now.day, 23, 59, 59),
      );
      if (mounted) _applyDbReadings(rows);
    } catch (e) {
      if (mounted && isNetworkError(e)) setState(() => _historyOffline = true);
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _loadDayFromSupabase(DateTime date) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() { _loadingHistory = true; _historyOffline = false; });
    try {
      final rows = await SupabaseService.getTempReadings(
        userId: user.id,
        from: DateTime(date.year, date.month, date.day),
        to: DateTime(date.year, date.month, date.day, 23, 59, 59),
      );
      if (mounted) _applyDbReadings(rows);
    } catch (e) {
      if (mounted && isNetworkError(e)) setState(() => _historyOffline = true);
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _loadPeriodFromSupabase(int days) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() { _loadingHistory = true; _historyOffline = false; });
    try {
      final now = DateTime.now();
      final rows = await SupabaseService.getTempReadings(
        userId: user.id,
        from: now.subtract(Duration(days: days - 1)),
        to: now,
      );
      if (mounted) _applyDbReadings(rows);
    } catch (e) {
      if (mounted && isNetworkError(e)) setState(() => _historyOffline = true);
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  void _applyDbReadings(List<Map<String, dynamic>> rows) {
    final vals =
        rows.map((r) => (r['value_c'] as num? ?? 0).toDouble()).where((v) => v > 0).toList();
    setState(() {
      _dbReadings = rows;
      _histAvg = vals.isEmpty ? 0 : vals.reduce((a, b) => a + b) / vals.length;
      _histMin = vals.isEmpty ? 0 : vals.reduce((a, b) => a < b ? a : b);
      _histMax = vals.isEmpty ? 0 : vals.reduce((a, b) => a > b ? a : b);
    });
  }

  // ── Settings ───────────────────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    try {
      final json = await _ble.getTemperatureSetting();
      final m = jsonDecode(json) as Map<String, dynamic>;
      setState(() {
        _settingEnabled = m['enable'] as bool? ?? true;
        _settingIntervalSec = (m['interval'] as num?)?.toInt() ?? 5;
      });
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      await _ble.setTemperatureSetting(
          enable: _settingEnabled, interval: _settingIntervalSec);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Settings saved')));
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    final String clean;
    if (msg.contains('TIMEOUT')) {
      clean = 'Ring timed out — wear it snugly and try again.';
    } else if (msg.contains('ACTION_FAILED')) {
      clean = 'Ring rejected sync — see JSON viewer for error code.';
    } else {
      clean = msg.length > 100 ? msg.substring(0, 100) : msg;
    }
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(clean), backgroundColor: AppTheme.danger));
  }

  // ── Chart helpers ──────────────────────────────────────────────────────────

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
    final anyLoading = _syncing || _loadingHistory;
    final displayAvg = _displayAvg;
    final displayMin = _displayMin;
    final displayMax = _displayMax;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _darkBar('Temperature'),
      body: RefreshIndicator(
        color: AppTheme.gold,
        backgroundColor: AppTheme.card,
        onRefresh: () async {
          if (connected) await _fetchTodayData();
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

              if (_historyOffline && !_showRingData) ...[
                const OfflineNotice(message: 'Connect to WiFi to load temperature history'),
                const SizedBox(height: 16),
              ],

              _chartCard(anyLoading),
              const SizedBox(height: 16),

              VitalStatsRow(
                avg: displayAvg > 0 ? displayAvg.toStringAsFixed(1) : '--',
                min: displayMin > 0 ? displayMin.toStringAsFixed(1) : '--',
                max: displayMax > 0 ? displayMax.toStringAsFixed(1) : '--',
                unit: '°C',
              ),
              const SizedBox(height: 16),

              if (_period == 0) ...[
                _readingsList(),
                const SizedBox(height: 16),
              ],

              _syncCard(connected),
              const SizedBox(height: 12),

              if (_period == 0) _monitorCard(connected),

              if (anyLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.gold, strokeWidth: 2)),
                ),

              const SizedBox(height: 16),
              _jsonViewerCard(),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  // ── Widgets ────────────────────────────────────────────────────────────────

  Widget _metricCard(double displayAvg) {
    final color = _tempColor(displayAvg);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.tempColor.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
          child: Icon(Icons.thermostat_rounded, color: color, size: 30),
        ),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('BODY TEMPERATURE',
              style: TextStyle(
                  color: AppTheme.tempColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _syncing
                    ? '···'
                    : (displayAvg > 0 ? displayAvg.toStringAsFixed(1) : '--'),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 52,
                    fontWeight: FontWeight.w700,
                    height: 1.0),
              ),
              const SizedBox(width: 8),
              const Text('°C',
                  style: TextStyle(color: AppTheme.textSec, fontSize: 16)),
            ],
          ),
          Text(
            _syncing ? 'Syncing…' : _tempLabel(displayAvg),
            style: TextStyle(
                color: _syncing ? AppTheme.textSec : color,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ]),
      ]),
    );
  }

  Widget _chartCard(bool loading) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
          child: _buildChartContent(loading),
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
          _LegendDot(color: AppTheme.spo2Color, label: 'Low'),
          SizedBox(width: 10),
          _LegendDot(color: AppTheme.success, label: 'Normal'),
          SizedBox(width: 10),
          _LegendDot(color: Color(0xFFFBBF24), label: 'Elevated'),
          SizedBox(width: 10),
          _LegendDot(color: AppTheme.danger, label: 'Fever'),
        ]),
      ]),
    );
  }

  Widget _buildChartContent(bool loading) {
    if (loading) {
      return const Center(
          child: CircularProgressIndicator(
              color: AppTheme.tempColor, strokeWidth: 2));
    }

    // Collect display readings
    final List<({DateTime time, double valueC})> points;
    if (_showRingData) {
      points = _ringReadings.map((r) => (time: r.time, valueC: r.valueC)).toList();
    } else {
      points = _dbReadings.map((r) {
        final raw = r['measured_at'] as String;
        final v = (r['value_c'] as num? ?? 0).toDouble();
        return (time: DateTime.parse(raw).toLocal(), valueC: v);
      }).where((p) => p.valueC > 0).toList();
    }

    if (points.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.thermostat_outlined,
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

    if (_period == 0) {
      return CustomPaint(painter: _TempDayPainter(points));
    }
    return CustomPaint(
        painter: _TempRangePainter(points, _period == 1 ? 7 : 30));
  }

  Widget _readingsList() {
    final List<({DateTime time, double valueC, String source})> rows;
    if (_showRingData) {
      rows = _ringReadings
          .map((r) => (time: r.time, valueC: r.valueC, source: r.source))
          .toList();
    } else {
      rows = _dbReadings.map((r) {
        final dt = DateTime.parse(r['measured_at'] as String).toLocal();
        final v = (r['value_c'] as num? ?? 0).toDouble();
        final s = r['source'] as String? ?? 'auto';
        return (time: dt, valueC: v, source: s);
      }).where((r) => r.valueC > 0).toList();
    }

    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
        child: const Center(
            child: Text('No readings for this day',
                style: TextStyle(color: AppTheme.textSec))),
      );
    }

    final sorted = [...rows]..sort((a, b) => b.time.compareTo(a.time));

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
        ...sorted.asMap().entries.map((e) {
          final r = e.value;
          final color = _tempColor(r.valueC);
          final isLast = e.key == sorted.length - 1;
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
                  child: Icon(Icons.thermostat_rounded, color: color, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_fmtTime(r.time),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                        Row(children: [
                          Text(_tempLabel(r.valueC),
                              style: TextStyle(color: color, fontSize: 11)),
                          const SizedBox(width: 6),
                          Text('· ${r.source}',
                              style: const TextStyle(
                                  color: AppTheme.textSec, fontSize: 10)),
                        ]),
                      ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(r.valueC.toStringAsFixed(1),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 22)),
                  const Text('°C',
                      style: TextStyle(color: AppTheme.textSec, fontSize: 10)),
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

  Widget _syncCard(bool connected) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('SYNC DATA',
              style: TextStyle(
                  color: AppTheme.textSec,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: _Btn(
              label: "Today's Data",
              icon: Icons.today_rounded,
              enabled: connected && !_syncing,
              onTap: _fetchTodayData,
            )),
            const SizedBox(width: 10),
            Expanded(
                child: _Btn(
              label: 'Sync Auto',
              icon: Icons.sync_rounded,
              enabled: connected && !_syncing,
              onTap: _syncAuto,
            )),
          ]),
          const SizedBox(height: 10),
          _Btn(
            label: _syncing ? 'Measuring…' : 'Single Reading',
            icon: Icons.thermostat_rounded,
            enabled: connected && !_syncing,
            onTap: _syncManual,
          ),
        ]),
      );

  Widget _jsonViewerCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _jsonExpanded = !_jsonExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                const Icon(Icons.data_object_rounded,
                    color: Color(0xFF58A6FF), size: 15),
                const SizedBox(width: 8),
                const Text('RAW JSON',
                    style: TextStyle(
                        color: Color(0xFF58A6FF),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2)),
                const Spacer(),
                if (_rawJson.isEmpty)
                  const Text('no data yet',
                      style: TextStyle(
                          color: Color(0xFF8B949E), fontSize: 10))
                else
                  Icon(
                    _jsonExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF8B949E),
                    size: 18,
                  ),
              ]),
            ),
          ),
          if (_jsonExpanded && _rawJson.isNotEmpty) ...[
            const Divider(color: Color(0xFF30363D), height: 0.5),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(14),
              child: SelectableText(
                _rawJson,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFFE6EDF3),
                  height: 1.6,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _monitorCard(bool connected) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.div)),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Auto Monitoring',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                    SizedBox(height: 2),
                    Text('Continuously monitors body temperature',
                        style:
                            TextStyle(color: AppTheme.textSec, fontSize: 12)),
                  ]),
            ),
            Switch.adaptive(
              value: _settingEnabled,
              onChanged: connected
                  ? (v) {
                      setState(() => _settingEnabled = v);
                      _saveSettings();
                    }
                  : null,
            ),
          ]),
          if (_settingEnabled && connected) ...[
            const Divider(color: AppTheme.div, height: 16),
            Row(children: [
              const Text('Interval',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              const Spacer(),
              DropdownButton<int>(
                value: _settingIntervalSec,
                dropdownColor: AppTheme.card2,
                style: const TextStyle(color: Colors.white),
                underline: const SizedBox(),
                items: [2, 5, 10, 30, 60, 120]
                    .map((e) =>
                        DropdownMenuItem(value: e, child: Text('${e}s')))
                    .toList(),
                onChanged: (v) => setState(() => _settingIntervalSec = v ?? 5),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _saveSettings,
                child: const Text('Save',
                    style: TextStyle(color: AppTheme.gold)),
              ),
            ]),
          ],
        ]),
      );
}

// ── Data model ─────────────────────────────────────────────────────────────────

class _TempReading {
  final DateTime time;
  final double valueC;
  final String source;
  const _TempReading({required this.time, required this.valueC, required this.source});
}

// ── Chart painters ────────────────────────────────────────────────────────────

Color _tempBarColor(double v) {
  if (v < 36.0) return AppTheme.spo2Color;
  if (v <= 37.2) return AppTheme.success;
  if (v <= 38.0) return const Color(0xFFFBBF24);
  return AppTheme.danger;
}

// Day view: one bar per reading positioned by hour
class _TempDayPainter extends CustomPainter {
  final List<({DateTime time, double valueC})> points;
  const _TempDayPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    // 35–40 °C baseline keeps bars visually meaningful
    const baseline = 35.0;
    const range = 5.0;
    const slots = 24;
    final slotW = size.width / slots;
    final barW = (slotW * 0.65).clamp(2.0, 10.0);

    for (final p in points) {
      final slot = p.time.hour.clamp(0, slots - 1);
      final x = slot * slotW + (slotW - barW) / 2;
      final normalized = ((p.valueC - baseline) / range).clamp(0.0, 1.0);
      final barH = (normalized * size.height * 0.85 + 4).clamp(4.0, size.height);
      canvas.drawRRect(
        RRect.fromLTRBR(
            x, size.height - barH, x + barW, size.height, const Radius.circular(3)),
        Paint()..color = _tempBarColor(p.valueC),
      );
    }
  }

  @override
  bool shouldRepaint(_TempDayPainter old) => old.points != points;
}

// Week/Month view: one bar per day (daily average)
class _TempRangePainter extends CustomPainter {
  final List<({DateTime time, double valueC})> points;
  final int days;
  const _TempRangePainter(this.points, this.days);

  Map<String, double> _dailyAvgs() {
    final sums = <String, double>{};
    final counts = <String, int>{};
    for (final p in points) {
      final key =
          '${p.time.year}-${p.time.month.toString().padLeft(2, '0')}-${p.time.day.toString().padLeft(2, '0')}';
      sums[key] = (sums[key] ?? 0) + p.valueC;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return {for (final k in sums.keys) k: sums[k]! / counts[k]!};
  }

  @override
  void paint(Canvas canvas, Size size) {
    const baseline = 35.0;
    const range = 5.0;
    final avgs = _dailyAvgs();
    final now = DateTime.now();
    final slotW = size.width / days;
    final barW = (slotW * 0.6).clamp(2.0, 10.0);

    for (int i = 0; i < days; i++) {
      final day = now.subtract(Duration(days: days - 1 - i));
      final key =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      final v = avgs[key];
      if (v == null || v <= 0) continue;
      final x = i * slotW + (slotW - barW) / 2;
      final normalized = ((v - baseline) / range).clamp(0.0, 1.0);
      final barH = (normalized * size.height * 0.85 + 4).clamp(4.0, size.height);
      canvas.drawRRect(
        RRect.fromLTRBR(
            x, size.height - barH, x + barW, size.height, const Radius.circular(3)),
        Paint()..color = _tempBarColor(v),
      );
    }
  }

  @override
  bool shouldRepaint(_TempRangePainter old) =>
      old.points != points || old.days != days;
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

class _Btn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  const _Btn(
      {required this.label,
      required this.icon,
      required this.enabled,
      this.onTap});

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
              Icon(icon,
                  color: enabled ? AppTheme.gold : AppTheme.textSec, size: 18),
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
