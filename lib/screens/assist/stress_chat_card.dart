import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_typography.dart';
import 'chat_vital_shell.dart';

class StressChatCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback? onTap;
  const StressChatCard({super.key, required this.data, this.onTap});

  static Color _barColor(int v) {
    if (v < 40) return AppTheme.success;
    if (v < 60) return AppTheme.amber;
    if (v < 80) return AppTheme.stressColor;
    return AppTheme.danger;
  }

  @override
  Widget build(BuildContext context) {
    final avg = (data['avg'] as num? ?? 0).toInt();
    final min = (data['min'] as num? ?? 0).toInt();
    final max = (data['max'] as num? ?? 0).toInt();
    final unit = data['unit'] as String? ?? '';
    final values = (data['values'] as List? ?? [])
        .map((v) => (v as num).toInt())
        .toList();
    final labels = (data['labels'] as List? ?? [])
        .map((v) => v.toString())
        .toList();

    return ChatVitalCardShell(
      title: 'LAST 7 DAYS TREND',
      accent: AppTheme.stressColor,
      avg: avg,
      min: min,
      max: max,
      unit: unit,
      chart: Column(
        children: [
          Expanded(
            child: _ColoredMiniBarChart(
              values: values,
              labels: labels,
              maxY: 100,
              yLines: const [100, 75, 50, 25],
              colorMapper: _barColor,
            ),
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _LegendDot(color: AppTheme.success, label: 'Relaxed'),
              _LegendDot(color: AppTheme.amber, label: 'Normal'),
              _LegendDot(color: AppTheme.stressColor, label: 'Elevated'),
              _LegendDot(color: AppTheme.danger, label: 'High'),
            ],
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _ColoredMiniBarChart extends StatelessWidget {
  final List<int> values;
  final List<String> labels;
  final double maxY;
  final List<int> yLines;
  final Color Function(int) colorMapper;

  const _ColoredMiniBarChart({
    required this.values,
    required this.labels,
    required this.maxY,
    required this.yLines,
    required this.colorMapper,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: CustomPaint(
            painter: _ColoredMiniBarPainter(
              values: values,
              maxY: maxY,
              yLines: yLines,
              colorMapper: colorMapper,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: labels
              .map(
                (l) => Text(
                  l,
                  style: AppTypography.inter(
                    fontSize: 9,
                    color: AppTheme.white40,
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _ColoredMiniBarPainter extends CustomPainter {
  final List<int> values;
  final double maxY;
  final List<int> yLines;
  final Color Function(int) colorMapper;

  const _ColoredMiniBarPainter({
    required this.values,
    required this.maxY,
    required this.yLines,
    required this.colorMapper,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppTheme.white04
      ..strokeWidth = 0.5;
    for (final y in yLines) {
      final yPos = size.height - (y / maxY) * size.height;
      canvas.drawLine(Offset(0, yPos), Offset(size.width, yPos), gridPaint);
    }
    if (values.isEmpty) return;
    final n = values.length;
    final slotW = size.width / n;
    final barW = (slotW * 0.55).clamp(4.0, 12.0);

    for (int i = 0; i < n; i++) {
      if (values[i] <= 0) continue;
      final ratio = (values[i] / maxY).clamp(0.0, 1.0);
      final barH = (ratio * size.height).clamp(2.0, size.height);
      final x = i * slotW + (slotW - barW) / 2;
      canvas.drawRRect(
        RRect.fromLTRBR(
          x,
          size.height - barH,
          x + barW,
          size.height,
          const Radius.circular(3),
        ),
        Paint()..color = colorMapper(values[i]).withValues(alpha: 0.88),
      );
    }
  }

  @override
  bool shouldRepaint(_ColoredMiniBarPainter old) => old.values != values;
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(
        label,
        style: AppTypography.inter(
          fontSize: 9,
          color: AppTheme.white60,
        ),
      ),
    ],
  );
}
