import 'dart:convert';
import 'health_engine.dart';

// Pure sleep domain — no Widget, no BuildContext.
// Extracted from lib/screens/health/sleep_screen.dart:216-437 + 757-811 + 1267-1376
// Service flavor delegates scoring to HealthEngine (remote-tunable thresholds).

class SleepEngine {
  // SDK constants
  static const int kDeep = 0;
  static const int kLight = 1;
  static const int kAwake = 2;
  static const int kRem = 3;

  // Normalized Y for hypnogram painter (kept here for single truth, painter reads via engine)
  static const Map<int, double> yPos = {
    kAwake: 0.05,
    kRem: 0.35,
    kLight: 0.62,
    kDeep: 0.88,
  };

  // Pure scoring — mirrors HealthEngine.calcSleepScore but static for engine-internal use
  static int calcScore(int total, int deep, int rem, int st, int et) =>
      HealthEngine.instance.calcSleepScore(total: total, deep: deep, rem: rem, st: st, et: et);

  static double efficiency(int total, int st, int et) {
    if (st <= 0 || et <= 0 || total <= 0) return 0;
    final window = et - st;
    if (window <= 0) return 0;
    return (total / window * 100).clamp(0, 100).toDouble();
  }

  static String efficiencyLabel(int total, int st, int et) {
    if (st <= 0 || et <= 0 || total <= 0) return '--';
    final window = et - st;
    if (window <= 0) return '--';
    return '${(total / window * 100).round()}%';
  }

  // Parse raw list -> segments
  static List<Map<String, int>> parseSegments(dynamic rawList, [int st = 0, int et = 0]) {
    if (rawList == null) return [];
    final list = rawList as List<dynamic>;
    if (list.isEmpty) return [];
    final first = list.first as Map<String, dynamic>;
    final isNewProto = first.containsKey('d') || first.containsKey('t');
    if (isNewProto) {
      return _parseNewProto(list, st, et);
    } else {
      return _parseOldProto(list);
    }
  }

