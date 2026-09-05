import 'package:flutter/material.dart';

/// Which vital/metric the engine is asked about. Used for `noteFor()`,
/// `rangesFor()` and generic `assess()` dispatch.
enum HealthMetric {
  sleep,
  heartRate,
  spo2,
  hrv,
  stress,
  bloodPressure,
  temperature,
  activity,
  steps,
}

/// Severity bucket for theming / insights. Independent of label wording.
enum HealthSeverity { unknown, normal, borderline, atRisk, excellent }

/// Result of a single threshold classification.
class HealthAssessment {
  final String label;
  final Color color;
  final HealthSeverity severity;

  const HealthAssessment({
    required this.label,
    required this.color,
    required this.severity,
  });
}

/// One band in a VitalNote range bar.
class VitalRangeData {
  final String label;
  final String range;
  final String colorKey; // e.g. "success", "danger", "sleepColor"
  const VitalRangeData({
    required this.label,
    required this.range,
    required this.colorKey,
  });

  Map<String, dynamic> toJson() =>
      {'label': label, 'range': range, 'color': colorKey};
  factory VitalRangeData.fromJson(Map<String, dynamic> j) => VitalRangeData(
        label: j['label'] as String? ?? '',
        range: j['range'] as String? ?? '',
        colorKey: j['color'] as String? ?? 'textSec',
      );
}

/// One tip card in a VitalNote screen.
class TipData {
  final String icon; // e.g. "bedtime_rounded"
  final String colorKey;
  final String title;
  final String tip;
  const TipData({
    required this.icon,
    required this.colorKey,
    required this.title,
    required this.tip,
  });

  Map<String, dynamic> toJson() =>
      {'icon': icon, 'color': colorKey, 'title': title, 'tip': tip};
  factory TipData.fromJson(Map<String, dynamic> j) => TipData(
        icon: j['icon'] as String? ?? 'info_outline_rounded',
        colorKey: j['color'] as String? ?? 'gold',
        title: j['title'] as String? ?? '',
        tip: j['tip'] as String? ?? '',
      );
}

/// Full VitalNote payload — what used to be hard-coded `VitalNoteScreen(...)` args.
class VitalNoteData {
  final String title;
  final String heading;
  final String intro;
  final List<VitalRangeData> ranges;
  final List<TipData> tips;
  final String? didYouKnow;
  const VitalNoteData({
    required this.title,
    required this.heading,
    required this.intro,
    required this.ranges,
    required this.tips,
    this.didYouKnow,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'heading': heading,
        'intro': intro,
        'didYouKnow': didYouKnow,
        'ranges': ranges.map((r) => r.toJson()).toList(),
        'tips': tips.map((t) => t.toJson()).toList(),
      };
}
