import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/local_vitals_service.dart';
import '../../services/health_connect_service.dart';
import '../../services/health_engine/health_engine.dart';
import '../../services/health_engine/models.dart';
import '../../services/health_engine/sleep_engine.dart';
import '../../services/incident_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_menu.dart';
import '../../widgets/offline_notice.dart';
import '../../widgets/screenshot_share.dart';
import '../settings/goal_setting_screen.dart';
import 'vital_note_screen.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/date_scroll_row.dart';
import '../../widgets/legend_dot.dart';
import '../../utils/date_keys.dart';
import '../../utils/formatters.dart';
import '../../utils/trend_math.dart';
import '../../widgets/metric_chart_card.dart';
import '../../widgets/metric_stat_card.dart';
import '../../widgets/not_enough_data_card.dart';


// Oudmon SDK sleep stage constants: 0=deep, 1=light, 2=awake, 3=REM
const _kDeep = 0;
const _kLight = 1;
const _kAwake = 2;
const _kRem = 3;

const _kDeepColor = Color(0xFF6366F1);

const _stageColors = {
  _kDeep: _kDeepColor,
  _kLight: AppTheme.softBlue,
  _kAwake: AppTheme.amber,
  _kRem: AppTheme.bpColor,
};

// ── Local design tokens — same system as heart_rate_screen.dart / blood_oxygen_screen.dart ──


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

class SleepScreen extends StatefulWidget {
  const SleepScreen({super.key});
  @override
  State<SleepScreen> createState() => _SleepScreenState();
}

class _SleepScreenState extends State<SleepScreen> {
  final _ble = BleService();
  final _moreButtonKey = GlobalKey();
  final _screenshotKey = GlobalKey();

  DateTime _selectedDate = DateTime.now();
  bool _loading = false;
  bool _dbOffline = false;

  // Day sleep data
  int _totalDuration = 0;
  int _deepDuration = 0;
  int _lightDuration = 0;
  int _remDuration = 0;
  int _awakeDuration = 0;
  int _sleepTime = 0;
  int _wakeTime = 0;
  int _sleepScore = 0;
  List<Map<String, int>> _segments = [];

  // Vitals for selected day
  int _avgHr = 0;
  int _avgSpo2 = 0;
  int _avgHrv = 0;

  // Last 7 days (always loaded on open, same as HR/SpO2's 7-day trend)
  List<Map<String, dynamic>> _historyRows = [];

