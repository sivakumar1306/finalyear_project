import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'chat_vital_shell.dart';

class HrvChatCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const HrvChatCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final avg = (data['avg'] as num? ?? 0).toInt();
    final min = (data['min'] as num? ?? 0).toInt();
    final max = (data['max'] as num? ?? 0).toInt();
    final unit = data['unit'] as String? ?? 'ms';
    final values = (data['values'] as List? ?? [])
        .map((v) => (v as num).toInt())
        .toList();
    final labels = (data['labels'] as List? ?? [])
        .map((v) => v.toString())
        .toList();

    return ChatVitalCardShell(
      title: 'HRV — 7 DAY TREND',
      accent: AppTheme.hrvColor,
      avg: avg,
      min: min,
      max: max,
      unit: unit,
      chart: MiniBarChart(
        values: values,
        labels: labels,
        maxY: 100,
        yLines: const [100, 80, 60, 40, 20],
        color: AppTheme.hrvColor,
      ),
    );
  }
}
