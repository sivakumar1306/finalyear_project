import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../incident_service.dart';

/// Single dict HealthEngine config. Bundled defaults + Supabase remote over deep-merge + SharedPrefs offline cache.
///
/// Shape:
/// {
///   "version":1,
///   "thresholds": { "sleep":{ "excellent":80,"good":60,"fair":40 }, ... },
///   "advice": { "sleep":{ "title":"Sleep","heading":"About Sleep","intro":"...","didYouKnow":"...","tips":[...] }, ... },
///   "ranges": { "sleep":[ {"label":"Poor","range":"0–39","color":"danger"}, ... ], ... }
/// }
class HealthConfig {
  static const _prefsKey = 'health_engine_config_json';
  static const _prefsUpdatedAtKey = 'health_engine_config_updated_at';
  static const Duration kCacheTtl = Duration(minutes: 5);

  /// Bundled fallback — verbatim copy from detail screens so first install is visually identical.
  static const Map<String, dynamic> kDefaultConfig = {
    'version': 1,
    'thresholds': {
      'sleep': {'excellent': 80, 'good': 60, 'fair': 40},
      'hr': {'belowNormal': 60, 'aboveNormal': 100},
      'spo2': {'normal': 95, 'borderline': 90},
      'hrv': {'veryLow': 20, 'low': 40, 'moderate': 60, 'good': 80},
      'stress': {'relaxed': 40, 'normal': 60, 'elevated': 80},
      'bp': {
        'normalSbp': 120,
        'normalDbp': 80,
        'elevatedSbp': 130,
        'stage1Sbp': 140,
        'stage1Dbp': 90,
      },
      'temp': {'low': 36.0, 'normal': 37.2, 'elevated': 38.0},
      'activity': {
        'stepsWeight': 60,
        'caloriesWeight': 25,
        'distanceWeight': 15,
        'stepsDenom': 10000,
        'caloriesDenom': 1000,
        'distanceDenomM': 5000,
      },
    },
    'advice': {
      'sleep': {
        'title': 'Sleep',
        'heading': 'About Sleep',
        'intro':
            'Your ring tracks time asleep and cycles through light, deep, and REM stages — the sleep score blends duration and how unbroken that time was.',
        'didYouKnow':
            'Deep sleep handles physical recovery, REM handles memory and mood — you need a healthy mix of both.',
        'tips': [
          {
            'icon': 'bedtime_rounded',
            'color': 'sleepColor',
            'title': 'Aim for 7–9 hours',
            'tip':
                'Most adults need 7–9 hours a night — consistently under 6 shows up as a lower score even with deep sleep.'
          },
          {
            'icon': 'schedule_rounded',
            'color': 'gold',
            'title': 'Consistency matters',
            'tip':
                'Going to bed and waking at the same time daily improves quality more than chasing extra hours.'
          },
        ],
      },
      'heartRate': {
        'title': 'Heart Rate',
        'heading': 'About Heart Rate',
        'intro':
            'Beats per minute, measured continuously by the ring\'s optical sensor. Resting heart rate is one of the clearest day-to-day fitness signals you have.',
        'didYouKnow':
            'Caffeine, dehydration, and poor sleep can all push your resting heart rate up temporarily.',
        'tips': [
          {
            'icon': 'trending_down_rounded',
            'color': 'hrvColor',
            'title': 'Lower can be fine',
            'tip':
                'A resting rate under 60 bpm is often a sign of good cardiovascular fitness, not a problem.'
          },
          {
            'icon': 'show_chart_rounded',
            'color': 'hrColor',
            'title': 'Watch the trend',
            'tip':
                'A resting rate that\'s creeping up week over week is more meaningful than any single reading.'
          },
        ],
      },
      'spo2': {
        'title': 'Blood Oxygen',
        'heading': 'About Blood Oxygen (SpO₂)',
        'intro':
            'The percentage of oxygen your red blood cells are carrying, measured optically by the ring. Healthy adults typically sit at 95% or above.',
        'didYouKnow':
            'Cold fingers, ring fit, and movement can all cause a temporarily low or noisy reading — retry after settling.',
        'tips': [
          {
            'icon': 'nightlight_round',
            'color': 'spo2Color',
            'title': 'Dips can happen in sleep',
            'tip':
                'Brief overnight dips are common. Frequent or deep drops are worth mentioning to a doctor.'
          },
          {
            'icon': 'terrain_rounded',
            'color': 'hrvColor',
            'title': 'Altitude affects it too',
            'tip':
                'Readings naturally run a little lower at high altitude — that\'s expected, not a fault reading.'
          },
        ],
      },
      'hrv': {
        'title': 'HRV',
        'heading': 'About HRV',
        'intro':
            'Heart rate variability — the tiny variation in time between heartbeats. Higher generally means your body is more recovered and ready to handle stress.',
        'didYouKnow':
            'A rising HRV trend over time is one of the best signs that training or lifestyle changes are working.',
        'tips': [
          {
            'icon': 'fitness_center_rounded',
            'color': 'hrvColor',
            'title': 'It\'s personal',
            'tip':
                'HRV varies a lot person to person — track your own trend over weeks rather than comparing to others.'
          },
          {
            'icon': 'local_bar_rounded',
            'color': 'stressColor',
            'title': 'Alcohol drops it fast',
            'tip':
                'Alcohol, illness, and poor sleep are the most common causes of a sudden overnight dip.'
          },
        ],
      },
      'stress': {
        'title': 'Stress',
        'heading': 'About Stress',
        'intro':
            'Your ring estimates stress from heart-rate variability — how activated your nervous system is right now, not just how you feel.',
        'didYouKnow':
            'A brief spike during focused work isn\'t a problem — it\'s staying elevated for hours that matters.',
        'tips': [
          {
            'icon': 'self_improvement_rounded',
            'color': 'success',
            'title': 'Lower it fast',
            'tip':
                'A 2-minute slow-breathing break (4s in, 6s out) can visibly bring down an elevated reading.'
          },
          {
            'icon': 'bedtime_rounded',
            'color': 'sleepColor',
            'title': 'Sleep debt shows up here',
            'tip':
                'A poor night\'s sleep often reads as elevated stress the next day, even on a calm one.'
          },
        ],
      },
      'temperature': {
        'title': 'Temperature',
        'heading': 'About Temperature',
        'intro':
            'Skin temperature measured by the ring — most useful as a deviation from your own baseline, not as an absolute clinical reading.',
        'didYouKnow':
            'Skin temperature runs cooler than core body temperature — don\'t compare it directly to an oral thermometer reading.',
        'tips': [
          {
            'icon': 'show_chart_rounded',
            'color': 'tempColor',
            'title': 'Track your baseline',
            'tip':
                'Skin temperature varies person to person — a rise of 0.5°C+ from your usual baseline matters more than the absolute number.'
          },
          {
            'icon': 'schedule_rounded',
            'color': 'hrvColor',
            'title': 'It has a daily rhythm',
            'tip':
                'Temperature naturally dips overnight and rises through the day — that\'s expected, not a fever.'
          },
        ],
      },
      'bloodPressure': {
        'title': 'Blood Pressure',
        'heading': 'About Blood Pressure',
        'intro':
            'Systolic (top) over diastolic (bottom) — the pressure in your arteries as your heart beats and rests. Cuffless ring readings are an estimate, best read as a trend rather than a single exact number.',
        'didYouKnow':
            'Blood pressure naturally dips at night and rises in the morning — a single high reading isn\'t cause for alarm.',
        'tips': [
          {
            'icon': 'self_improvement_rounded',
            'color': 'success',
            'title': 'Sodium adds up fast',
            'tip':
                'Cutting back on salty, processed food is one of the quickest ways to bring elevated readings down.'
          },
          {
            'icon': 'schedule_rounded',
            'color': 'bpColor',
            'title': 'Measure the same way',
            'tip':
                'Readings taken while resting, seated, and at the same time of day are the most comparable over time.'
          },
        ],
      },
      'activity': {
        'title': 'Activity',
        'heading': 'Your Activity Score',
        'intro':
            'A single 0–100 number for how much you moved today. It blends steps, active calories and distance, weighted 60/25/15, against your personal goals from Goal Setting.',
        'didYouKnow':
            'A score of 0 shows as Lack of exercise. Short walks spread through the day usually lift the score more evenly than one long workout.',
        'tips': [
          {
            'icon': 'directions_walk_rounded',
            'color': 'softGreen',
            'title': 'Steps',
            'tip':
                'Full steps credit when you hit your daily steps goal. Under ~50% is typically sedentary; 75%+ supports heart health.'
          },
          {
            'icon': 'local_fire_department_rounded',
            'color': 'softOrange',
            'title': 'Calories',
            'tip':
                'Full calorie credit when you hit your calorie goal — about a 30-minute brisk walk for most goals. Only movement-related burn counts.'
          },
          {
            'icon': 'directions_run_rounded',
            'color': 'softBlue',
            'title': 'Distance',
            'tip':
                'Full distance credit when you hit your distance goal. Use with steps to see pace, not just total movement.'
          },
        ],
      },
    },
    'ranges': {
      'sleep': [
        {'label': 'Poor', 'range': '0–39', 'color': 'danger'},
        {'label': 'Fair', 'range': '40–59', 'color': 'amber'},
        {'label': 'Good', 'range': '60–79', 'color': 'sleepColor'},
        {'label': 'Excellent', 'range': '80–100', 'color': 'success'},
      ],
      'heartRate': [
        {'label': 'Below normal', 'range': '<60 bpm', 'color': 'hrvColor'},
        {'label': 'Normal', 'range': '60–99 bpm', 'color': 'success'},
        {'label': 'Above normal', 'range': '100+ bpm', 'color': 'danger'},
      ],
      'spo2': [
        {'label': 'Normal', 'range': '95–100%', 'color': 'success'},
        {'label': 'Borderline', 'range': '90–94%', 'color': 'amber'},
        {'label': 'Low', 'range': '<90%', 'color': 'danger'},
      ],
      'hrv': [
        {'label': 'Very Low', 'range': '0–19', 'color': 'danger'},
        {'label': 'Low', 'range': '20–39', 'color': 'stressColor'},
        {'label': 'Moderate', 'range': '40–59', 'color': 'amber'},
        {'label': 'Good', 'range': '60–79', 'color': 'success'},
        {'label': 'Excellent', 'range': '80+', 'color': 'hrvColor'},
      ],
      'stress': [
        {'label': 'Relaxed', 'range': '0–39', 'color': 'success'},
        {'label': 'Normal', 'range': '40–59', 'color': 'amber'},
        {'label': 'Elevated', 'range': '60–79', 'color': 'stressColor'},
        {'label': 'High', 'range': '80–100', 'color': 'danger'},
      ],
      'temperature': [
        {'label': 'Low', 'range': '<36.0°C', 'color': 'spo2Color'},
        {'label': 'Normal', 'range': '36.0–37.2°C', 'color': 'success'},
        {'label': 'Elevated', 'range': '37.2–38.0°C', 'color': 'tempColor'},
        {'label': 'Fever', 'range': '>38.0°C', 'color': 'danger'},
      ],
      'bloodPressure': [
        {'label': 'Normal', 'range': '<120/80', 'color': 'success'},
        {'label': 'Elevated', 'range': '120–129/<80', 'color': 'amber'},
        {'label': 'Stage 1', 'range': '130–139/80–89', 'color': 'stressColor'},
        {'label': 'Stage 2', 'range': '140+/90+', 'color': 'danger'},
      ],
      'activity': [
        {'label': 'Lack of exercise', 'range': '0', 'color': 'danger'},
        {'label': 'Sedentary', 'range': '1–24', 'color': 'danger'},
        {'label': 'Lightly active', 'range': '25–49', 'color': 'tempColor'},
        {'label': 'Moderately active', 'range': '50–74', 'color': 'spo2Color'},
        {'label': 'Highly active', 'range': '75–100', 'color': 'success'},
      ],
    },
  };

