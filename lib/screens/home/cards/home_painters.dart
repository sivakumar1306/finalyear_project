import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import 'home_card_shared.dart';
/// Heart Rate area chart — faint 7% fill under a 0.7-white curve with an
/// end-point dot (Frame 478: Rectangle 1 + Line 15 + Ellipse 6).
class AreaChartPainter extends CustomPainter {
  final List<double> data;
  const AreaChartPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2 || size.width <= 0 || size.height <= 0) return;
    const pad = 6.0;
    final step = size.width / (data.length - 1);
    final ys = <double>[];
    final path = Path();
    for (int i = 0; i < data.length; i++) {
      final x = i * step;
      final y = pad + (1 - data[i]) * (size.height - pad * 2);
      ys.add(y);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        final px = (i - 1) * step;
        final py = ys[i - 1];
        final cpx = (px + x) / 2;
        path.cubicTo(cpx, py, cpx, y, x, y);
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()..color = Colors.white.withValues(alpha: 0.07),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(size.width, ys.last),
      2,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(AreaChartPainter old) => old.data != data;
}

/// Blood Pressure chart — systolic (0.7-white) and diastolic (0.35-white)
/// lines over a common 70–140 mmHg scale, with an end-point dot.
class BpChartPainter extends CustomPainter {
  final int sbp;
  final int dbp;
  const BpChartPainter({required this.sbp, required this.dbp});

  static const _sysPattern = [
    114.0,
    119.0,
    122.0,
    118.0,
    125.0,
    129.0,
    126.0,
    121.0,
    128.0,
    132.0,
    128.0,
    125.0,
    124.0,
  ];
  static const _diaPattern = [
    76.0,
    78.0,
    79.0,
    77.0,
    81.0,
    83.0,
    80.0,
    78.0,
    82.0,
    85.0,
    82.0,
    80.0,
    79.0,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final sysScale = sbp > 0 ? sbp / 128.0 : 1.0;
    final diaScale = dbp > 0 ? dbp / 82.0 : 1.0;
    Path line(List<double> pattern, double scale) {
      final p = Path();
      final step = size.width / (pattern.length - 1);
      for (int i = 0; i < pattern.length; i++) {
        final x = i * step;
        final v = pattern[i] * scale;
        final y = size.height * (1 - (v - 70) / 70);
        if (i == 0) {
          p.moveTo(x, y);
        } else {
          final px = (i - 1) * step;
          final py = size.height * (1 - (pattern[i - 1] * scale - 70) / 70);
          final cpx = (px + x) / 2;
          p.cubicTo(cpx, py, cpx, y, x, y);
        }
      }
      return p;
    }

    final sys = line(_sysPattern, sysScale);
    final dia = line(_diaPattern, diaScale);
    canvas.drawPath(
      dia,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      sys,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    final last = size.height * (1 - (_sysPattern.last * sysScale - 70) / 70);
    canvas.drawCircle(
      Offset(size.width, last),
      2,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(BpChartPainter old) => old.sbp != sbp || old.dbp != dbp;
}

/// Stress mini-bar chart — 6px bars, 2px gap, rounded 2px: low = soft green,
/// mid = 80% white, high = soft rose (Frame 481 colours).
class StressMiniBarsPainter extends CustomPainter {
  final List<double> data;
  const StressMiniBarsPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || size.width <= 0 || size.height <= 0) return;
    const barW = 6.0;
    final maxH = size.height * 0.67;
    final pitch = size.width / data.length;
    for (int i = 0; i < data.length; i++) {
      final x = i * pitch + (pitch - barW) / 2;
      final h = (data[i] * maxH).clamp(2.0, maxH);
      final y = size.height - h;
      final Color barColor;
      if (data[i] < 0.4) {
        barColor = kFigmaStressLow;
      } else if (data[i] < 0.65) {
        barColor = Colors.white.withValues(alpha: 0.8);
      } else {
        barColor = kFigmaStressHigh;
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barW, h),
          const Radius.circular(2),
        ),
        Paint()..color = barColor,
      );
    }
  }

  @override
  bool shouldRepaint(StressMiniBarsPainter old) => old.data != data;
}

class SparkPainter extends CustomPainter {
  final Color color;
  final List<double> data;
  const SparkPainter(this.color, this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final step = size.width / (data.length - 1);
    final path = Path();

    for (int i = 0; i < data.length; i++) {
      final x = i * step;
      final y = size.height - data[i] * size.height * 0.9;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        final px = (i - 1) * step;
        final py = size.height - data[i - 1] * size.height * 0.9;
        final cpx = (px + x) / 2;
        path.cubicTo(cpx, py, cpx, y, x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.7)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(SparkPainter old) =>
      old.color != color || old.data != data;
}

class BarChartPainter extends CustomPainter {
  final Color color;
  final List<double> data;
  const BarChartPainter(this.color, this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final slotW = size.width / data.length;
    final barW = slotW * 0.55; // thinner bars, more breathing room between them
    final xOffset = (slotW - barW) / 2;

    for (int i = 0; i < data.length; i++) {
      final x = i * slotW + xOffset;
      final h = data[i] * size.height;
      final y = size.height - h;

      // Color ramp: low = green orb, mid = yellow, high = red
      final Color barColor;
      if (data[i] < 0.4) {
        barColor = AppTheme.stressColor;
      } else if (data[i] < 0.65) {
        barColor = AppTheme.amber;
      } else {
        barColor = AppTheme.hrColor;
      }

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barW, h),
          Radius.circular((barW / 2).clamp(0, 4)),
        ),
        Paint()..color = barColor.withValues(alpha: 0.75),
      );
    }
  }

  @override
  bool shouldRepaint(BarChartPainter old) =>
      old.color != color || old.data != data;
}
