import 'package:flutter/material.dart';
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
  if (sbp <= 0 || dbp <= 0) return BpStage.noData;
  if (sbp < 120 && dbp < 80) return BpStage.normal;
  if (sbp < 130 && dbp < 80) return BpStage.elevated;
  if (sbp < 140 && dbp < 90) return BpStage.stage1;
  return BpStage.stage2;
}

String bpStatusLabel(int sbp, int dbp) => classifyBp(sbp, dbp).label;

String bpCompactStatusLabel(int sbp, int dbp) =>
    classifyBp(sbp, dbp).compactLabel;

Color bpStatusColor(int sbp, int dbp, {Color noDataColor = const Color(0xFF888888)}) {
  switch (classifyBp(sbp, dbp)) {
    case BpStage.noData:
      return noDataColor;
    case BpStage.normal:
      return AppTheme.success;
    case BpStage.elevated:
      return const Color(0xFFFBBF24);
    case BpStage.stage1:
      return AppTheme.stressColor;
    case BpStage.stage2:
      return AppTheme.danger;
  }
}