  static List<Map<String, int>> _parseNewProto(List<dynamic> list, int st, int et) {
    final segs = <Map<String, int>>[];
    final first = list.first as Map<String, dynamic>;
    final firstD = (first['d'] as num? ?? 0).toInt();
    final isTimestamp = firstD > 1000000000;
    if (isTimestamp) {
      for (final item in list) {
        final m = item as Map<String, dynamic>;
        final s = (m['d'] as num? ?? 0).toInt();
        final t = (m['t'] as num? ?? kLight).toInt();
        if (s > 0) segs.add({'start': s, 'end': s + 1800, 'type': t});
      }
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
      if (segs.isEmpty || segs.any((s) => s['end']! - s['start']! > 3600 * 3)) {
        segs.clear();
        int cursor = st > 0 ? st : 0;
        for (final item in list) {
          final m = item as Map<String, dynamic>;
          int dVal = (m['d'] as num? ?? 0).toInt();
          final t = (m['t'] as num? ?? kLight).toInt();
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
      }
    } else {
      int cursor = st > 0 ? st : 0;
      for (final item in list) {
        final m = item as Map<String, dynamic>;
        int dVal = (m['d'] as num? ?? 0).toInt();
        final t = (m['t'] as num? ?? kLight).toInt();
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
  }

  static List<Map<String, int>> _parseOldProto(List<dynamic> list) {
    final segs = <Map<String, int>>[];
    for (final item in list) {
      final m = item as Map<String, dynamic>;
      final s = (m['sleepStart'] as num? ?? m['start'] as num? ?? 0).toInt();
      final e = (m['sleepEnd'] as num? ?? m['end'] as num? ?? 0).toInt();
      final t = (m['type'] as num? ?? m['t'] as num? ?? kLight).toInt();
      if (s > 0 && e > s) segs.add({'start': s, 'end': e, 'type': t});
    }
    return segs;
  }

  /// Result of parsing a sleep JSON payload
  static SleepParseResult parseSleepData(String jsonStr) {
    final d = jsonDecode(jsonStr) as Map<String, dynamic>;
    int total = (d['totalSleepDuration'] as num? ?? 0).toInt();
    int deep = (d['deepDuration'] as num? ?? 0).toInt();
    int light = (d['lightDuration'] as num? ?? 0).toInt();
    int rem = (d['remDuration'] as num? ?? 0).toInt();
    int awake = (d['awakeDuration'] as num? ?? 0).toInt();
    int st = (d['sleepTime'] as num? ?? 0).toInt();
    int et = (d['wakeTime'] as num? ?? 0).toInt();
    dynamic rawList = d['list'];

    if ((total <= 0 || rawList == null) && d.containsKey('st')) {
      st = (d['st'] as num? ?? st).toInt();
      et = (d['et'] as num? ?? et).toInt();
      rawList = d['list'];
      rawList ??= d['data'];
    }
    if (total <= 0 && st > 0 && rawList != null) {
      final segsTmp = parseSegments(rawList, st, et);
      if (segsTmp.isNotEmpty) {
        int calcTotal = 0, calcDeep = 0, calcLight = 0, calcRem = 0, calcAwake = 0;
        for (final s in segsTmp) {
          final dur = s['end']! - s['start']!;
          if (dur <= 0) continue;
          calcTotal += dur;
          switch (s['type']) {
            case kDeep:
              calcDeep += dur;
              break;
            case kLight:
              calcLight += dur;
              break;
            case kRem:
              calcRem += dur;
              break;
            case kAwake:
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
          final score = calcScore(total, deep, rem, st, et);
          return SleepParseResult(
            total: total, deep: deep, light: light, rem: rem, awake: awake,
            st: st, et: et, score: score, segments: segsTmp, hasData: true);
        }
      }
    }

    if (total <= 0) {
      return SleepParseResult.empty();
    }
    final segs = parseSegments(rawList, st, et);
    final score = calcScore(total, deep, rem, st, et);
    return SleepParseResult(
      total: total, deep: deep, light: light, rem: rem, awake: awake,
      st: st, et: et, score: score, segments: segs, hasData: true);
  }

  static List<Map<String, int>> syntheticSegs({
    required int totalDuration,
    required int awakeDuration,
    required int lightDuration,
    required int deepDuration,
    required int remDuration,
    required int sleepTime,
  }) {
    if (totalDuration <= 0) return [];
    final base = sleepTime > 0 ? sleepTime : 0;
    int cursor = base;
    final parts = [
      (awakeDuration > 0 ? (awakeDuration ~/ 2).clamp(600, 1800) : 900, kAwake),
      (lightDuration > 0 ? (lightDuration * 0.35).round() : 2700, kLight),
      (deepDuration > 0 ? deepDuration : 3600, kDeep),
      (remDuration > 0 ? remDuration : 2400, kRem),
      (lightDuration > 0 ? (lightDuration * 0.35).round() : 2400, kLight),
      (awakeDuration > 0 ? (awakeDuration ~/ 2).clamp(300, 900) : 600, kAwake),
    ];
    final segs = <Map<String, int>>[];
    for (final p in parts) {
      if (p.$1 <= 0) continue;
      segs.add({'start': cursor, 'end': cursor + p.$1, 'type': p.$2});
      cursor += p.$1;
    }
    return segs;
  }
}

class SleepParseResult {
  final int total, deep, light, rem, awake, st, et, score;
  final List<Map<String, int>> segments;
  final bool hasData;
  const SleepParseResult({
    required this.total, required this.deep, required this.light,
    required this.rem, required this.awake, required this.st, required this.et,
    required this.score, required this.segments, required this.hasData,
  });
  factory SleepParseResult.empty() => const SleepParseResult(
    total: 0, deep: 0, light: 0, rem: 0, awake: 0, st: 0, et: 0, score: 0, segments: [], hasData: false);
}
