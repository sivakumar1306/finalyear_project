import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/goal_prefs.dart';
import 'health_config.dart';
import 'models.dart';

// Singleton facade — single source of truth for every health determination/advice.
class HealthEngine {
  HealthEngine._();
  static final HealthEngine instance = HealthEngine._();

  // ── Public init ─────────────────────────────────────────────────────────
  /// Call once in main.dart before runApp. Also safe to call on resume/pull-to-refresh.
  Future<void> init() => HealthConfig.load();
  // Resume/open path: respect kCacheTtl (5m) so Home open + resume doesn't
  // force a network fetch every time (was the 25-row incident storm source).
  // Explicit pull-to-refresh should call HealthConfig.forceRefresh() directly.
  Future<void> refreshConfig() => HealthConfig.refresh();

  // ── Color / icon maps (string key from config → actual) ─────────────────

  Color _colorForKey(String key) => switch (key) {
        'success' => AppTheme.success,
        'danger' => AppTheme.danger,
        'amber' => AppTheme.amber,
        'sleepColor' => AppTheme.sleepColor,
        'hrColor' => AppTheme.hrColor,
        'hrvColor' => AppTheme.hrvColor,
        'spo2Color' => AppTheme.spo2Color,
        'stressColor' => AppTheme.stressColor,
        'bpColor' => AppTheme.bpColor,
        'tempColor' => AppTheme.tempColor,
        'gold' => AppTheme.gold,
        'textSec' => AppTheme.textSec,
        'softGreen' => AppTheme.softGreen,
        'softOrange' => AppTheme.softOrange,
        'softBlue' => AppTheme.softBlue,
        _ => AppTheme.textSec,
      };

  IconData _iconForKey(String key) => switch (key) {
        'bedtime_rounded' => Icons.bedtime_rounded,
        'schedule_rounded' => Icons.schedule_rounded,
        'trending_down_rounded' => Icons.trending_down_rounded,
        'show_chart_rounded' => Icons.show_chart_rounded,
        'nightlight_round' => Icons.nightlight_round,
        'terrain_rounded' => Icons.terrain_rounded,
        'fitness_center_rounded' => Icons.fitness_center_rounded,
        'local_bar_rounded' => Icons.local_bar_rounded,
        'self_improvement_rounded' => Icons.self_improvement_rounded,
        'bedtime' => Icons.bedtime_rounded,
        'local_fire_department_rounded' => Icons.local_fire_department_rounded,
        'directions_walk_rounded' => Icons.directions_walk_rounded,
        'directions_run_rounded' => Icons.directions_run_rounded,
        'lightbulb_outline_rounded' => Icons.lightbulb_outline_rounded,
        _ => Icons.info_outline_rounded,
      };

  // Exposed for tests / UI if needed
  Color colorForKey(String k) => _colorForKey(k);
  IconData iconForKey(String k) => _iconForKey(k);

  // ── Sleep ───────────────────────────────────────────────────────────────

  int calcSleepScore({
    required int total,
    required int deep,
    required int rem,
    required int st,
    required int et,
  }) {
    final window = (st > 0 && et > 0) ? (et - st) : total;
    final num efficiency = window > 0 ? (total / window * 100).clamp(0, 100) : 0;
    final num deepPct = total > 0 ? (deep / total * 100).clamp(0, 40) : 0;
    final num remPct = total > 0 ? (rem / total * 100).clamp(0, 30) : 0;
    final num v = efficiency * 0.4 + deepPct * 1.0 + remPct * 0.5;
    return v.round().clamp(0, 100);
  }

  // Overload for legacy int signature
  int calcSleepScoreInts(int total, int deep, int rem, int st, int et) =>
      calcSleepScore(total: total, deep: deep, rem: rem, st: st, et: et);

  HealthAssessment assessSleep(int score) {
    if (score <= 0) {
      return const HealthAssessment(label: 'No data', color: AppTheme.textSec, severity: HealthSeverity.unknown);
    }
    final excellent = HealthConfig.intThreshold('sleep', 'excellent', 80);
    final good = HealthConfig.intThreshold('sleep', 'good', 60);
    final fair = HealthConfig.intThreshold('sleep', 'fair', 40);
    if (score >= excellent) return const HealthAssessment(label: 'Excellent', color: AppTheme.success, severity: HealthSeverity.excellent);
    if (score >= good) return HealthAssessment(label: 'Good', color: AppTheme.sleepColor, severity: HealthSeverity.normal);
    if (score >= fair) return const HealthAssessment(label: 'Fair', color: AppTheme.amber, severity: HealthSeverity.borderline);
    return const HealthAssessment(label: 'Poor', color: AppTheme.danger, severity: HealthSeverity.atRisk);
  }