  // ── Init ──────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _init();
    });
  }



  Future<void> _init() async {
    if (!mounted) return;
    final date = _selectedDate;
    // Local night first, so the page is filled before the ring or the network.
    final hadLocal = await _applyLocalSleep(date);
    if (!mounted || !_sameDay(date, _selectedDate)) return;
    setState(() => _loading = false);
    unawaited(_loadVitals(date));
    unawaited(() async {
      await _loadHistory();
      if (!mounted || !_sameDay(date, _selectedDate)) return;
      await _refreshFromRing(date);
      if (!mounted || !_sameDay(date, _selectedDate)) return;
      if (!hadLocal && _totalDuration <= 0) await _fillFromCloud(date);
      await _syncMissingHistory();
    }());
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  int _dayIndexFor(DateTime date) {
    final today = DateTime.now();
    final sel = DateTime(date.year, date.month, date.day);
    final todayDay = DateTime(today.year, today.month, today.day);
    return todayDay.difference(sel).inDays;
  }

  // ── Date selection ────────────────────────────────────────────────────────────

  void _onDateSelected(DateTime date) {
    setState(() {
      _selectedDate = date;
      _totalDuration = 0;
      _deepDuration = 0;
      _lightDuration = 0;
      _remDuration = 0;
      _awakeDuration = 0;
      _sleepTime = 0;
      _wakeTime = 0;
      _sleepScore = 0;
      _segments = [];
      _avgHr = 0;
      _avgSpo2 = 0;
      _avgHrv = 0;
    });
    _init();
  }

  // ── Ring fetch ───────────────────────────────────────────────────────────────

  /// Expected-offline BLE states (ring out of range / stale isConnected cache /
  /// SDK busy) fall through to the Supabase cache silently. Only unexpected
  /// errors become app_incidents rows — one open with a dead ring used to emit
  /// up to 6 rows.
  bool _isExpectedBleOffline(Object e) {
    if (e is TimeoutException) return true;
    if (e is PlatformException) {
      const expected = {
        'NOT_CONNECTED',
        'SDK_GUARD_OPEN',
        'BUSY',
        'TIMEOUT',
        'CMD_FAILED',
        'SDK_EXCEPTION',
      };
      if (expected.contains(e.code)) return true;
      final msg = '${e.code} ${e.message}'.toUpperCase();
      if (msg.contains('NOT_CONNECTED') ||
          msg.contains('NOT CONNECTED') ||
          msg.contains('RING NOT CONNECTED') ||
          msg.contains('TIMEOUT') ||
          msg.contains('BUSY')) {
        return true;
      }
    }
    final s = e.toString().toUpperCase();
    return s.contains('NOT_CONNECTED') ||
        s.contains('RING NOT CONNECTED') ||
        s.contains('TIMEOUT');
  }

  void _reportSleepBle(Object e, StackTrace st, String message) {
    if (_isExpectedBleOffline(e)) {
      debugPrint('[sleep_screen] expected offline ($message): $e');
      return;
    }
    IncidentService.reportUnhandled(
      source: 'sleep_screen',
      error: e,
      stackTrace: st,
      customMessage: message,
    );
  }

  Future<void> _refreshFromRing(DateTime date) async {
    bool connected = false;
    try {
      connected = context.read<BleProvider>().isConnected;
    } catch (_) {}
    if (!connected) return;
    final daysDiff = _dayIndexFor(date);
    if (daysDiff < 0 || daysDiff > 6) return;
    try {
      final data = await _ble.syncSleep(dayIndex: daysDiff);
      if (!mounted || !_sameDay(date, _selectedDate)) return;
      if (_parseSleepData(data, date: date)) return;
    } catch (e, st) {
      _reportSleepBle(e, st, 'syncSleep($daysDiff) failed');
    }
    try {
      final data = await _ble.getSleep(daysDiff);
      if (!mounted || !_sameDay(date, _selectedDate)) return;
      if (_parseSleepData(data, date: date)) return;
    } catch (e, st) {
      _reportSleepBle(e, st, 'getSleep($daysDiff) fallback failed');
    }
  }

  bool _parseSleepData(String jsonStr, {DateTime? date}) {
    if (jsonStr.isEmpty || jsonStr == '{}' || jsonStr == '[]') return false;
    try {
      final result = SleepEngine.parseSleepData(jsonStr);
      if (!result.hasData) return false;
      _applyParsed(result);
      unawaited(_saveLocal(result, date ?? _selectedDate));
      return true;
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'sleep_screen',
        error: e,
        stackTrace: st,
        customMessage: '_parseSleepData failed',
        extraInfo: {'raw': jsonStr.substring(0, jsonStr.length.clamp(0, 500))},
      );
      return false;
    }
  }

  void _applyParsed(SleepParseResult result) {
    if (!mounted) return;
    setState(() {
      _totalDuration = result.total;
      _deepDuration = result.deep;
      _lightDuration = result.light;
      _remDuration = result.rem;
      _awakeDuration = result.awake;
      _sleepTime = result.st;
      _wakeTime = result.et;
      _sleepScore = result.score;
      _segments = result.segments;
      _loading = false;
    });
  }

  // ── Local DB, then cloud fill ────────────────────────────────────────────────


  Future<bool> _applyLocalSleep(DateTime date) async {
    try {
      final raw = await _ble.getLocalSleep(DateKeys.fmt(date));
      if (raw.isEmpty || raw == '{}') return false;
      final row = jsonDecode(raw);
      if (row is! Map) return false;
      final payload = row['payloadJson'];
      if (payload is String && payload.length > 2) {
        final parsed = SleepEngine.parseSleepData(payload);
        if (parsed.hasData && mounted && _sameDay(date, _selectedDate)) {
          _applyParsed(parsed);
          return true;
        }
      }
      final total = (row['totalDuration'] as num?)?.toInt() ?? 0;
      if (total <= 0 || !mounted || !_sameDay(date, _selectedDate)) return false;
      _applyParsed(SleepParseResult(
        total: total,
        deep: (row['deepDuration'] as num?)?.toInt() ?? 0,
        light: (row['lightDuration'] as num?)?.toInt() ?? 0,
        rem: (row['remDuration'] as num?)?.toInt() ?? 0,
        awake: (row['awakeDuration'] as num?)?.toInt() ?? 0,
        st: (row['sleepTime'] as num?)?.toInt() ?? 0,
        et: (row['wakeTime'] as num?)?.toInt() ?? 0,
        score: (row['sleepScore'] as num?)?.toInt() ?? 0,
        segments: const [],
        hasData: true,
      ));
      return true;
    } catch (e) {
      debugPrint('[sleep_screen] local read failed: $e');
      return false;
    }
  }

  Future<void> _fillFromCloud(DateTime date) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      final row = await SupabaseService.getSleepForDate(user.id, date)
          .timeout(const Duration(seconds: 6));
      if (!mounted || !_sameDay(date, _selectedDate)) return;
      if (row == null) return;
      final total = (row['total_duration'] as num? ?? 0).toInt();
      if (total <= 0) return;
      final parsed = SleepParseResult(
        total: total,
        deep: (row['deep_duration'] as num? ?? 0).toInt(),
        light: (row['light_duration'] as num? ?? 0).toInt(),
        rem: (row['rem_duration'] as num? ?? 0).toInt(),
        awake: (row['awake_duration'] as num? ?? 0).toInt(),
        st: (row['sleep_time'] as num? ?? 0).toInt(),
        et: (row['wake_time'] as num? ?? 0).toInt(),
        score: (row['sleep_score'] as num? ?? 0).toInt(),
        segments: const [],
        hasData: true,
      );
      _applyParsed(parsed);
      await _saveLocal(parsed, date, source: 'cloud_cache');
    } catch (e) {
      if (mounted && isNetworkError(e)) setState(() => _dbOffline = true);
    }
  }

  Future<void> _loadVitals(DateTime date) async {
    try {
      final local = LocalVitalsService(ble: _ble);
      final results = await Future.wait([
        local.getDaySummary('heart_rate', date),
        local.getDaySummary('spo2', date),
        local.getDaySummary('hrv', date),
      ]);
      if (!mounted || !_sameDay(date, _selectedDate)) return;
      final hr = (results[0]['avg'] as num?)?.round() ?? 0;
      final spo2 = (results[1]['avg'] as num?)?.round() ?? 0;
      final hrv = (results[2]['avg'] as num?)?.round() ?? 0;
      if (hr > 0 || spo2 > 0 || hrv > 0) {
        setState(() {
          _avgHr = hr;
          _avgSpo2 = spo2;
          _avgHrv = hrv;
        });
        return;
      }
    } catch (_) {}
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      final results = await Future.wait([
        SupabaseService.getHrForDate(user.id, date),
        SupabaseService.getSpo2ForDate(user.id, date),
        SupabaseService.getHrvForDate(user.id, date),
      ]).timeout(const Duration(seconds: 6));
      if (!mounted || !_sameDay(date, _selectedDate)) return;
      setState(() {
        _avgHr = (results[0]?['avg_hr'] as num? ?? 0).toInt();
        _avgSpo2 = (results[1]?['avg_spo2'] as num? ?? 0).toInt();
        _avgHrv = (results[2]?['avg_hrv'] as num? ?? 0).toInt();
      });
    } catch (e) {
      if (mounted && isNetworkError(e)) setState(() => _dbOffline = true);
    }
  }

  Future<void> _loadHistory() async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    final to = DateTime(now.year, now.month, now.day);
    try {
      final raw = await _ble.getLocalSleepHistory(
        from: DateKeys.fmt(from),
        to: DateKeys.fmt(to),
      );
      final decoded = jsonDecode(raw);
      if (decoded is List && mounted) {
        final rows = decoded.whereType<Map>().map((row) {
          return <String, dynamic>{
            'date': row['dateStr'],
            'total_duration': row['totalDuration'],
            'deep_duration': row['deepDuration'],
            'light_duration': row['lightDuration'],
            'rem_duration': row['remDuration'],
            'sleep_score': row['sleepScore'],
          };
        }).where((r) => ((r['total_duration'] as num?) ?? 0) > 0).toList();
        if (rows.isNotEmpty) setState(() => _historyRows = rows);
      }
    } catch (e) {
      debugPrint('[sleep_screen] local history failed: $e');
    }
    unawaited(_mergeCloudHistory(from, to));
  }

  Future<void> _syncMissingHistory() async {
    bool connected = false;
    try {
      connected = context.read<BleProvider>().isConnected;
    } catch (_) {}
    if (!connected) return;
    final now = DateTime.now();
    final have = <String>{
      for (final r in _historyRows)
        if (r['date'] is String) r['date'] as String,
    };
    for (var i = 0; i <= 6; i++) {
      if (!mounted) return;
      final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final key = DateKeys.fmt(day);
      if (i != 0 && have.contains(key)) continue;
      if (i == 0 && _sameDay(day, _selectedDate) && _totalDuration > 0) {
        have.add(key);
        continue;
      }
      try {
        final data = await _ble.syncSleep(dayIndex: i);
        final parsed = SleepEngine.parseSleepData(data);
        if (!parsed.hasData) continue;
        await _saveLocal(parsed, day);
        have.add(key);
        if (mounted && _sameDay(day, _selectedDate)) _applyParsed(parsed);
      } catch (e, st) {
        _reportSleepBle(e, st, 'history syncSleep($i) failed');
      }
    }
    if (!mounted) return;
    await _reloadLocalHistory();
  }

  Future<void> _reloadLocalHistory() async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    final to = DateTime(now.year, now.month, now.day);
    try {
      final raw = await _ble.getLocalSleepHistory(
        from: DateKeys.fmt(from),
        to: DateKeys.fmt(to),
      );
      final decoded = jsonDecode(raw);
      if (decoded is! List || !mounted) return;
      final rows = decoded.whereType<Map>().map((row) {
        return <String, dynamic>{
          'date': row['dateStr'],
          'total_duration': row['totalDuration'],
          'deep_duration': row['deepDuration'],
          'light_duration': row['lightDuration'],
          'rem_duration': row['remDuration'],
          'sleep_score': row['sleepScore'],
        };
      }).where((r) => ((r['total_duration'] as num?) ?? 0) > 0).toList();
      if (rows.isEmpty) return;
      setState(() => _historyRows = rows);
    } catch (e) {
      debugPrint('[sleep_screen] local history reload failed: $e');
    }
  }

  Future<void> _mergeCloudHistory(DateTime from, DateTime to) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      final rows = await SupabaseService.getSleepHistory(
        userId: user.id,
        from: from,
        to: to,
      ).timeout(const Duration(seconds: 6));
      if (!mounted || rows.isEmpty) return;
      final byDate = <String, Map<String, dynamic>>{
        for (final r in _historyRows)
          if (r['date'] is String) r['date'] as String: Map<String, dynamic>.from(r),
      };
      for (final r in rows) {
        final key = r['date'] as String?;
        if (key == null) continue;
        final existingTotal = (byDate[key]?['total_duration'] as num?)?.toInt() ?? 0;
        final cloudTotal = (r['total_duration'] as num?)?.toInt() ?? 0;
        if (existingTotal > 0 || cloudTotal <= 0) continue;
        byDate[key] = r;
        final parsed = SleepParseResult(
          total: cloudTotal,
          deep: (r['deep_duration'] as num? ?? 0).toInt(),
          light: (r['light_duration'] as num? ?? 0).toInt(),
          rem: (r['rem_duration'] as num? ?? 0).toInt(),
          awake: (r['awake_duration'] as num? ?? 0).toInt(),
          st: (r['sleep_time'] as num? ?? 0).toInt(),
          et: (r['wake_time'] as num? ?? 0).toInt(),
          score: (r['sleep_score'] as num? ?? 0).toInt(),
          segments: const [],
          hasData: true,
        );
        unawaited(_saveLocal(parsed, DateTime.parse('${key}T12:00:00'), source: 'cloud_cache'));
      }
      final merged = byDate.values.toList()
        ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
      if (!mounted) return;
      setState(() => _historyRows = merged);
    } catch (e) {
      if (mounted && isNetworkError(e)) setState(() => _dbOffline = true);
    }
  }

  Future<void> _saveLocal(
    SleepParseResult result,
    DateTime date, {
    String source = 'ring',
  }) async {
    if (!result.hasData || result.total <= 0) return;
    final today = DateTime.now();
    final dayIndex = DateTime(today.year, today.month, today.day)
        .difference(DateTime(date.year, date.month, date.day))
        .inDays;
    BleProvider? provider;
    try {
      provider = context.read<BleProvider>();
    } catch (_) {}
    await _ble.saveLocalSleep(
      dateStr: DateKeys.fmt(date),
      dayIndex: dayIndex < 0 ? 0 : dayIndex,
      totalDuration: result.total,
      deepDuration: result.deep,
      lightDuration: result.light,
      remDuration: result.rem,
      awakeDuration: result.awake,
      sleepScore: result.score,
      sleepTime: result.st,
      wakeTime: result.et,
      payloadJson: SleepEngine.canonicalJson(result),
      source: source,
    );
    if (provider != null) {
      if (mounted && _sameDay(date, DateTime.now())) {
        provider.updateSleepData(result.total, result.score);
      }
      provider.scheduleCloudUpload();
    }
    if (source == 'ring' && result.st > 0) {
      unawaited(
        HealthConnectService.instance.tryWriteSleep(
          sleepTime: DateTime.fromMillisecondsSinceEpoch(result.st * 1000),
          wakeTime: DateTime.fromMillisecondsSinceEpoch(
            (result.et > 0 ? result.et : result.st + 3600) * 1000,
          ),
          lightMinutes: result.light ~/ 60,
          deepMinutes: result.deep ~/ 60,
          remMinutes: result.rem ~/ 60,
          awakeMinutes: result.awake ~/ 60,
        ),
      );
    }
  }


  // ── Computed helpers ─────────────────────────────────────────────────────────

  String _fmt(int secs) => Formatters.sleepDuration(secs);

  String _timeLabel(int ts) => Formatters.sleepTimeLabel(ts);

  String _efficiency() {
    return SleepEngine.efficiencyLabel(_totalDuration, _sleepTime, _wakeTime);
  }

  int _avgHistoryScore() => TrendMath.avgHistoryScore(_historyRows);

  int _avgHistoryDuration() => TrendMath.avgHistoryDuration(_historyRows);

  List<int> _last7Bars() => TrendMath.last7Bars(_historyRows);

  /// Day-of-week letters for the last 7 days (oldest → newest), matching
  /// `_last7Bars()` order so each bar sits over its label.
  List<String> _trendDayLabels() => DateKeys.trendDayLabelsShort();

  // ── Three-dot menu ────────────────────────────────────────────────────────

  void _openMenu() {
    showGlassMenu(
      context: context,
      anchorKey: _moreButtonKey,
      items: [
        GlassMenuItem(
          label: 'Share',
          onTap: () =>
              shareScreenshot(_screenshotKey, text: 'My Sleep — SUNDR'),
        ),
        GlassMenuItem(
          label: 'Goal setting',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const GoalSettingScreen()),
          ),
        ),
        GlassMenuItem(
          label: 'Note',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VitalNoteScreen.fromMetric(HealthMetric.sleep),
            ),
          ),
        ),
      ],
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasData = _totalDuration > 0;
    final trendVals = _last7Bars();
    final avgDur = _avgHistoryDuration();
    final avgScore = _avgHistoryScore();

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
          title: Text('Sleep', style: _inter(17, weight: FontWeight.w600)),
          actions: [
            IconButton(
              key: _moreButtonKey,
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onPressed: _openMenu,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(0.5),
            child: Container(color: AppTheme.div, height: 0.5),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // ── 1. Date row ────────────────────────────────────────────────
              DateScrollRow(
                selectedDate: _selectedDate,
                onDateSelected: _onDateSelected,
              ),
              const SizedBox(height: 22),

              // ── 2. Current reading ───────────────────────────────────────
              Text(
                'TOTAL SLEEP',
                style: _inter(
                  11,
                  weight: FontWeight.w600,
                  color: AppTheme.gold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hasData ? _fmt(_totalDuration) : '--',
                style: _inter(
                  52,
                  weight: FontWeight.w300,
                  color: Colors.white,
                  height: 1.1,
                ),
              ),
              Text(
                hasData
                    ? 'Score $_sleepScore · ${(HealthEngine.instance.assessSleep(_sleepScore).label == 'No data' ? '--' : HealthEngine.instance.assessSleep(_sleepScore).label)}'
                    : (_loading ? 'Loading…' : 'No data yet'),
                style: _inter(13, color: AppTheme.textTertiary),
              ),
              const SizedBox(height: 16),

              if (_dbOffline && !hasData) ...[
                const OfflineNotice(
                  message: 'Connect to WiFi to load sleep data',
                ),
                const SizedBox(height: 16),
              ],

              // ── 3-7. Daily section — collapse to single glass card when empty
              if (!hasData && !_loading && !_dbOffline)
                NotEnoughDataCard(
                  metric: 'sleep',
                  date: _selectedDate,
                  loading: _loading,
                  isConnected: context.read<BleProvider>().isConnected,
                )
              else ...[
                // ── 3. Sleep stages chart ────────────────────────────────────
                MetricChartCard(
                  headerLabel: hasData ? 'SLEEP STAGES' : 'NO DATA YET',
                  rangeLabel: hasData && _sleepTime > 0
                      ? '${_timeLabel(_sleepTime)} – ${_timeLabel(_wakeTime)}'
                      : '-- --',
                  height: 100,
                  child: !hasData
                      ? Center(
                          child: Text(
                            'NO DATA YET',
                            style: _inter(12, color: AppTheme.textTertiary, letterSpacing: 1.2),
                          ),
                        )
                      : CustomPaint(
                          painter: _HypnogramPainter(
                            segments: _segments,
                            sleepTime: _sleepTime,
                            wakeTime: _wakeTime,
                            totalDuration: _totalDuration,
                            awakeDuration: _awakeDuration,
                            lightDuration: _lightDuration,
                            deepDuration: _deepDuration,
                            remDuration: _remDuration,
                          ),
                          child: const SizedBox.expand(),
                        ),
                ),
                const SizedBox(height: 8),
                const Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    LegendDot(color: AppTheme.amber, label: 'Awake'),
                    LegendDot(color: AppTheme.bpColor, label: 'REM'),
                    LegendDot(color: AppTheme.softBlue, label: 'Light'),
                    LegendDot(color: _kDeepColor, label: 'Deep'),
                  ],
                ),
                const SizedBox(height: 10),

                // ── 4. Stats row ─────────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: MetricStatCard(
                        label: 'EFFICIENCY',
                        value: hasData ? _efficiency() : '--',
                        unit: '',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MetricStatCard(
                        label: 'DEEP SLEEP',
                        value: hasData ? _fmt(_deepDuration) : '--',
                        unit: '',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MetricStatCard(
                        label: 'REM SLEEP',
                        value: hasData ? _fmt(_remDuration) : '--',
                        unit: '',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // ── 5. Sleep stages breakdown ────────────────────────────────
                _StagesBreakdownCard(
                  hasData: hasData,
                  awakeDuration: _awakeDuration,
                  lightDuration: _lightDuration,
                  deepDuration: _deepDuration,
                  remDuration: _remDuration,
                  totalDuration: _totalDuration,
                  fmt: _fmt,
                ),
                const SizedBox(height: 10),

                // ── 6. Sleep summary ──────────────────────────────────────────
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SLEEP SUMMARY',
                        style: _inter(
                          11,
                          weight: FontWeight.w600,
                          color: AppTheme.textTertiary,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _SummaryRow(
                        label: 'Sleep Duration',
                        value: hasData ? _fmt(_totalDuration) : '--',
                      ),
                      const Divider(color: AppTheme.div, height: 20),
                      _SummaryRow(
                        label: 'Sleep Time',
                        value: hasData && _sleepTime > 0
                            ? _timeLabel(_sleepTime)
                            : '--',
                      ),
                      const Divider(color: AppTheme.div, height: 20),
                      _SummaryRow(
                        label: 'Wake Time',
                        value: hasData && _wakeTime > 0
                            ? _timeLabel(_wakeTime)
                            : '--',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── 7. Vitals during sleep ────────────────────────────────────
                Text(
                  'VITALS DURING SLEEP',
                  style: _inter(
                    11,
                    weight: FontWeight.w600,
                    color: AppTheme.textTertiary,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: MetricStatCard(
                        label: 'AVG HEART RATE',
                        value: _avgHr > 0 ? '$_avgHr' : '--',
                        unit: _avgHr > 0 ? 'bpm' : '',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MetricStatCard(
                        label: 'AVG BLOOD OXYGEN',
                        value: _avgSpo2 > 0 ? '$_avgSpo2' : '--',
                        unit: _avgSpo2 > 0 ? '%' : '',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MetricStatCard(
                        label: 'AVG HRV',
                        value: _avgHrv > 0 ? '$_avgHrv' : '--',
                        unit: _avgHrv > 0 ? 'ms' : '',
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 20),

              // ── 8. 7-day trend — collapse when empty (2+ days required)
              if (!TrendMath.hasEnoughTrendData(trendVals) && !_dbOffline)
                const NotEnoughTrendDataCard(metric: 'sleep')
              else
                MetricChartCard(
                  headerLabel: 'LAST 7 DAYS TREND',
                  rangeLabel: avgDur > 0
                      ? 'avg ${_fmt(avgDur)}${avgScore > 0 ? " · score $avgScore" : ""}'
                      : '-- --',
                  height: 128,
                  yLabels: const ['8h', '6h', '4h', '2h'],
                  barCount: trendVals.length,
                  xLabels: _trendDayLabels(),
                  child: CustomPaint(
                    painter: _SleepBarPainter(values: trendVals),
                    child: const SizedBox.expand(),
                  ),
                ),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}


// ── Stages breakdown card ─────────────────────────────────────────────────────

class _StagesBreakdownCard extends StatelessWidget {
  final bool hasData;
  final int awakeDuration,
      lightDuration,
      deepDuration,
      remDuration,
      totalDuration;
  final String Function(int) fmt;

  const _StagesBreakdownCard({
    required this.hasData,
    required this.awakeDuration,
    required this.lightDuration,
    required this.deepDuration,
    required this.remDuration,
    required this.totalDuration,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final total = totalDuration > 0 ? totalDuration : 1;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SLEEP STAGE BREAKDOWN',
            style: _inter(
              11,
              weight: FontWeight.w600,
              color: AppTheme.textTertiary,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 14),
          _StageRow(
            label: 'Time Awake',
            value: hasData ? fmt(awakeDuration) : '--',
            progress: hasData ? (awakeDuration / total).clamp(0.0, 1.0) : 0.0,
            color: AppTheme.amber,
          ),
          const SizedBox(height: 12),
          _StageRow(
            label: 'Light Sleep',
            value: hasData ? fmt(lightDuration) : '--',
            progress: hasData ? (lightDuration / total).clamp(0.0, 1.0) : 0.0,
            color: AppTheme.softBlue,
          ),
          const SizedBox(height: 12),
          _StageRow(
            label: 'Deep Sleep',
            value: hasData ? fmt(deepDuration) : '--',
            progress: hasData ? (deepDuration / total).clamp(0.0, 1.0) : 0.0,
            color: _kDeepColor,
          ),
          const SizedBox(height: 12),
          _StageRow(
            label: 'REM Sleep',
            value: hasData ? fmt(remDuration) : '--',
            progress: hasData ? (remDuration / total).clamp(0.0, 1.0) : 0.0,
            color: AppTheme.bpColor,
          ),
        ],
      ),
    );
  }
}

// ── Stage Row ──────────────────────────────────────────────────────────────────

class _StageRow extends StatelessWidget {
  final String label, value;
  final double progress;
  final Color color;
  const _StageRow({
    required this.label,
    required this.value,
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _inter(13, weight: FontWeight.w500),
                  ),
                ),
                const SizedBox(width: 8),
                Text(value, style: _inter(12, color: AppTheme.textSec)),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: AppTheme.div,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 4,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

// ── Summary Row ────────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final String label, value;
  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _inter(13, color: AppTheme.textSec),
        ),
      ),
      const SizedBox(width: 8),
      Text(value, style: _inter(13, weight: FontWeight.w600)),
    ],
  );
}

// ── Hypnogram Painter ──────────────────────────────────────────────────────────

class _HypnogramPainter extends CustomPainter {
  final List<Map<String, int>> segments;
  final int sleepTime, wakeTime;
  final int totalDuration,
      awakeDuration,
      lightDuration,
      deepDuration,
      remDuration;

  const _HypnogramPainter({
    required this.segments,
    required this.sleepTime,
    required this.wakeTime,
    required this.totalDuration,
    required this.awakeDuration,
    required this.lightDuration,
    required this.deepDuration,
    required this.remDuration,
  });

  // Normalized Y position for each stage (0=top, 1=bottom)
  static const _yPos = {
    _kAwake: 0.05,
    _kRem: 0.35,
    _kLight: 0.62,
    _kDeep: 0.88,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final window = (wakeTime > sleepTime && sleepTime > 0)
        ? (wakeTime - sleepTime).toDouble()
        : totalDuration.toDouble();
    if (window <= 0) return;

    final segs = segments.isNotEmpty ? segments : _syntheticSegs();
    if (segs.isEmpty) return;

    final fillPaint = Paint()..style = PaintingStyle.fill;
    final linePath = Path();
    bool first = true;

    for (int i = 0; i < segs.length; i++) {
      final seg = segs[i];
      final startOff = (seg['start']! - (sleepTime > 0 ? sleepTime : 0))
          .clamp(0, window.toInt())
          .toDouble();
      final endOff = (seg['end']! - (sleepTime > 0 ? sleepTime : 0))
          .clamp(0, window.toInt())
          .toDouble();
      final type = seg['type']!;
      final x1 = startOff / window * size.width;
      final x2 = endOff / window * size.width;
      final y = (_yPos[type] ?? 0.62) * size.height;
      final color = _stageColors[type] ?? AppTheme.softBlue;

      // Shaded area under segment
      fillPaint.color = color.withValues(alpha: 0.18);
      canvas.drawPath(
        Path()
          ..moveTo(x1, size.height)
          ..lineTo(x1, y)
          ..lineTo(x2, y)
          ..lineTo(x2, size.height)
          ..close(),
        fillPaint,
      );

      // Step line
      if (first) {
        linePath.moveTo(x1, y);
        first = false;
      } else {
        linePath.lineTo(x1, y); // vertical step
      }
      linePath.lineTo(x2, y);
    }

    canvas.drawPath(
      linePath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.75)
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke,
    );
  }

  List<Map<String, int>> _syntheticSegs() {
    if (totalDuration <= 0) return [];
    final base = sleepTime > 0 ? sleepTime : 0;
    int cursor = base;
    final parts = [
      (
        awakeDuration > 0 ? (awakeDuration ~/ 2).clamp(600, 1800) : 900,
        _kAwake,
      ),
      (lightDuration > 0 ? (lightDuration * 0.35).round() : 2700, _kLight),
      (deepDuration > 0 ? deepDuration : 3600, _kDeep),
      (remDuration > 0 ? remDuration : 2400, _kRem),
      (lightDuration > 0 ? (lightDuration * 0.35).round() : 2400, _kLight),
      (awakeDuration > 0 ? (awakeDuration ~/ 2).clamp(300, 900) : 600, _kAwake),
    ];
    final segs = <Map<String, int>>[];
    for (final p in parts) {
      if (p.$1 <= 0) continue;
      segs.add({'start': cursor, 'end': cursor + p.$1, 'type': p.$2});
      cursor += p.$1;
    }
    return segs;
  }

  @override
  bool shouldRepaint(_HypnogramPainter old) =>
      old.segments != segments ||
      old.sleepTime != sleepTime ||
      old.totalDuration != totalDuration;
}

// ── Sleep Bar Painter (7-day trend) ────────────────────────────────────────────

class _SleepBarPainter extends CustomPainter {
  final List<int> values;
  const _SleepBarPainter({required this.values});

  /// Fixed scale matching the Y-axis labels (8h / 6h / 4h / 2h).
  static const _maxY = 8 * 3600.0; // 8 hours in seconds
  static const _yHours = [8, 6, 4, 2];

  @override
  void paint(Canvas canvas, Size size) {
    // Subtle horizontal grid lines at each Y-axis label.
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 0.5;
    for (final h in _yHours) {
      final yPos = size.height - (h / 8.0) * size.height;
      canvas.drawLine(Offset(0, yPos), Offset(size.width, yPos), gridPaint);
    }

    if (values.isEmpty) return;
    final maxVal = values.fold(0, math.max).toDouble();
    if (maxVal <= 0) return;

    final n = values.length;
    // Equal-width slots so bar centers line up with centered day labels.
    // ~5–6 px gap between bars; bars extend to fill the rest of each slot.
    final slotW = size.width / n;
    const gap = 5.5;
    final barW = math.max(4.0, slotW - gap);

    final paint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < n; i++) {
      final v = values[i];
      final ratio = (v / _maxY).clamp(0.0, 1.0);
      final barH = v > 0 ? math.max(3.0, ratio * size.height) : 3.0;
      final x = i * slotW + (slotW - barW) / 2;
      paint.color = v > 0
          ? AppTheme.sleepColor.withValues(alpha: 0.85)
          : AppTheme.div;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - barH, barW, barH),
          const Radius.circular(3),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SleepBarPainter old) => old.values != values;
}
