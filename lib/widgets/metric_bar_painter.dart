import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Bar chart painter for a single metric series: horizontal grid lines at
/// [yLines], then one rounded bar per value. Bars are uniformly colored with
/// [barColor] or per-value via [colorFor] (which takes priority). Values are
/// normalized between [baseline] and [maxY].
class MetricBarPainter extends CustomPainter {
  const MetricBarPainter({
    required this.values,
    required this.maxY,
    required this.yLines,
    this.baseline = 0,
    this.barColor,
    this.colorFor,
  });

  final List<num> values;
  final double maxY;
  final List<int> yLines;
  final double baseline;
  final Color? barColor;
  final Color Function(num value)? colorFor;

  @override
  void paint(Canvas canvas, Size size) {
    final range = (maxY - baseline).clamp(1.0, double.infinity).toDouble();
    final gridPaint = Paint()
      ..color = AppTheme.grid
      ..strokeWidth = 0.5;
    for (final y in yLines) {
      final yPos = size.height - ((y - baseline) / range) * size.height;
      canvas.drawLine(Offset(0, yPos), Offset(size.width, yPos), gridPaint);
    }

    if (values.isEmpty) return;
    final n = values.length;
    final slotW = size.width / n;
    // Bar width: narrower for many values, wider for 7-day (few values)
    final barW = (slotW * 0.55).clamp(2.0, 9.0).toDouble();

    for (int i = 0; i < n; i++) {
      final v = values[i];
      if (v <= 0) continue;
      final normalized = ((v - baseline) / range).clamp(0.0, 1.0).toDouble();
      final barH = (normalized * size.height).clamp(2.0, size.height).toDouble();
      final x = i * slotW + (slotW - barW) / 2;
      canvas.drawRRect(
        RRect.fromLTRBR(
          x,
          size.height - barH,
          x + barW,
          size.height,
          const Radius.circular(3),
        ),
        Paint()..color = colorFor != null ? colorFor!(v) : barColor ?? AppTheme.gold,
      );
    }
  }

  @override
  bool shouldRepaint(MetricBarPainter old) =>
      old.values != values ||
      old.maxY != maxY ||
      old.baseline != baseline ||
      old.yLines != yLines ||
      old.barColor != barColor ||
      old.colorFor != colorFor;
}