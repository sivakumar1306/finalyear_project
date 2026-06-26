import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/vital_widgets.dart';

// Sleep stage type constants (Oudmon SDK convention):
// 0 = deep, 1 = light, 2 = awake, 3 = REM
const _kDeep = 0;
const _kLight = 1;
const _kAwake = 2;
const _kRem = 3;

class SleepScreen extends StatefulWidget {
  const SleepScreen({super.key});
  @override
  State<SleepScreen> createState() => _SleepScreenState();
}

class _SleepScreenState extends State<SleepScreen> {
  final _ble = BleService();

  bool _loading = false;
  bool _loadingDb = false;

  // Parsed data
  int _totalDuration = 0;  // seconds
  int _deepDuration  = 0;
  int _lightDuration = 0;
  int _remDuration   = 0;
  int _awakeDuration = 0;
  int _sleepTime     = 0;  // unix timestamp (seconds)
  int _wakeTime      = 0;
  int _sleepScore    = 0;
  List<Map<String, int>> _segments = [];

  String _result = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.read<BleProvider>().isConnected) {
        _fetchFromRing();
      } else {
        _loadFromDb();
      }
    });
  }

  // ── Ring fetch ─────────────────────────────────────────────────────────────

  Future<void> _fetchFromRing() async {
    setState(() { _loading = true; _result = ''; });
    try {
      final data = await _ble.getTodaySleep();
      if (mounted) setState(() => _result = _pretty(data));
      _parseSleepData(data);
    } catch (e) {
      if (mounted) setState(() => _result = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncFromRing() async {
    setState(() { _loading = true; _result = ''; });
    try {
      final data = await _ble.syncSleep();
      if (mounted) setState(() => _result = _pretty(data));
      // syncSleep may return SleepDisplay format or SleepNewProtoResp format
      final decoded = jsonDecode(data) as Map<String, dynamic>;
      if (decoded.containsKey('totalSleepDuration')) {
        _parseSleepData(data);
      } else if (decoded.containsKey('st') || decoded.containsKey('et')) {
        _parseSleepNewProto(decoded);
      }
    } catch (e) {
      if (mounted) setState(() => _result = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _parseSleepData(String jsonStr) {
    try {
      final d = jsonDecode(jsonStr) as Map<String, dynamic>;
      final total  = (d['totalSleepDuration'] as num? ?? 0).toInt();
      final deep   = (d['deepDuration']        as num? ?? 0).toInt();
      final light  = (d['lightDuration']       as num? ?? 0).toInt();
      final rem    = (d['remDuration']         as num? ?? 0).toInt();
      final awake  = (d['awakeDuration']       as num? ?? 0).toInt();
      final st     = (d['sleepTime']           as num? ?? 0).toInt();
      final et     = (d['wakeTime']            as num? ?? 0).toInt();

      if (total <= 0) return;

      final segs = _parseSegments(d['list']);
      final score = _calcScore(total, deep, rem, st, et);

      if (!mounted) return;
      setState(() {
        _totalDuration = total;
        _deepDuration  = deep;
        _lightDuration = light;
        _remDuration   = rem;
        _awakeDuration = awake;
        _sleepTime     = st;
        _wakeTime      = et;
        _sleepScore    = score;
        _segments      = segs;
      });

      _saveToDb(total, deep, light, rem, awake, score, st, et);
    } catch (e) {
      if (mounted) setState(() => _result = 'Parse error: $e');
    }
  }

  // Handle SleepNewProtoResp format (from syncSleep)
  void _parseSleepNewProto(Map<String, dynamic> d) {
    final st = (d['st'] as num? ?? 0).toInt();
    final et = (d['et'] as num? ?? 0).toInt();
    if (st <= 0 || et <= 0) return;

    final rawList = (d['list'] as List<dynamic>?) ?? [];
    int deep = 0, light = 0, rem = 0, awake = 0;
    final segs = <Map<String, int>>[];

    int cursor = st;
    for (final item in rawList) {
      final m = item as Map<String, dynamic>;
      final dur  = (m['d'] as num? ?? 0).toInt(); // seconds
      final type = (m['t'] as num? ?? _kLight).toInt();
      if (dur <= 0) continue;
      segs.add({'start': cursor, 'end': cursor + dur, 'type': type});
      switch (type) {
        case _kDeep:  deep  += dur; break;
        case _kLight: light += dur; break;
        case _kAwake: awake += dur; break;
        case _kRem:   rem   += dur; break;
      }
      cursor += dur;
    }

    final total = et - st;
    if (total <= 0) return;
    final score = _calcScore(total, deep, rem, st, et);

    if (!mounted) return;
    setState(() {
      _totalDuration = total;
      _deepDuration  = deep;
      _lightDuration = light;
      _remDuration   = rem;
      _awakeDuration = awake;
      _sleepTime     = st;
      _wakeTime      = et;
      _sleepScore    = score;
      _segments      = segs;
    });

    _saveToDb(total, deep, light, rem, awake, score, st, et);
  }

  List<Map<String, int>> _parseSegments(dynamic rawList) {
    if (rawList == null) return [];
    final list = rawList as List<dynamic>;
    final segs = <Map<String, int>>[];
    for (final item in list) {
      final m = item as Map<String, dynamic>;
      final s = (m['sleepStart'] as num? ?? 0).toInt();
      final e = (m['sleepEnd']   as num? ?? 0).toInt();
      final t = (m['type']       as num? ?? _kLight).toInt();
      if (s > 0 && e > s) segs.add({'start': s, 'end': e, 'type': t});
    }
    return segs;
  }

  int _calcScore(int total, int deep, int rem, int st, int et) {
    final window = (st > 0 && et > 0) ? (et - st) : total;
    final efficiency = window > 0 ? (total / window * 100).clamp(0, 100) : 0;
    final deepPct = total > 0 ? (deep / total * 100).clamp(0, 40) : 0;
    final remPct  = total > 0 ? (rem  / total * 100).clamp(0, 30) : 0;
    return (efficiency * 0.4 + deepPct * 1.0 + remPct * 0.5).round().clamp(0, 100);
  }

  // ── DB ─────────────────────────────────────────────────────────────────────

  Future<void> _saveToDb(int total, int deep, int light, int rem, int awake,
      int score, int st, int et) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.upsertSleep(
        userId: user.id,
        date: DateTime.now(),
        totalDuration: total,
        deepDuration: deep,
        lightDuration: light,
        remDuration: rem,
        awakeDuration: awake,
        sleepScore: score,
        sleepTime: st,
        wakeTime: et,
      );
    } catch (_) {}
  }

  Future<void> _loadFromDb() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() => _loadingDb = true);
    try {
      final row = await SupabaseService.getSleepForDate(user.id, DateTime.now());
      if (!mounted) return;
      if (row != null) {
        setState(() {
          _totalDuration = (row['total_duration'] as num? ?? 0).toInt();
          _deepDuration  = (row['deep_duration']  as num? ?? 0).toInt();
          _lightDuration = (row['light_duration'] as num? ?? 0).toInt();
          _remDuration   = (row['rem_duration']   as num? ?? 0).toInt();
          _awakeDuration = (row['awake_duration'] as num? ?? 0).toInt();
          _sleepTime     = (row['sleep_time']     as num? ?? 0).toInt();
          _wakeTime      = (row['wake_time']      as num? ?? 0).toInt();
          _sleepScore    = (row['sleep_score']    as num? ?? 0).toInt();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingDb = false);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _pretty(String raw) {
    try { return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw)); }
    catch (_) { return raw; }
  }

  String _fmt(int secs) {
    if (secs <= 0) return '--';
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m}m';
  }

  String _quality() {
    if (_sleepScore >= 85) return 'Excellent';
    if (_sleepScore >= 70) return 'Good';
    if (_sleepScore >= 55) return 'Fair';
    if (_sleepScore > 0)  return 'Poor';
    return '--';
  }

  String _efficiency() {
    if (_sleepTime <= 0 || _wakeTime <= 0 || _totalDuration <= 0) return '--%';
    final window = _wakeTime - _sleepTime;
    if (window <= 0) return '--%';
    return '${(_totalDuration / window * 100).round()}%';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;
    final anyLoading = _loading || _loadingDb;
    final hasData = _totalDuration > 0;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _darkBar('Sleep'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            const VitalDateSelector(),
            const SizedBox(height: 12),
            const VitalPeriodTabs(),
            const SizedBox(height: 24),

            _scoreCard(hasData, anyLoading),
            const SizedBox(height: 16),

            _stagesCard(hasData, anyLoading),
            const SizedBox(height: 16),

            _qualityRow(),
            const SizedBox(height: 24),

            // Action buttons
            Row(children: [
              Expanded(child: _Btn(
                label: 'Load Sleep Data',
                icon: Icons.bedtime_rounded,
                enabled: connected && !_loading,
                onTap: _fetchFromRing,
              )),
              const SizedBox(width: 10),
              Expanded(child: _Btn(
                label: 'Sync Sleep',
                icon: Icons.sync_rounded,
                enabled: connected && !_loading,
                onTap: _syncFromRing,
              )),
            ]),
            const SizedBox(height: 12),

            if (anyLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(color: AppTheme.gold, strokeWidth: 2)),
              ),

            if (_result.isNotEmpty)
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

  // ── Cards ──────────────────────────────────────────────────────────────────

  Widget _scoreCard(bool hasData, bool loading) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.sleepColor.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              height: 90,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 90,
                    height: 90,
                    child: CircularProgressIndicator(
                      value: loading ? null : (hasData ? _sleepScore / 100 : 0.0),
                      strokeWidth: 8,
                      backgroundColor: AppTheme.card2,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.sleepColor),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        hasData && !loading ? '$_sleepScore' : '--',
                        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
                      ),
                      Text('Score', style: TextStyle(color: AppTheme.sleepColor, fontSize: 10, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TOTAL DURATION', style: TextStyle(color: AppTheme.textSec, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text(
                    hasData ? _fmt(_totalDuration) : '-h --m',
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasData
                        ? '${_timeLabel(_sleepTime)} – ${_timeLabel(_wakeTime)}'
                        : 'Wear device to monitor sleep',
                    style: TextStyle(color: AppTheme.textSec.withValues(alpha: 0.7), fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  String _timeLabel(int ts) {
    if (ts <= 0) return '--';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final suffix = h < 12 ? 'am' : 'pm';
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$hour12:$m$suffix';
  }

  Widget _stagesCard(bool hasData, bool loading) {
    final total = _totalDuration > 0 ? _totalDuration : 1;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SLEEP STAGES', style: TextStyle(color: AppTheme.textSec, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 16),
          _Stage(
            label: 'Awake',
            value: hasData ? _fmt(_awakeDuration) : '--m',
            progress: hasData ? (_awakeDuration / total).clamp(0.0, 1.0) : 0.0,
            color: const Color(0xFFFBBF24),
          ),
          const SizedBox(height: 12),
          _Stage(
            label: 'REM',
            value: hasData ? _fmt(_remDuration) : '--m',
            progress: hasData ? (_remDuration / total).clamp(0.0, 1.0) : 0.0,
            color: const Color(0xFF818CF8),
          ),
          const SizedBox(height: 12),
          _Stage(
            label: 'Light Sleep',
            value: hasData ? _fmt(_lightDuration) : '-h --m',
            progress: hasData ? (_lightDuration / total).clamp(0.0, 1.0) : 0.0,
            color: const Color(0xFF60A5FA),
          ),
          const SizedBox(height: 12),
          _Stage(
            label: 'Deep Sleep',
            value: hasData ? _fmt(_deepDuration) : '-h --m',
            progress: hasData ? (_deepDuration / total).clamp(0.0, 1.0) : 0.0,
            color: AppTheme.sleepColor,
          ),
          const SizedBox(height: 16),
          const Text('SLEEP TIMELINE', style: TextStyle(color: AppTheme.textSec, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 28,
              child: loading
                  ? const Center(child: LinearProgressIndicator(color: AppTheme.sleepColor, backgroundColor: AppTheme.card2))
                  : CustomPaint(
                      painter: _SleepTimelinePainter(
                        segments: _segments,
                        sleepTime: _sleepTime,
                        wakeTime: _wakeTime,
                        totalDuration: _totalDuration,
                        deepDuration: _deepDuration,
                        lightDuration: _lightDuration,
                        awakeDuration: _awakeDuration,
                        remDuration: _remDuration,
                      ),
                      size: const Size(double.infinity, 28),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          _timelineLabels(),
        ],
      ),
    );
  }

  Widget _timelineLabels() {
    if (_sleepTime <= 0 || _wakeTime <= 0) {
      return const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('10pm', style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
          Text('12am', style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
          Text('2am',  style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
          Text('4am',  style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
          Text('6am',  style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
        ],
      );
    }
    final st = DateTime.fromMillisecondsSinceEpoch(_sleepTime * 1000);
    final et = DateTime.fromMillisecondsSinceEpoch(_wakeTime * 1000);
    final span = et.difference(st);
    final labels = <String>[_timeLabel(_sleepTime)];
    // Add 2-3 intermediate labels
    final steps = span.inHours > 3 ? 4 : 3;
    for (int i = 1; i < steps; i++) {
      final ts = st.add(Duration(seconds: (span.inSeconds * i ~/ steps)));
      labels.add(_timeLabel(ts.millisecondsSinceEpoch ~/ 1000));
    }
    labels.add(_timeLabel(_wakeTime));
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: labels
          .map((l) => Text(l, style: const TextStyle(color: Color(0xFF555555), fontSize: 10)))
          .toList(),
    );
  }

  Widget _qualityRow() => Row(
        children: [
          Expanded(
            child: _QualityBox(label: 'SLEEP EFFICIENCY', value: _efficiency(), description: 'Time asleep vs in bed'),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QualityBox(label: 'SLEEP QUALITY', value: _quality(), description: 'Based on stages'),
          ),
        ],
      );
}

// ── Sleep timeline painter ─────────────────────────────────────────────────

class _SleepTimelinePainter extends CustomPainter {
  final List<Map<String, int>> segments;
  final int sleepTime, wakeTime;
  final int totalDuration, deepDuration, lightDuration, awakeDuration, remDuration;

  const _SleepTimelinePainter({
    required this.segments,
    required this.sleepTime,
    required this.wakeTime,
    required this.totalDuration,
    required this.deepDuration,
    required this.lightDuration,
    required this.awakeDuration,
    required this.remDuration,
  });

  static const _colors = {
    _kDeep:  Color(0xFF6366F1),
    _kLight: Color(0xFF60A5FA),
    _kAwake: Color(0xFFFBBF24),
    _kRem:   Color(0xFF818CF8),
  };

  @override
  void paint(Canvas canvas, Size size) {
    if (sleepTime <= 0 || wakeTime <= 0 || wakeTime <= sleepTime) {
      _drawSynthetic(canvas, size);
      return;
    }
    final window = (wakeTime - sleepTime).toDouble();

    if (segments.isEmpty) {
      _drawSynthetic(canvas, size);
      return;
    }

    for (final seg in segments) {
      final start = seg['start']! - sleepTime;
      final end   = seg['end']!   - sleepTime;
      final type  = seg['type']!;
      if (end <= start || start >= window) continue;
      final x1 = (start / window * size.width).clamp(0.0, size.width);
      final x2 = (end   / window * size.width).clamp(0.0, size.width);
      canvas.drawRect(
        Rect.fromLTRB(x1, 0, x2, size.height),
        Paint()..color = _colors[type] ?? const Color(0xFF60A5FA),
      );
    }
  }

  void _drawSynthetic(Canvas canvas, Size size) {
    if (totalDuration <= 0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = AppTheme.card2);
      return;
    }
    final total = totalDuration.toDouble();
    final parts = [
      (awakeDuration,  _kAwake),
      (lightDuration,  _kLight),
      (deepDuration,   _kDeep),
      (lightDuration ~/ 2, _kLight),
      (remDuration,    _kRem),
      (lightDuration ~/ 2, _kLight),
      (awakeDuration ~/ 2, _kAwake),
    ];
    double x = 0;
    for (final p in parts) {
      if (p.$1 <= 0) continue;
      final w = p.$1 / total * size.width;
      canvas.drawRect(
        Rect.fromLTWH(x, 0, w, size.height),
        Paint()..color = _colors[p.$2] ?? const Color(0xFF60A5FA),
      );
      x = math.min(x + w, size.width);
    }
  }

  @override
  bool shouldRepaint(_SleepTimelinePainter old) =>
      old.segments != segments || old.sleepTime != sleepTime || old.totalDuration != totalDuration;
}

// ── Stage row ─────────────────────────────────────────────────────────────

class _Stage extends StatelessWidget {
  final String label, value;
  final double progress;
  final Color color;
  const _Stage({required this.label, required this.value, required this.progress, required this.color});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                    Text(value, style: const TextStyle(color: AppTheme.textSec, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: AppTheme.card2,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  borderRadius: BorderRadius.circular(4),
                  minHeight: 6,
                ),
              ],
            ),
          ),
        ],
      );
}

// ── Quality box ────────────────────────────────────────────────────────────

class _QualityBox extends StatelessWidget {
  final String label, value, description;
  const _QualityBox({required this.label, required this.value, required this.description});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.div)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppTheme.textSec, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1)),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(description, style: const TextStyle(color: AppTheme.textSec, fontSize: 10)),
          ],
        ),
      );
}

// ── Shared helpers ─────────────────────────────────────────────────────────

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
          decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.div)),
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
