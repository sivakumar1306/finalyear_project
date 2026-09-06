import 'package:flutter/material.dart';
import '../services/health_engine/health_engine.dart';
import '../theme/app_theme.dart';

/// AHA/ACC adult BP stage labels from systolic/diastolic mmHg.
/// Stage uses the higher stage when SBP and DBP fall in different bands.
enum BpStage {
  noData,
  normal,
  elevated,
  stage1,
  stage2,
}

extension BpStageLabel on BpStage {
  String get label {
    switch (this) {
      case BpStage.noData:
        return '';
      case BpStage.normal:
        return 'Normal';
      case BpStage.elevated:
        return 'Elevated';
      case BpStage.stage1:
        return 'Stage 1';
      case BpStage.stage2:
        return 'Stage 2';
    }
  }

  String get compactLabel {
    switch (this) {
      case BpStage.noData:
        return 'No data';
      default:
        return label;
    }
  }
}

BpStage classifyBp(int sbp, int dbp) {
  final a = HealthEngine.instance.assessBloodPressure(sbp, dbp);
  return switch (a.label) {
    'Normal' => BpStage.normal,
    'Elevated' => BpStage.elevated,
    'Stage 1' => BpStage.stage1,
    'Stage 2' => BpStage.stage2,
    _ => BpStage.noData,
  };
}

String bpStatusLabel(int sbp, int dbp) => classifyBp(sbp, dbp).label;

String bpCompactStatusLabel(int sbp, int dbp) =>
    classifyBp(sbp, dbp).compactLabel;

Color bpStatusColor(int sbp, int dbp, {Color noDataColor = AppTheme.textSec}) {
  final a = HealthEngine.instance.assessBloodPressure(sbp, dbp);
  if (a.label == 'No data') return noDataColor;
  return a.color;
}
