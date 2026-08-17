import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'chat_vital_shell.dart';

// DBP uses the same contrasting violet as blood_pressure_screen.dart so both
// series stay visually consistent between the full screen and the chat card.

class BloodPressureChatCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback? onTap;
  const BloodPressureChatCard({super.key, required this.data, this.onTap});

  @override
  Widget build(BuildContext context) {
    final sbpAvg = (data['sbp_avg'] as num? ?? 0).toInt();
    final sbpValues = (data['sbp_values'] as List? ?? [])
        .map((v) => (v as num).toInt())
        .toList();
    final dbpValues = (data['dbp_values'] as List? ?? [])
        .map((v) => (v as num).toInt())
        .toList();
    final labels = (data['labels'] as List? ?? [])
        .map((v) => v.toString())
        .toList();

    return ChatVitalCardShell(
      title: 'BLOOD PRESSURE — 7 DAY TREND',
      accent: AppTheme.bpColor,
      avg: sbpAvg,
      min: 0,
      max: 0,
      unit: 'mmHg',
      showMinMax: false,
      chart: DualMiniBarChart(
        sbpValues: sbpValues,
        dbpValues: dbpValues,
        labels: labels,
        maxY: 160,
        yLines: const [160, 120, 80, 40],
        sbpColor: AppTheme.bpColor,
        dbpColor: AppTheme.softViolet,
      ),
      onTap: onTap,
    );
  }
}