  // Keep success const for Excellent sleep — need non-const for good path to allow color mapping if config changes
  // but we keep simple: always map to theme colors as above.
  // Range list bridge to VitalNote: config ranges sleep uses colorKeys we map via colorForKey.

  // ── Heart Rate ──────────────────────────────────────────────────────────
  HealthAssessment assessHeartRate(int bpm) {
    if (bpm <= 0) return const HealthAssessment(label: 'No data', color: AppTheme.textSec, severity: HealthSeverity.unknown);
    final below = HealthConfig.intThreshold('hr', 'belowNormal', 60);
    final above = HealthConfig.intThreshold('hr', 'aboveNormal', 100);
    if (bpm < below) return const HealthAssessment(label: 'Below normal', color: AppTheme.hrvColor, severity: HealthSeverity.borderline);
    if (bpm < above) return const HealthAssessment(label: 'Normal', color: AppTheme.success, severity: HealthSeverity.normal);
    return const HealthAssessment(label: 'Above normal', color: AppTheme.danger, severity: HealthSeverity.atRisk);
  }

  // ── SpO2 ────────────────────────────────────────────────────────────────
  HealthAssessment assessSpo2(int pct) {
    if (pct <= 0) return const HealthAssessment(label: 'No data', color: AppTheme.textSec, severity: HealthSeverity.unknown);
    final normal = HealthConfig.intThreshold('spo2', 'normal', 95);
    final borderline = HealthConfig.intThreshold('spo2', 'borderline', 90);
    if (pct >= normal) return const HealthAssessment(label: 'Normal', color: AppTheme.success, severity: HealthSeverity.normal);
    if (pct >= borderline) return const HealthAssessment(label: 'Borderline', color: AppTheme.amber, severity: HealthSeverity.borderline);
    return const HealthAssessment(label: 'Low', color: AppTheme.danger, severity: HealthSeverity.atRisk);
  }

  // ── HRV ─────────────────────────────────────────────────────────────────
  HealthAssessment assessHrv(int ms) {
    if (ms <= 0) return const HealthAssessment(label: '--', color: AppTheme.textSec, severity: HealthSeverity.unknown);
    if (ms < HealthConfig.intThreshold('hrv', 'veryLow', 20)) return const HealthAssessment(label: 'Very Low', color: AppTheme.danger, severity: HealthSeverity.atRisk);
    if (ms < HealthConfig.intThreshold('hrv', 'low', 40)) return const HealthAssessment(label: 'Low', color: AppTheme.stressColor, severity: HealthSeverity.borderline);
    if (ms < HealthConfig.intThreshold('hrv', 'moderate', 60)) return const HealthAssessment(label: 'Moderate', color: AppTheme.amber, severity: HealthSeverity.borderline);
    if (ms < HealthConfig.intThreshold('hrv', 'good', 80)) return const HealthAssessment(label: 'Good', color: AppTheme.success, severity: HealthSeverity.normal);
    return const HealthAssessment(label: 'Excellent', color: AppTheme.hrvColor, severity: HealthSeverity.excellent);
  }

  Color hrvBarColor(num v) {
    if (v < 20) return AppTheme.danger;
    if (v < 40) return AppTheme.stressColor;
    if (v < 60) return AppTheme.amber;
    if (v < 80) return AppTheme.success;
    return AppTheme.hrvColor;
  }

  // ── Stress ──────────────────────────────────────────────────────────────
  HealthAssessment assessStress(int v) {
    if (v <= 0) return const HealthAssessment(label: '--', color: AppTheme.textSec, severity: HealthSeverity.unknown);
    final relaxed = HealthConfig.intThreshold('stress', 'relaxed', 40);
    final normal = HealthConfig.intThreshold('stress', 'normal', 60);
    final elevated = HealthConfig.intThreshold('stress', 'elevated', 80);
    if (v < relaxed) return const HealthAssessment(label: 'Relaxed', color: AppTheme.success, severity: HealthSeverity.normal);
    if (v < normal) return HealthAssessment(label: 'Normal', color: const Color(0xFFFBBF24), severity: HealthSeverity.normal);
    if (v < elevated) return const HealthAssessment(label: 'Elevated', color: AppTheme.stressColor, severity: HealthSeverity.borderline);
    return const HealthAssessment(label: 'High', color: AppTheme.danger, severity: HealthSeverity.atRisk);
  }

