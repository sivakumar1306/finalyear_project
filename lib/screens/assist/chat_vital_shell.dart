import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../../widgets/app_typography.dart';

/// Shared glass-card shell for single-metric vital cards shown in chat
/// (heart rate, SpO2, HRV, steps). Matches the Figma sleep-highlights style.
/// Responsive: max 335 wide, stat chips scale down so long values never
/// overflow narrow screens. Tappable via [onTap] (ripple under the glass).
class ChatVitalCardShell extends StatelessWidget {
  final String title;
  final Color accent;
  final int avg, min, max;
  final String unit;
  final Widget chart;
  final bool showMinMax;
  final VoidCallback? onTap;

  const ChatVitalCardShell({
    super.key,
    required this.title,
    required this.accent,
    required this.avg,
    required this.min,
    required this.max,
    required this.unit,
    required this.chart,
    this.showMinMax = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 335),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    color: const Color(0x0AFFFFFF),
                    border: Border.all(color: const Color(0x14FFFFFF), width: 0.5),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTypography.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.14 * 10,
                          color: const Color(0x6BFFFFFF),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(height: 0.5, color: const Color(0x0AFFFFFF)),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: statChip('AVG', avg > 0 ? '$avg' : '--', unit, accent),
                            ),
                          ),
                          if (showMinMax) ...[
                            const SizedBox(width: 10),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: statChip(
                                  'MIN',
                                  min > 0 ? '$min' : '--',
                                  unit,
                                  const Color(0x99FFFFFF),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: statChip(
                                  'MAX',
                                  max > 0 ? '$max' : '--',
                                  unit,
                                  const Color(0x99FFFFFF),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(height: 80, child: chart),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget statChip(String label, String value, String unit, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.inter(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: const Color(0x66FFFFFF),
          ),
        ),
        const SizedBox(height: 4),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: AppTypography.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              TextSpan(
                text: ' $unit',
                style: AppTypography.inter(
                  fontSize: 10,
                  color: const Color(0x66FFFFFF),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Single-series mini bar chart, reused across HR / SpO2 / HRV / Steps cards.
/// Drawing logic mirrors each full screen's *BarPainter (same bar-width
/// clamping, same grid-line approach) — scaled down for the chat card.
class MiniBarChart extends StatelessWidget {
  final List<int> values;
  final List<String> labels;
  final double maxY;
  final List<int> yLines;
  final Color color;
  final double baseline;

  const MiniBarChart({
    super.key,
    required this.values,
    required this.labels,
    required this.maxY,
    required this.yLines,
    required this.color,
    this.baseline = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: CustomPaint(
            painter: MiniBarPainter(
              values: values,
              maxY: maxY,
              yLines: yLines,
              color: color,
              baseline: baseline,
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

class MiniBarPainter extends CustomPainter {
  final List<int> values;
  final double maxY;
  final List<int> yLines;
  final Color color;
  final double baseline;

  const MiniBarPainter({
    required this.values,
    required this.maxY,
    required this.yLines,
    required this.color,
    this.baseline = 0,
  });

  double get _range => maxY - baseline;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0x0AFFFFFF)
      ..strokeWidth = 0.5;
    for (final y in yLines) {
      final yPos = size.height - ((y - baseline) / _range) * size.height;
      canvas.drawLine(Offset(0, yPos), Offset(size.width, yPos), gridPaint);
    }
    if (values.isEmpty) return;
    final n = values.length;
    final slotW = size.width / n;
    final barW = (slotW * 0.5).clamp(4.0, 22.0);
    final barPaint = Paint()..color = color.withValues(alpha: 0.88);
    for (int i = 0; i < n; i++) {
      if (values[i] <= 0) continue;
      final ratio = ((values[i] - baseline) / _range).clamp(0.0, 1.0);
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
        barPaint,
      );
    }
  }

  @override
  bool shouldRepaint(MiniBarPainter old) =>
      old.values != values || old.color != color || old.maxY != maxY;
}

/// Dual-series mini bar chart for Blood Pressure (systolic + diastolic side by
/// side per slot) — mirrors _BPBarPainter's paired-bar layout, scaled down.
class DualMiniBarChart extends StatelessWidget {
  final List<int> sbpValues;
  final List<int> dbpValues;
  final List<String> labels;
  final double maxY;
  final List<int> yLines;
  final Color sbpColor;
  final Color dbpColor;

  const DualMiniBarChart({
    super.key,
    required this.sbpValues,
    required this.dbpValues,
    required this.labels,
    required this.maxY,
    required this.yLines,
    required this.sbpColor,
    required this.dbpColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: CustomPaint(
            painter: DualMiniBarPainter(
              sbpValues: sbpValues,
              dbpValues: dbpValues,
              maxY: maxY,
              yLines: yLines,
              sbpColor: sbpColor,
              dbpColor: dbpColor,
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

class DualMiniBarPainter extends CustomPainter {
  final List<int> sbpValues;
  final List<int> dbpValues;
  final double maxY;
  final List<int> yLines;
  final Color sbpColor;
  final Color dbpColor;

  const DualMiniBarPainter({
    required this.sbpValues,
    required this.dbpValues,
    required this.maxY,
    required this.yLines,
    required this.sbpColor,
    required this.dbpColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0x0AFFFFFF)
      ..strokeWidth = 0.5;
    for (final y in yLines) {
      final yPos = size.height - (y / maxY) * size.height;
      canvas.drawLine(Offset(0, yPos), Offset(size.width, yPos), gridPaint);
    }

    final n = sbpValues.length;
    if (n == 0) return;
    final slotW = size.width / n;
    final barW = (slotW * 0.28).clamp(3.0, 9.0);
    final sbpPaint = Paint()..color = sbpColor.withValues(alpha: 0.88);
    final dbpPaint = Paint()..color = dbpColor.withValues(alpha: 0.88);

    for (int i = 0; i < n; i++) {
      final cx = i * slotW + slotW / 2;

      final sbp = sbpValues[i];
      if (sbp > 0) {
        final ratio = (sbp / maxY).clamp(0.0, 1.0);
        final barH = (ratio * size.height).clamp(2.0, size.height);
        canvas.drawRRect(
          RRect.fromLTRBR(
            cx - barW - 1,
            size.height - barH,
            cx - 1,
            size.height,
            const Radius.circular(2),
          ),
          sbpPaint,
        );
      }

      final dbp = i < dbpValues.length ? dbpValues[i] : 0;
      if (dbp > 0) {
        final ratio = (dbp / maxY).clamp(0.0, 1.0);
        final barH = (ratio * size.height).clamp(2.0, size.height);
        canvas.drawRRect(
          RRect.fromLTRBR(
            cx + 1,
            size.height - barH,
            cx + barW + 1,
            size.height,
            const Radius.circular(2),
          ),
          dbpPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(DualMiniBarPainter old) =>
      old.sbpValues != sbpValues || old.dbpValues != dbpValues;
}
