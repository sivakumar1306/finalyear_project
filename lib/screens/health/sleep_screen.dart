import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/health_connect_service.dart';
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
import '../../widgets/metric_chart_card.dart';
import '../../widgets/metric_stat_card.dart';


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
      _loadHistory();
    });
  }



  Future<void> _init() async {
    if (!mounted) return;
    try {
      final today = DateTime.now();
      final isToday =
          _selectedDate.year == today.year &&
          _selectedDate.month == today.month &&
          _selectedDate.day == today.day;
      if (isToday && context.read<BleProvider>().isConnected) {
        await _fetchFromRing();
      } else {
        await _loadDayFromDb();
      }
      await _loadVitals();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

  Future<void> _fetchFromRing() async {
    // Try primary: getTodaySleep (daily summary)
    try {
      final data = await _ble.getTodaySleep();
      if (data.isNotEmpty && data != '{}') {
        final d = jsonDecode(data) as Map<String, dynamic>;
        final hasOld = (d['totalSleepDuration'] as num? ?? 0).toInt() > 0;
        final hasNew = d.containsKey('st') && (d['st'] as num? ?? 0).toInt() > 0;
        if (hasOld || hasNew) {
          _parseSleepData(data);
          return;
        }
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'sleep_screen',
        error: e,
        stackTrace: st,
        customMessage: 'getTodaySleep failed, trying syncSleep fallback',
      );
    }
    // Fallback 1: large-data sync (handles both SleepDisplay and SleepNewProto)
    try {
      final data = await _ble.syncSleep();
      if (data.isNotEmpty && data != '{}' && data != '[]') {
        // syncSleep may return either format; try parsing directly
        // If it's a list wrapper, check first element
        try {
          final d = jsonDecode(data);
          if (d is Map<String, dynamic> && (d.containsKey('totalSleepDuration') || d.containsKey('st'))) {
            _parseSleepData(data);
            return;
          }
        } catch (_) {}
        // Some firmware returns empty list for syncSleep when no new data - try getSleep
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'sleep_screen',
        error: e,
        stackTrace: st,
        customMessage: 'syncSleep fallback failed',
      );
    }
    // Fallback 2: getSleep for today (dayIndex 0) - explicit per-day fetch
    try {
      final data = await _ble.getSleep(0);
      if (data.isNotEmpty && data != '{}') {
        _parseSleepData(data);
        return;
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'sleep_screen',
        error: e,
        stackTrace: st,
        customMessage: 'getSleep(0) fallback failed',
      );
    }
    await _loadDayFromDb();
  }

  void _parseSleepData(String jsonStr, {DateTime? date}) {
    try {
      final d = jsonDecode(jsonStr) as Map<String, dynamic>;
      int total = (d['totalSleepDuration'] as num? ?? 0).toInt();
      int deep = (d['deepDuration'] as num? ?? 0).toInt();
      int light = (d['lightDuration'] as num? ?? 0).toInt();
      int rem = (d['remDuration'] as num? ?? 0).toInt();
      int awake = (d['awakeDuration'] as num? ?? 0).toInt();
      int st = (d['sleepTime'] as num? ?? 0).toInt();
      int et = (d['wakeTime'] as num? ?? 0).toInt();
      dynamic rawList = d['list'];

      // New proto fallback: st/et + list with d/t (QRing large-data path)
      // This is what QRing's syncSleep (LargeDataHandler.syncSleepList) returns
      // when the ring firmware uses SleepNewProtoResp instead of SleepDisplay.
      if ((total <= 0 || rawList == null) && d.containsKey('st')) {
        st = (d['st'] as num? ?? st).toInt();
        et = (d['et'] as num? ?? et).toInt();
        rawList = d['list'];
        // Some new-proto payloads nest list inside data/stList, try alternative keys
        rawList ??= d['data'];
      }
      // Also handle case where JSON is directly the new-proto map without wrapper
      // e.g. from syncSleep's sleepNewProtoToMap: {st,et,list:[{d,t}]}
      if (total <= 0 && st > 0 && rawList != null) {
        final segsTmp = _parseSegments(rawList, st, et);
        if (segsTmp.isNotEmpty) {
          int calcTotal = 0, calcDeep = 0, calcLight = 0, calcRem = 0, calcAwake = 0;
          for (final s in segsTmp) {
            final dur = s['end']! - s['start']!;
            if (dur <= 0) continue;
            calcTotal += dur;
            switch (s['type']) {
              case _kDeep:
                calcDeep += dur;
                break;
              case _kLight:
                calcLight += dur;
                break;
              case _kRem:
                calcRem += dur;
                break;
              case _kAwake:
                calcAwake += dur;
                break;
            }
          }
          if (calcTotal > 0) {
            if (total <= 0) total = calcTotal;
            if (deep == 0) deep = calcDeep;
            if (light == 0) light = calcLight;
            if (rem == 0) rem = calcRem;
            if (awake == 0) awake = calcAwake;
            final score = _calcScore(total, deep, rem, st, et);
            if (!mounted) return;
            setState(() {
              _totalDuration = total;
              _deepDuration = deep;
              _lightDuration = light;
              _remDuration = rem;
              _awakeDuration = awake;
              _sleepTime = st;
              _wakeTime = et;
              _sleepScore = score;
              _segments = segsTmp;
            });
            _saveToDb(total, deep, light, rem, awake, score, st, et, date: date ?? _selectedDate);
            return;
          }
        }
      }

      if (total <= 0) {
        // Try Supabase fallback but also report to Supabase for visibility
        IncidentService.reportUnhandled(
          source: 'sleep_screen',
          error: Exception('sleep total <=0'),
          customMessage: 'getTodaySleep returned empty - falling back to DB',
          extraInfo: {'raw': jsonStr.substring(0, jsonStr.length.clamp(0, 500))},
        );
        _loadDayFromDb();
        return;
      }
      final segs = _parseSegments(rawList, st, et);
      final score = _calcScore(total, deep, rem, st, et);
      if (!mounted) return;
      setState(() {
        _totalDuration = total;
        _deepDuration = deep;
        _lightDuration = light;
        _remDuration = rem;
        _awakeDuration = awake;
        _sleepTime = st;
        _wakeTime = et;
        _sleepScore = score;
        _segments = segs;
      });
      _saveToDb(total, deep, light, rem, awake, score, st, et, date: date ?? _selectedDate);
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'sleep_screen',
        error: e,
        stackTrace: st,
        customMessage: '_parseSleepData failed',
        extraInfo: {'raw': jsonStr.substring(0, jsonStr.length.clamp(0, 500))},
      );
      _loadDayFromDb();
    }
  }

  List<Map<String, int>> _parseSegments(dynamic rawList, [int st = 0, int et = 0]) {
    if (rawList == null) return [];
    final segs = <Map<String, int>>[];
    // Detect new-proto vs old by inspecting first element keys
    final list = rawList as List<dynamic>;
    if (list.isEmpty) return [];
    final first = list.first as Map<String, dynamic>;
    final isNewProto = first.containsKey('d') || first.containsKey('t');
    if (isNewProto) {
      // New proto: each item {d, t} where d is either timestamp or duration
      // Heuristic: if d > 1000000000 treat as absolute timestamp (sec),
      // otherwise treat as duration (minutes if <500 else seconds)
      bool isTimestamp = false;
      final firstD = (first['d'] as num? ?? 0).toInt();
      if (firstD > 1000000000) isTimestamp = true;
      if (isTimestamp) {
        for (final item in list) {
          final m = item as Map<String, dynamic>;
          final s = (m['d'] as num? ?? 0).toInt();
          final t = (m['t'] as num? ?? _kLight).toInt();
          // Need end - use next item's d or et
          // Since we don't have explicit end, infer: segment ends at next start or et
          // For now treat d as start, next d as end; last segment ends at et
          // This will be corrected in post-loop
          if (s > 0) segs.add({'start': s, 'end': s + 1800, 'type': t}); // placeholder 30min
        }
        // Reconstruct ends correctly
        for (int i = 0; i < segs.length; i++) {
          final start = segs[i]['start']!;
          int end;
          if (i + 1 < segs.length) {
            end = segs[i + 1]['start']!;
          } else {
            end = et > start ? et : start + 1800;
          }
          if (end > start) {
            segs[i] = {'start': start, 'end': end, 'type': segs[i]['type']!};
          }
        }
        // If placeholder still, fallback to duration mode
        if (segs.isEmpty || segs.any((s) => s['end']! - s['start']! > 3600 * 3)) {
          // Likely mis-parsed, try duration mode instead
          segs.clear();
          int cursor = st > 0 ? st : 0;
          for (final item in list) {
            final m = item as Map<String, dynamic>;
            int dVal = (m['d'] as num? ?? 0).toInt();
            final t = (m['t'] as num? ?? _kLight).toInt();
            if (dVal <= 0) continue;
            int durSec;
            if (dVal < 500) {
              durSec = dVal * 60; // minutes -> seconds
            } else if (dVal < 10000) {
              durSec = dVal; // seconds
            } else {
              durSec = dVal; // already seconds
            }
            final s = cursor;
            final e = cursor + durSec;
            segs.add({'start': s, 'end': e, 'type': t});
            cursor = e;
          }
        }
      } else {
        // Duration mode
        int cursor = st > 0 ? st : 0;
        // If st is 0, use 0 as base; segments will be relative
        for (final item in list) {
          final m = item as Map<String, dynamic>;
          int dVal = (m['d'] as num? ?? 0).toInt();
          final t = (m['t'] as num? ?? _kLight).toInt();
          if (dVal <= 0) continue;
          int durSec;
          if (dVal < 500) {
            durSec = dVal * 60;
          } else if (dVal < 10000) {
            durSec = dVal;
          } else {
            durSec = dVal;
          }
          final s = cursor;
          final e = cursor + durSec;
          segs.add({'start': s, 'end': e, 'type': t});
          cursor = e;
        }
        // If st was 0, shift so last segment ends at et if available
        if (st == 0 && et > 0 && segs.isNotEmpty) {
          final shift = et - segs.last['end']!;
          if (shift != 0) {
            for (int i = 0; i < segs.length; i++) {
              segs[i] = {
                'start': segs[i]['start']! + shift,
                'end': segs[i]['end']! + shift,
                'type': segs[i]['type']!
              };
            }
          }
        }
      }
      return segs.where((s) => s['end']! > s['start']!).toList();
    } else {
      // Old proto: sleepStart/sleepEnd/type
      for (final item in list) {
        final m = item as Map<String, dynamic>;
        final s = (m['sleepStart'] as num? ?? m['start'] as num? ?? 0).toInt();
        final e = (m['sleepEnd'] as num? ?? m['end'] as num? ?? 0).toInt();
        final t = (m['type'] as num? ?? m['t'] as num? ?? _kLight).toInt();
        if (s > 0 && e > s) segs.add({'start': s, 'end': e, 'type': t});
      }
      return segs;
    }
  }

  int _calcScore(int total, int deep, int rem, int st, int et) {
    final window = (st > 0 && et > 0) ? (et - st) : total;
    final efficiency = window > 0 ? (total / window * 100).clamp(0, 100) : 0;
    final deepPct = total > 0 ? (deep / total * 100).clamp(0, 40) : 0;
    final remPct = total > 0 ? (rem / total * 100).clamp(0, 30) : 0;
    return (efficiency * 0.4 + deepPct * 1.0 + remPct * 0.5).round().clamp(
      0,
      100,
    );
  }

  // ── DB ───────────────────────────────────────────────────────────────────────

  Future<void> _loadDayFromDb() async {
    // Try ring first for recent dates when connected (mirrors QRing's historical fetch)
    // QRing stores ~7 days on-device; Supabase is fallback/cache for offline
    try {
      bool isConnected = false;
      try {
        isConnected = context.read<BleProvider>().isConnected;
      } catch (_) {}
      final today = DateTime.now();
      final selDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final todayDay = DateTime(today.year, today.month, today.day);
      final daysDiff = todayDay.difference(selDay).inDays;
      if (isConnected && daysDiff >= 0 && daysDiff < 7) {
        try {
          final ringData = await _ble.getSleep(daysDiff);
          if (ringData.isNotEmpty && ringData != '{}' && ringData != '[]') {
            final d = jsonDecode(ringData) as Map<String, dynamic>;
            final hasOld = (d['totalSleepDuration'] as num? ?? 0).toInt() > 0;
            final hasNew = d.containsKey('st') && (d['st'] as num? ?? 0).toInt() > 0;
            if (hasOld || hasNew) {
              // Directly parse without recursing to DB on failure
              // Reuse _parseSleepData but guard against fallback loop by checking
              // if parse will succeed - we already know has data, so just parse
              _parseSleepData(ringData, date: _selectedDate);
              return;
            }
          }
        } catch (e, st) {
          IncidentService.reportUnhandled(
            source: 'sleep_screen',
            error: e,
            stackTrace: st,
            customMessage: 'getSleep($daysDiff) fallback failed',
          );
        }
        // Also try getSleepList as broader fallback (QRing sync path)
        try {
          final listData = await _ble.getSleepList(daysDiff, 1);
          if (listData.isNotEmpty && listData != '[]' && listData != '{}') {
            final decoded = jsonDecode(listData);
            if (decoded is List && decoded.isNotEmpty) {
              final first = decoded.first as Map<String, dynamic>;
              // getSleepList returns DayIndexedData with 'data' field containing sleep JSON
              final inner = first['data'] as Map<String, dynamic>?;
              if (inner != null && (inner['totalSleepDuration'] != null || inner['st'] != null)) {
                _parseSleepData(jsonEncode(inner), date: _selectedDate);
                return;
              }
            }
          }
        } catch (e, st) {
          IncidentService.reportUnhandled(
            source: 'sleep_screen',
            error: e,
            stackTrace: st,
            customMessage: 'getSleepList fallback failed',
          );
        }
      }
    } catch (_) {}

    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() => _dbOffline = false);
    try {
      final row = await SupabaseService.getSleepForDate(user.id, _selectedDate);
      if (!mounted) return;
      if (row == null) {
        setState(() {
          _totalDuration = 0;
          _deepDuration = 0;
          _lightDuration = 0;
          _remDuration = 0;
          _awakeDuration = 0;
          _sleepTime = 0;
          _wakeTime = 0;
          _sleepScore = 0;
          _segments = [];
        });
        return;
      }
      setState(() {
        _totalDuration = (row['total_duration'] as num? ?? 0).toInt();
        _deepDuration = (row['deep_duration'] as num? ?? 0).toInt();
        _lightDuration = (row['light_duration'] as num? ?? 0).toInt();
        _remDuration = (row['rem_duration'] as num? ?? 0).toInt();
        _awakeDuration = (row['awake_duration'] as num? ?? 0).toInt();
        _sleepTime = (row['sleep_time'] as num? ?? 0).toInt();
        _wakeTime = (row['wake_time'] as num? ?? 0).toInt();
        _sleepScore = (row['sleep_score'] as num? ?? 0).toInt();
        _segments = [];
      });
    } catch (e) {
      if (mounted && isNetworkError(e)) setState(() => _dbOffline = true);
    }
  }

  Future<void> _loadVitals() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      final results = await Future.wait([
        SupabaseService.getHrForDate(user.id, _selectedDate),
        SupabaseService.getSpo2ForDate(user.id, _selectedDate),
        SupabaseService.getHrvForDate(user.id, _selectedDate),
      ]);
      if (!mounted) return;
      final hrRow = results[0];
      final spo2Row = results[1];
      final hrvRow = results[2];
      setState(() {
        _avgHr = (hrRow?['avg_hr'] as num? ?? 0).toInt();
        _avgSpo2 = (spo2Row?['avg_spo2'] as num? ?? 0).toInt();
        _avgHrv = (hrvRow?['avg_hrv'] as num? ?? 0).toInt();
      });
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'sleep_screen',
        error: e,
        stackTrace: st,
        customMessage: 'load last night avg failed',
      );
    }
  }

  Future<void> _loadHistory() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 6));
    // Try ring first when connected (mirrors QRing's historical sync)
    try {
      bool isConnected = false;
      try {
        isConnected = context.read<BleProvider>().isConnected;
      } catch (_) {}
      if (isConnected) {
        try {
          final ringJson = await _ble.getSleepList(0, 7);
          if (ringJson.isNotEmpty && ringJson != '[]' && ringJson != '{}') {
            final decoded = jsonDecode(ringJson);
            if (decoded is List && decoded.isNotEmpty) {
              final List<Map<String, dynamic>> ringRows = [];
              for (final entry in decoded) {
                final m = entry as Map<String, dynamic>;
                final dayIdx = (m['dayIndex'] as num? ?? m['day_index'] as num? ?? -1).toInt();
                final data = m['data'] as Map<String, dynamic>?;
                if (data == null) continue;
                // Support both old (totalSleepDuration) and new (st/et + list d/t) formats
                int total = (data['totalSleepDuration'] as num? ?? 0).toInt();
                int st = (data['sleepTime'] as num? ?? data['st'] as num? ?? 0).toInt();
                int et = (data['wakeTime'] as num? ?? data['et'] as num? ?? 0).toInt();
                if (total <= 0 && st > 0 && data['list'] != null) {
                  // New proto: compute from segments
                  final segs = _parseSegments(data['list'], st, et);
                  int calcTotal = 0;
                  for (final s in segs) calcTotal += s['end']! - s['start']!;
                  if (calcTotal > 0) total = calcTotal;
                }
                if (total <= 0) continue;
                final d = now.subtract(Duration(days: dayIdx));
                final dateStr =
                    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                final deep = (data['deepDuration'] as num? ?? 0).toInt();
                final light = (data['lightDuration'] as num? ?? 0).toInt();
                final rem = (data['remDuration'] as num? ?? 0).toInt();
                final score = (total > 0 && deep >= 0 && rem >= 0) ? _calcScore(total, deep, rem, st, et) : 0;
                ringRows.add({
                  'date': dateStr,
                  'total_duration': total,
                  'deep_duration': deep,
                  'light_duration': light,
                  'rem_duration': rem,
                  'sleep_score': score,
                });
                // Cache to Supabase for offline use (best-effort)
                try {
                  await SupabaseService.upsertSleep(
                    userId: user.id,
                    date: DateTime(d.year, d.month, d.day),
                    totalDuration: total,
                    deepDuration: deep,
                    lightDuration: light,
                    remDuration: rem,
                    awakeDuration: (data['awakeDuration'] as num? ?? 0).toInt(),
                    sleepScore: score,
                    sleepTime: st,
                    wakeTime: et,
                  );
                } catch (_) {}
              }
              if (ringRows.isNotEmpty) {
                // Merge ring rows with existing Supabase rows, preferring ring for recent days
                try {
                  final supaRows = await SupabaseService.getSleepHistory(
                    userId: user.id,
                    from: DateTime(from.year, from.month, from.day),
                    to: DateTime(now.year, now.month, now.day),
                  );
                  final byDate = {for (final r in supaRows) r['date'] as String: r};
                  for (final r in ringRows) byDate[r['date'] as String] = r;
                  final merged = byDate.values.toList()
                    ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
                  if (!mounted) return;
                  setState(() => _historyRows = merged);
                  return;
                } catch (_) {
                  if (!mounted) return;
                  setState(() => _historyRows = ringRows);
                  return;
                }
              }
            }
          }
        } catch (e, st) {
          IncidentService.reportUnhandled(
            source: 'sleep_screen',
            error: e,
            stackTrace: st,
            customMessage: 'getSleepList history fallback failed',
          );
        }
      }
    } catch (_) {}
    try {
      final rows = await SupabaseService.getSleepHistory(
        userId: user.id,
        from: DateTime(from.year, from.month, from.day),
        to: DateTime(now.year, now.month, now.day),
      );
      if (!mounted) return;
      setState(() => _historyRows = rows);
    } catch (e) {
      if (mounted && isNetworkError(e)) setState(() => _dbOffline = true);
    }
  }

  Future<void> _saveToDb(
    int total,
    int deep,
    int light,
    int rem,
    int awake,
    int score,
    int st,
    int et, {
    DateTime? date,
  }) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.upsertSleep(
        userId: user.id,
        date: date ?? DateTime.now(),
        totalDuration: total,
        deepDuration: deep,
        lightDuration: light,
        remDuration: rem,
        awakeDuration: awake,
        sleepScore: score,
        sleepTime: st,
        wakeTime: et,
      );
      if (mounted) context.read<BleProvider>().updateSleepData(total, score);
      // Two-way sync: push last night's sleep into Health Connect.
      if (st > 0) {
        unawaited(
          HealthConnectService.instance.tryWriteSleep(
            sleepTime: DateTime.fromMillisecondsSinceEpoch(st * 1000),
            wakeTime: DateTime.fromMillisecondsSinceEpoch(
              (et > 0 ? et : st + 3600) * 1000,
            ),
            lightMinutes: light ~/ 60,
            deepMinutes: deep ~/ 60,
            remMinutes: rem ~/ 60,
            awakeMinutes: awake ~/ 60,
          ),
        );
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'sleep_screen',
        error: e,
        stackTrace: st,
        customMessage: '_saveToDb failed',
      );
    }
  }

  // ── Computed helpers ─────────────────────────────────────────────────────────

  String _fmt(int secs) {
    if (secs <= 0) return '--';
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m}m';
  }

  String _timeLabel(int ts) {
    if (ts <= 0) return '--';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final suffix = h < 12 ? 'am' : 'pm';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$m$suffix';
  }

  String _efficiency() {
    if (_sleepTime <= 0 || _wakeTime <= 0 || _totalDuration <= 0) return '--';
    final window = _wakeTime - _sleepTime;
    if (window <= 0) return '--';
    return '${(_totalDuration / window * 100).round()}%';
  }

  String _quality() {
    if (_sleepScore >= 85) return 'Excellent';
    if (_sleepScore >= 70) return 'Good';
    if (_sleepScore >= 55) return 'Fair';
    if (_sleepScore > 0) return 'Poor';
    return '--';
  }

  int _avgHistoryScore() {
    final vals = _historyRows
        .map((r) => (r['sleep_score'] as num? ?? 0).toInt())
        .where((v) => v > 0)
        .toList();
    if (vals.isEmpty) return 0;
    return vals.fold(0, (a, b) => a + b) ~/ vals.length;
  }

  int _avgHistoryDuration() {
    final vals = _historyRows
        .map((r) => (r['total_duration'] as num? ?? 0).toInt())
        .where((v) => v > 0)
        .toList();
    if (vals.isEmpty) return 0;
    return vals.fold(0, (a, b) => a + b) ~/ vals.length;
  }

  List<int> _last7Bars() {
    final now = DateTime.now();
    final bars = <int>[];
    for (int i = 6; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final row = _historyRows.firstWhere(
        (r) => r['date'] == key,
        orElse: () => <String, dynamic>{},
      );
      bars.add((row['total_duration'] as num? ?? 0).toInt());
    }
    return bars;
  }

  /// Day-of-week letters for the last 7 days (oldest → newest), matching
  /// `_last7Bars()` order so each bar sits over its label.
  List<String> _trendDayLabels() {
    const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final now = DateTime.now();
    return List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return names[d.weekday - 1];
    });
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
              builder: (_) => const VitalNoteScreen(
                title: 'Sleep',
                heading: 'About Sleep',
                intro:
                    'Your ring tracks time asleep and cycles through light, '
                    'deep, and REM stages — the sleep score blends duration '
                    'and how unbroken that time was.',
                ranges: [
                  VitalRange(
                    label: 'Poor',
                    range: '0–39',
                    color: AppTheme.danger,
                  ),
                  VitalRange(
                    label: 'Fair',
                    range: '40–59',
                    color: AppTheme.amber,
                  ),
                  VitalRange(
                    label: 'Good',
                    range: '60–79',
                    color: AppTheme.sleepColor,
                  ),
                  VitalRange(
                    label: 'Excellent',
                    range: '80–100',
                    color: AppTheme.success,
                  ),
                ],
                tips: [
                  VitalTip(
                    icon: Icons.bedtime_rounded,
                    color: AppTheme.sleepColor,
                    title: 'Aim for 7–9 hours',
                    tip:
                        'Most adults need 7–9 hours a night — consistently '
                        'under 6 shows up as a lower score even with deep sleep.',
                  ),
                  VitalTip(
                    icon: Icons.schedule_rounded,
                    color: AppTheme.gold,
                    title: 'Consistency matters',
                    tip:
                        'Going to bed and waking at the same time daily '
                        'improves quality more than chasing extra hours.',
                  ),
                ],
                didYouKnow:
                    'Deep sleep handles physical recovery, REM handles '
                    'memory and mood — you need a healthy mix of both.',
              ),
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
                    ? 'Score $_sleepScore · ${_quality()}'
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: const [
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
              const SizedBox(height: 20),

              // ── 8. 7-day trend ─────────────────────────────────────────────
              MetricChartCard(
                headerLabel: 'LAST 7 DAYS TREND',
                rangeLabel: avgDur > 0
                    ? 'avg ${_fmt(avgDur)}${avgScore > 0 ? " · score $avgScore" : ""}'
                    : '-- --',
                height: 128,
                yLabels: const ['8h', '6h', '4h', '2h'],
                barCount: trendVals.length,
                xLabels: _trendDayLabels(),
                child: trendVals.every((v) => v == 0)
                    ? Center(
                        child: Text(
                          'NO DATA YET',
                          style: _inter(12, color: AppTheme.textTertiary, letterSpacing: 1.2),
                        ),
                      )
                    : CustomPaint(
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: _inter(13, weight: FontWeight.w500)),
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
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: _inter(13, color: AppTheme.textSec)),
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
