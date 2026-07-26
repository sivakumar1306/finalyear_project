import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'chat_vital_shell.dart';

class StepsChatCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const StepsChatCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final avg = (data['avg'] as num? ?? 0).toInt();
    final unit = data['unit'] as String? ?? 'steps';
    final values = (data['values'] as List? ?? [])
        .map((v) => (v as num).toInt())
        .toList();
    final labels = (data['labels'] as List? ?? [])
        .map((v) => v.toString())
        .toList();
    final maxVal = values.isEmpty
        ? 10000.0
        : (values.reduce((a, b) => a > b ? a : b) * 1.15)
              .clamp(1000, 999999)
              .toDouble();

    return ChatVitalCardShell(
      title: 'STEPS — 7 DAY TREND',
      accent: AppTheme.stepsColor,
      avg: avg,
      min: 0,
      max: 0,
      unit: unit,
      showMinMax: false,
      chart: MiniBarChart(
        values: values,
        labels: labels,
        maxY: maxVal,
        yLines: [maxVal.toInt(), (maxVal / 2).toInt(), 0],
        color: AppTheme.stepsColor,
      ),
    );
  }
}