  Color stressBarColor(num v) {
    if (v < 40) return AppTheme.success;
    if (v < 60) return const Color(0xFFFBBF24);
    if (v < 80) return AppTheme.stressColor;
    return AppTheme.danger;
  }

  // ── Temperature (°C input — ring native) ────────────────────────────────
  HealthAssessment assessTemperature(double c) {
    if (c <= 0) return const HealthAssessment(label: '--', color: AppTheme.textSec, severity: HealthSeverity.unknown);
    final low = HealthConfig.doubleThreshold('temp', 'low', 36.0);
    final normal = HealthConfig.doubleThreshold('temp', 'normal', 37.2);
    final elevated = HealthConfig.doubleThreshold('temp', 'elevated', 38.0);
    if (c < low) return const HealthAssessment(label: 'Low', color: AppTheme.spo2Color, severity: HealthSeverity.borderline);
    if (c <= normal) return const HealthAssessment(label: 'Normal', color: AppTheme.success, severity: HealthSeverity.normal);
    if (c <= elevated) return const HealthAssessment(label: 'Elevated', color: AppTheme.tempColor, severity: HealthSeverity.borderline);
    return const HealthAssessment(label: 'Fever', color: AppTheme.danger, severity: HealthSeverity.atRisk);
  }

  Color tempBarColor(num v) {
    final c = v.toDouble();
    if (c < 36.0) return AppTheme.spo2Color;
    if (c <= 37.2) return AppTheme.success;
    if (c <= 38.0) return AppTheme.tempColor;
    return AppTheme.danger;
  }

  // ── Blood Pressure (delegates to staged logic but via config thresholds) ─
  HealthAssessment assessBloodPressure(int sbp, int dbp) {
    if (sbp <= 0 || dbp <= 0) return const HealthAssessment(label: 'No data', color: AppTheme.textSec, severity: HealthSeverity.unknown);
    final normalSbp = HealthConfig.intThreshold('bp', 'normalSbp', 120);
    final normalDbp = HealthConfig.intThreshold('bp', 'normalDbp', 80);
    final elevatedSbp = HealthConfig.intThreshold('bp', 'elevatedSbp', 130);
    final stage1Sbp = HealthConfig.intThreshold('bp', 'stage1Sbp', 140);
    final stage1Dbp = HealthConfig.intThreshold('bp', 'stage1Dbp', 90);
    if (sbp < normalSbp && dbp < normalDbp) return const HealthAssessment(label: 'Normal', color: AppTheme.success, severity: HealthSeverity.normal);
    if (sbp < elevatedSbp && dbp < normalDbp) return const HealthAssessment(label: 'Elevated', color: AppTheme.amber, severity: HealthSeverity.borderline);
    if (sbp < stage1Sbp && dbp < stage1Dbp) return const HealthAssessment(label: 'Stage 1', color: AppTheme.stressColor, severity: HealthSeverity.atRisk);
    return const HealthAssessment(label: 'Stage 2', color: AppTheme.danger, severity: HealthSeverity.atRisk);
  }

  // ── Activity — goal-aware ───────────────────────────────────────────────

  /// Sync version: caller supplies goals (avoids async in build).
  int calcActivityScoreWithGoals({
    required int steps,
    required double distanceM,
    required int calories,
    required GoalTargets goals,
  }) {
    final thresholds = HealthConfig.thresholdsFor('activity');
    final stepsW = (thresholds['stepsWeight'] as num?)?.toDouble() ?? 60.0;
    final calW = (thresholds['caloriesWeight'] as num?)?.toDouble() ?? 25.0;
    final distW = (thresholds['distanceWeight'] as num?)?.toDouble() ?? 15.0;

    final goalSteps = goals.steps > 0 ? goals.steps.toDouble() : 10000.0;
    final goalCals = goals.calories > 0 ? goals.calories.toDouble() : 1000.0;
    final goalDistM = goals.distanceKm > 0 ? goals.distanceKm * 1000.0 : 5000.0;

    final s = (steps / goalSteps * stepsW).clamp(0.0, stepsW);
    final c = (calories / goalCals * calW).clamp(0.0, calW);
    final d = (distanceM / goalDistM * distW).clamp(0.0, distW);
    return (s + c + d).round().clamp(0, 100);
  }

  /// Async convenience — loads GoalPrefs internally.
  Future<int> calcActivityScore({
    required int steps,
    required int calories,
    required double distanceM,
  }) async {
    final goals = await GoalPrefs.load();
    return calcActivityScoreWithGoals(steps: steps, calories: calories, distanceM: distanceM, goals: goals);
  }