  static Map<String, dynamic> _current =
      jsonDecode(jsonEncode(kDefaultConfig)) as Map<String, dynamic>;
  static DateTime? _lastFetchAt;
  static DateTime? _lastFailReportAt;
  // Incident table was flooded (25 rows/2d from resume storm) — cache/default
  // fallback is benign, so only report uncached failures, at most 1 per 6h.
  static const Duration _failReportCooldown = Duration(hours: 6);

  static Map<String, dynamic> get current => _current;

  /// Call once at app start (before runApp) + on pull-to-refresh / resume.
  static Future<void> load() async {
    // 1) Try Supabase first.
    try {
      final client = Supabase.instance.client;
      final row = await client
          .from('health_engine_config')
          .select('config')
          .eq('id', 1)
          .maybeSingle()
          .timeout(const Duration(seconds: 6));
      final remote = row?['config'];
      if (remote is Map<String, dynamic> && remote.isNotEmpty) {
        _current = _deepMerge(
            jsonDecode(jsonEncode(kDefaultConfig)) as Map<String, dynamic>,
            remote);
        _lastFetchAt = DateTime.now();
        await _cacheToPrefs(_current);
        return;
      }
      if (remote is Map && remote.isNotEmpty) {
        final typed = Map<String, dynamic>.from(remote);
        _current = _deepMerge(
            jsonDecode(jsonEncode(kDefaultConfig)) as Map<String, dynamic>,
            typed);
        _lastFetchAt = DateTime.now();
        await _cacheToPrefs(_current);
        return;
      }
    } catch (e, st) {
      debugPrint('[HealthConfig] Supabase fetch failed: $e');
      final now = DateTime.now();
      // Expected-offline (no network / timeout): silent fallback to cache,
      // never an incident — app works fine from bundled defaults.
      final isOffline = e is TimeoutException ||
          e is SocketException ||
          e is HttpException ||
          e.toString().contains('SocketException') ||
          e.toString().contains('TimeoutException') ||
          e.toString().contains('ClientException') ||
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('Network is unreachable');
      if (!isOffline &&
          (_lastFailReportAt == null ||
              now.difference(_lastFailReportAt!) >= _failReportCooldown)) {
        // Only report when there is no usable cache — otherwise the
        // cache/default fallback covers the user and the row is just noise.
        bool hasCache = false;
        try {
          final prefs = await SharedPreferences.getInstance();
          final cached = prefs.getString(_prefsKey);
          hasCache = cached != null && cached.isNotEmpty;
        } catch (_) {}
        if (!hasCache) {
          _lastFailReportAt = now;
          IncidentService.reportUnhandled(
            source: 'health_config',
            error: e,
            stackTrace: st,
            customMessage:
                'Supabase health_engine_config fetch failed — using cache/default',
          );
        } else {
          _lastFailReportAt = now;
          debugPrint('[HealthConfig] using cached config, incident suppressed');
        }
      }
    }

    // 2) Offline fallback: SharedPreferences cache.
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefsKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final cached = jsonDecode(jsonStr);
        if (cached is Map<String, dynamic> && cached.isNotEmpty) {
          _current = _deepMerge(
              jsonDecode(jsonEncode(kDefaultConfig)) as Map<String, dynamic>,
              cached);
          return;
        }
        if (cached is Map && cached.isNotEmpty) {
          _current = _deepMerge(
              jsonDecode(jsonEncode(kDefaultConfig)) as Map<String, dynamic>,
              Map<String, dynamic>.from(cached));
          return;
        }
      }
    } catch (e) {
      debugPrint('[HealthConfig] prefs cache read failed: $e');
    }

    // 3) Bundled default stays as-is.
    _current = jsonDecode(jsonEncode(kDefaultConfig)) as Map<String, dynamic>;
  }

  static Future<void> refresh() async {
    if (_lastFetchAt != null &&
        DateTime.now().difference(_lastFetchAt!) < kCacheTtl) {
      return;
    }
    await load();
  }

  static Future<void> forceRefresh() async {
    _lastFetchAt = null;
    await load();
  }

  static Future<void> _cacheToPrefs(Map<String, dynamic> merged) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(merged));
      await prefs.setString(_prefsUpdatedAtKey, DateTime.now().toIso8601String());
    } catch (_) {}
  }

  // ── Helpers for engine consumers ────────────────────────────────────────

  static Map<String, dynamic> _asMap(Map<String, dynamic> root, String key) {
    final v = root[key];
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return const {};
  }

  static Map<String, dynamic> thresholdsFor(String metric) =>
      _asMap(_asMap(_current, 'thresholds'), metric);
  static Map<String, dynamic> adviceFor(String metric) =>
      _asMap(_asMap(_current, 'advice'), metric);
  static List<dynamic> rangesFor(String metric) {
    final r = _asMap(_current, 'ranges')[metric];
    if (r is List) return r;
    return const [];
  }

  static int intThreshold(String metric, String key, int fallback) {
    final m = thresholdsFor(metric);
    final v = m[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return fallback;
  }

  static double doubleThreshold(String metric, String key, double fallback) {
    final m = thresholdsFor(metric);
    final v = m[key];
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return fallback;
  }

  // Deep-merge: remote overwrites default recursively, but missing leaves keep default.
  static Map<String, dynamic> _deepMerge(
      Map<String, dynamic> base, Map<String, dynamic> overlay) {
    final out = Map<String, dynamic>.from(base);
    overlay.forEach((k, v) {
      if (v is Map<String, dynamic> && out[k] is Map<String, dynamic>) {
        out[k] = _deepMerge(out[k] as Map<String, dynamic>, v);
      } else if (v is Map && out[k] is Map) {
        out[k] = _deepMerge(
            Map<String, dynamic>.from(out[k] as Map), Map<String, dynamic>.from(v));
      } else {
        out[k] = v;
      }
    });
    return out;
  }
}
