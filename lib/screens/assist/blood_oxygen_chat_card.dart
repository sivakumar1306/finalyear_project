import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'chat_vital_shell.dart';

class BloodOxygenChatCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback? onTap;
  const BloodOxygenChatCard({super.key, required this.data, this.onTap});

  @override
  Widget build(BuildContext context) {
    final avg = (data['avg'] as num? ?? 0).toInt();
    final min = (data['min'] as num? ?? 0).toInt();
    final max = (data['max'] as num? ?? 0).toInt();
    final unit = data['unit'] as String? ?? '%';
    final values = (data['values'] as List? ?? [])
        .map((v) => (v as num).toInt())
        .toList();
    final labels = (data['labels'] as List? ?? [])
        .map((v) => v.toString())
        .toList();

    return ChatVitalCardShell(
      title: 'BLOOD OXYGEN — 7 DAY TREND',
      accent: AppTheme.spo2Color,
      avg: avg,
      min: min,
      max: max,
      unit: unit,
      chart: MiniBarChart(
        values: values,
        labels: labels,
        maxY: 100,
        baseline: 85,
        yLines: const [100, 97, 94, 85],
        color: AppTheme.spo2Color,
      ),
      onTap: onTap,
    );
  }
}