  HealthAssessment assessActivity(int score) {
    if (score <= 0) return const HealthAssessment(label: 'Lack of exercise', color: AppTheme.danger, severity: HealthSeverity.unknown);
    if (score < 25) return const HealthAssessment(label: 'Sedentary', color: AppTheme.danger, severity: HealthSeverity.atRisk);
    if (score < 50) return const HealthAssessment(label: 'Lightly active', color: AppTheme.tempColor, severity: HealthSeverity.borderline);
    if (score < 75) return const HealthAssessment(label: 'Moderately active', color: AppTheme.spo2Color, severity: HealthSeverity.normal);
    return const HealthAssessment(label: 'Highly active', color: AppTheme.success, severity: HealthSeverity.excellent);
  }

  String activityLabel(int score) => assessActivity(score).label;
  Color activityLabelColor(int score) => assessActivity(score).color;

  /// Human-readable description of the activity blend for ActivityDescriptionScreen.
  String activityDescription(GoalTargets goals) {
    final thresholds = HealthConfig.thresholdsFor('activity');
    final stepsW = (thresholds['stepsWeight'] as num?)?.toInt() ?? 60;
    final calW = (thresholds['caloriesWeight'] as num?)?.toInt() ?? 25;
    final distW = (thresholds['distanceWeight'] as num?)?.toInt() ?? 15;
    return 'A single 0–100 number for how much you moved today. It blends steps (up to $stepsW pts at ${goals.steps}), '
        'active calories (up to $calW pts at ${goals.calories} kcal), and distance (up to $distW pts at ${goals.distanceKm.toStringAsFixed(1)} km).';
  }

  // ── Advice / VitalNote bridge ───────────────────────────────────────────

  VitalNoteData noteFor(HealthMetric metric) {
    final key = _metricKey(metric);
    final adviceMap = HealthConfig.adviceFor(key);
    final rangesRaw = HealthConfig.rangesFor(key);

    // Fallback to defaults if remote deleted keys — already handled by merge,
    // but guard here so a malformed remote can't produce empty note.
    final title = adviceMap['title'] as String? ?? _fallbackTitle(metric);
    final heading = adviceMap['heading'] as String? ?? 'About $title';
    final intro = adviceMap['intro'] as String? ?? '';
    final didYouKnow = adviceMap['didYouKnow'] as String?;
    final tipsRaw = adviceMap['tips'];
    final tips = <TipData>[];
    if (tipsRaw is List) {
      for (final t in tipsRaw) {
        if (t is Map<String, dynamic>) {
          tips.add(TipData.fromJson(t));
        } else if (t is Map) {
          tips.add(TipData.fromJson(Map<String, dynamic>.from(t)));
        }
      }
    }
    final ranges = <VitalRangeData>[];
    for (final r in rangesRaw) {
      if (r is Map<String, dynamic>) {
        ranges.add(VitalRangeData.fromJson(r));
      } else if (r is Map) {
        ranges.add(VitalRangeData.fromJson(Map<String, dynamic>.from(r)));
      }
    }
    return VitalNoteData(
      title: title,
      heading: heading,
      intro: intro,
      ranges: ranges,
      tips: tips,
      didYouKnow: didYouKnow,
    );
  }

  List<VitalRangeData> rangesFor(HealthMetric m) => noteFor(m).ranges;
  List<TipData> tipsFor(HealthMetric m) => noteFor(m).tips;

  String _metricKey(HealthMetric m) => switch (m) {
        HealthMetric.sleep => 'sleep',
        HealthMetric.heartRate => 'heartRate',
        HealthMetric.spo2 => 'spo2',
        HealthMetric.hrv => 'hrv',
        HealthMetric.stress => 'stress',
        HealthMetric.bloodPressure => 'bloodPressure',
        HealthMetric.temperature => 'temperature',
        HealthMetric.activity => 'activity',
        HealthMetric.steps => 'activity',
      };

  String _fallbackTitle(HealthMetric m) => switch (m) {
        HealthMetric.sleep => 'Sleep',
        HealthMetric.heartRate => 'Heart Rate',
        HealthMetric.spo2 => 'Blood Oxygen',
        HealthMetric.hrv => 'HRV',
        HealthMetric.stress => 'Stress',
        HealthMetric.bloodPressure => 'Blood Pressure',
        HealthMetric.temperature => 'Temperature',
        HealthMetric.activity => 'Activity',
        HealthMetric.steps => 'Activity',
      };
}
