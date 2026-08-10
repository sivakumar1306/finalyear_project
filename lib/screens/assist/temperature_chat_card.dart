import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_typography.dart';
import 'chat_vital_shell.dart';

class TemperatureChatCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback? onTap;
  const TemperatureChatCard({super.key, required this.data, this.onTap});

  static Color _tempBarColor(double v) {
    if (v < 36.0) return AppTheme.spo2Color;
    if (v <= 37.2) return AppTheme.success;
    if (v <= 38.0) return const Color(0xFFFBBF24);
    return AppTheme.danger;
  }

  @override
  Widget build(BuildContext context) {
    final avg = (data['avg'] as num? ?? 0).toInt();
    final min = (data['min'] as num? ?? 0).toInt();
    final max = (data['max'] as num? ?? 0).toInt();
    final unit = data['unit'] as String? ?? '°C';
    final values = (data['values'] as List? ?? [])
        .map((v) => (v as num).toDouble())
        .toList();
    final labels = (data['labels'] as List? ?? [])
        .map((v) => v.toString())
        .toList();

    return ChatVitalCardShell(
      title: 'LAST 7 DAYS TREND',
      accent: AppTheme.tempColor,
      avg: avg,
      min: min,
      max: max,
      unit: unit,
      chart: Column(
        children: [
          Expanded(
            child: _TempMiniBarChart(
              values: values,
              labels: labels,
              minY: 34,
              maxY: 40,
              yLines: const [40, 38, 36, 34],
              colorMapper: _tempBarColor,
            ),
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _LegendDot(color: AppTheme.spo2Color, label: 'Low'),
              _LegendDot(color: AppTheme.success, label: 'Normal'),
              _LegendDot(color: Color(0xFFFBBF24), label: 'Elevated'),
              _LegendDot(color: AppTheme.danger, label: 'Fever'),
            ],
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _TempMiniBarChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final double minY;
  final double maxY;
  final List<int> yLines;
  final Color Function(double) colorMapper;

  const _TempMiniBarChart({
    required this.values,
    required this.labels,
    required this.minY,
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
            painter: _TempMiniBarPainter(
              values: values,
              minY: minY,
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
                    color: const Color(0x66FFFFFF),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _TempMiniBarPainter extends CustomPainter {
  final List<double> values;
  final double minY;
  final double maxY;
  final List<int> yLines;
  final Color Function(double) colorMapper;

  const _TempMiniBarPainter({
    required this.values,
    required this.minY,
    required this.maxY,
    required this.yLines,
    required this.colorMapper,
  });

  double get _range => maxY - minY;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0x0AFFFFFF)
      ..strokeWidth = 0.5;
    for (final y in yLines) {
      final yPos = size.height - ((y - minY) / _range) * size.height;
      canvas.drawLine(Offset(0, yPos), Offset(size.width, yPos), gridPaint);
    }
    if (values.isEmpty) return;
    final n = values.length;
    final slotW = size.width / n;
    final barW = (slotW * 0.55).clamp(4.0, 12.0);

    for (int i = 0; i < n; i++) {
      if (values[i] <= 0) continue;
      final ratio = ((values[i] - minY) / _range).clamp(0.0, 1.0);
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
  bool shouldRepaint(_TempMiniBarPainter old) => old.values != values;
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
          color: const Color(0x99FFFFFF),
        ),
      ),
    ],
  );
}
