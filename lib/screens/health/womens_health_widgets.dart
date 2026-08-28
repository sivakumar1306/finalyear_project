import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/womens_health_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_typography.dart';



TextStyle _inter(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = Colors.white,
  double? letterSpacing,
  double? height,
}) => AppTypography.inter(
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: letterSpacing,
  height: height,
);

const _kMonthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _fmtMD(DateTime d) => '${_kMonthsShort[d.month - 1]} ${d.day}';

// ── Calendar cell model ────────────────────────────────────────────────────────

class CalCell {
  final DateTime date;
  final bool inMonth;
  final bool isPeriod;
  final bool isFertile;
  final bool isOvulation;
  final bool isToday;

  const CalCell({
    required this.date,
    required this.inMonth,
    required this.isPeriod,
    required this.isFertile,
    required this.isOvulation,
    required this.isToday,
  });
}

// ── Cycle dial painter ────────────────────────────────────────────────────────

class CycleDialPainter extends CustomPainter {
  final int currentDay;
  final int cycleLength;
  final int periodLength;
  final int fertileStart; // 1-based day
  final int fertileEnd;   // 1-based day

  // 220° horseshoe arch — endpoints tuck ~20° below horizontal.
  static const _totalArcDeg = 220.0;
  static const _totalArcRad = _totalArcDeg * math.pi / 180.0;

  const CycleDialPainter({
    required this.currentDay,
    required this.cycleLength,
    required this.periodLength,
    required this.fertileStart,
    required this.fertileEnd,
  });

  // Center Y at 75% of canvas height so the lower arc tips are visible.
  Offset _center(Size s) => Offset(s.width / 2, s.height * 0.75);
  double _radius(Size s) => s.width / 2 - 22;

  // Arc begins 110° counter-clockwise from the top (12-o'clock = –π/2).
  double get _arcStart => -math.pi / 2 - _totalArcRad / 2;

  // Map a 0-based day index to its angle on the arc.
  double _dayAngle(int dayIdx) {
    final t = dayIdx.clamp(0, cycleLength - 1) / (cycleLength - 1);
    return _arcStart + t * _totalArcRad;
  }

  // Check if a day falls inside a coloured segment.
  bool _inSegment(int day) {
    if (day >= 0 && day < periodLength) return true;
    if (day >= fertileStart - 1 && day <= fertileEnd - 1) return true;
    return false;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = _center(size);
    final radius = _radius(size);
    final rect = Rect.fromCircle(center: center, radius: radius);

    // ── 1. Small dots along the track (skip where segments will draw) ──────
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < cycleLength; i++) {
      if (_inSegment(i)) continue; // segment will cover this position
      final a = _dayAngle(i);
      canvas.drawCircle(
        Offset(center.dx + radius * math.cos(a),
               center.dy + radius * math.sin(a)),
        1.8,
        dotPaint,
      );
    }

    // ── 2. Period segment (red) ─────────────────────────────────────────────
    _drawSegment(canvas, rect, 0, periodLength - 1, AppTheme.danger, 12);

    // ── 3. Fertile segment (teal) ───────────────────────────────────────────
    _drawSegment(canvas, rect, fertileStart - 1, fertileEnd - 1, AppTheme.hrvColor, 12);

    // ── 4. Blood-drop decoration below the period segment end ───────────────
    final dropDayIdx = (periodLength - 1).clamp(0, cycleLength - 1);
    final dropAngle = _dayAngle(dropDayIdx);
    // Position it just outside the arc, shifted outward from center.
    final dropDist = radius + 16;
    final dropCenter = Offset(
      center.dx + dropDist * math.cos(dropAngle),
      center.dy + dropDist * math.sin(dropAngle),
    );
    _paintBloodDrop(canvas, dropCenter, 4);

    // ── 5. Current-day indicator (clean white dot) ──────────────────────────
    final dayA = _dayAngle(currentDay - 1);
    final dayPos = Offset(
      center.dx + radius * math.cos(dayA),
      center.dy + radius * math.sin(dayA),
    );
    // Soft glow
    canvas.drawCircle(dayPos, 8,
        Paint()..color = Colors.white.withValues(alpha: 0.08));
    // White dot
    canvas.drawCircle(dayPos, 4.5, Paint()..color = Colors.white);
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  void _drawSegment(Canvas canvas, Rect rect,
      int startIdx, int endIdx, Color color, double strokeW) {
    if (startIdx >= cycleLength || endIdx < 0) return;
    startIdx = startIdx.clamp(0, cycleLength - 1);
    endIdx   = endIdx.clamp(0, cycleLength - 1);

    final segStart = _dayAngle(startIdx);
    final segEnd   = _dayAngle(endIdx);

    canvas.drawArc(
      rect,
      segStart,
      segEnd - segStart,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintBloodDrop(Canvas canvas, Offset pos, double r) {
    final path = Path()
      ..moveTo(pos.dx, pos.dy + r * 1.5)              // tip (pointing down)
      ..quadraticBezierTo(
          pos.dx - r, pos.dy, pos.dx, pos.dy - r * 0.8) // left curve up
      ..quadraticBezierTo(
          pos.dx + r, pos.dy, pos.dx, pos.dy + r * 1.5); // right curve down
    canvas.drawPath(path, Paint()..color = AppTheme.danger);
  }

  @override
  bool shouldRepaint(CycleDialPainter old) =>
      old.currentDay != currentDay ||
      old.cycleLength != cycleLength ||
      old.periodLength != periodLength ||
      old.fertileStart != fertileStart ||
      old.fertileEnd != fertileEnd;
}

// ── Prediction column ──────────────────────────────────────────────────────────

class PredictionCol extends StatelessWidget {
  final String label;
  final String value;
  final String valueSuffix;
  final String subtitle;

  const PredictionCol({
    super.key,
    required this.label,
    required this.value,
    this.valueSuffix = '',
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: _inter(10.5,
              weight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.45)),
        ),
        const SizedBox(height: 6),
        RichText(
          text: TextSpan(children: [
            TextSpan(
                text: value,
                style: _inter(20, weight: FontWeight.w600, color: Colors.white)),
            if (valueSuffix.isNotEmpty)
              TextSpan(
                  text: valueSuffix,
                  style: _inter(12, color: Colors.white.withValues(alpha: 0.6))),
          ]),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: _inter(11, color: Colors.white.withValues(alpha: 0.4)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ── Cycle pattern row ──────────────────────────────────────────────────────────

class CyclePatternRow extends StatelessWidget {
  final int index;
  final CycleData cycle;
  const CyclePatternRow({super.key, required this.index, required this.cycle});

  @override
  Widget build(BuildContext context) {
    final rangeEnd = cycle.periodStart.add(Duration(days: cycle.cycleLength - 1));
    final rangeLabel = '${_fmtMD(cycle.periodStart)} – ${_fmtMD(rangeEnd)}';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 74,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cycle $index',
                  style: _inter(13, weight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('${cycle.cycleLength} days',
                  style: _inter(11, color: AppTheme.textSec)),
            ],
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 22,
            child: CyclePatternTrack(cycle: cycle),
          ),
        ),
        const SizedBox(width: 10),
        Text(rangeLabel, style: _inter(11, color: AppTheme.textSec)),
      ],
    );
  }
}

class CyclePatternTrack extends StatelessWidget {
  final CycleData cycle;
  const CyclePatternTrack({super.key, required this.cycle});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 22),
      painter: CyclePatternDotsPainter(cycle: cycle),
    );
  }
}

class CyclePatternDotsPainter extends CustomPainter {
  final CycleData cycle;
  const CyclePatternDotsPainter({required this.cycle});

  @override
  void paint(Canvas canvas, Size size) {
    final dotCount = cycle.cycleLength;
    if (dotCount <= 0) return;
    
    final slotWidth = size.width / dotCount;
    
    final int periodLen = cycle.periodLength;
    final int ovuDiff = cycle.ovulationDate.difference(cycle.periodStart).inDays + 1;
    final fertStartDiff = cycle.fertileStart.difference(cycle.periodStart).inDays + 1;
    final fertEndDiff = cycle.fertileEnd.difference(cycle.periodStart).inDays + 1;

    // Use App Theme Colors
    final cPeriod = AppTheme.womenColor.withValues(alpha: 0.75); // Pinkish bar
    final cFollicular = AppTheme.hrvColor.withValues(alpha: 0.8); // Teal
    final cLuteal = AppTheme.sleepColor.withValues(alpha: 0.7); // Purple
    final cOvu = AppTheme.spo2Color; // Blue ring

    // Draw Period Capsule
    if (periodLen > 0) {
      final periodW = (periodLen * slotWidth) - (slotWidth * 0.3);
      final rrect = RRect.fromLTRBR(0, size.height / 2 - 4.5, periodW.clamp(0.0, size.width), size.height / 2 + 4.5, const Radius.circular(5));
      canvas.drawRRect(rrect, Paint()..color = cPeriod);
    }

    // Draw rest of the days
    for (int i = 0; i < dotCount; i++) {
      final day = i + 1;
      final cx = (i * slotWidth) + (slotWidth / 2);
      final cy = size.height / 2;

      if (day <= periodLen) {
        continue; // Handled by the continuous capsule
      }
      
      if (day == ovuDiff) {
        // Blue ovulation ring overlapping the day dot
        canvas.drawCircle(
          Offset(cx, cy),
          2.5,
          Paint()..color = cLuteal,
        );
        canvas.drawCircle(
          Offset(cx, cy),
          6.5,
          Paint()
            ..color = cOvu
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
        );
      } else if (day >= fertStartDiff && day <= fertEndDiff) {
        // Follicular / Fertile window
        canvas.drawCircle(
          Offset(cx, cy),
          2.5,
          Paint()..color = cFollicular,
        );
      } else {
        // Luteal
        canvas.drawCircle(
          Offset(cx, cy),
          2.5,
          Paint()..color = cLuteal,
        );
      }
    }
  }

  @override
  bool shouldRepaint(CyclePatternDotsPainter old) => old.cycle != cycle;
}

class TempGaugePainter extends CustomPainter {
  final double delta;
  const TempGaugePainter({required this.delta});

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    
    // Draw baseline
    canvas.drawLine(
      Offset(0, midY),
      Offset(size.width, midY),
      Paint()..color = Colors.white.withValues(alpha: 0.2)..strokeWidth = 2,
    );

    // Draw baseline tick
    canvas.drawLine(
      Offset(size.width / 2, midY - 6),
      Offset(size.width / 2, midY + 6),
      Paint()..color = Colors.white.withValues(alpha: 0.5)..strokeWidth = 2,
    );

    // Calculate dot x position
    // Range is -1.0 to +1.0
    final clampedDelta = delta.clamp(-1.0, 1.0);
    final ratio = (clampedDelta + 1.0) / 2.0; // 0.0 to 1.0
    final x = ratio * size.width;

    // Draw dot
    canvas.drawCircle(
      Offset(x, midY),
      6,
      Paint()..color = AppTheme.tempColor,
    );
  }

  @override
  bool shouldRepaint(TempGaugePainter old) => old.delta != delta;
}

// ── Stress gauge painter ────────────────────────────────────────────────────────

class StressGaugePainter extends CustomPainter {
  final int min;
  final int max;
  final int latest;

  const StressGaugePainter({required this.min, required this.max, required this.latest});

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    
    // Draw background track
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, midY - 4, size.width, 8),
      const Radius.circular(4),
    );
    canvas.drawRRect(trackRect, Paint()..color = Colors.white.withValues(alpha: 0.1));

    if (max > 0) {
      // Draw range bar
      final startX = (min / 100.0).clamp(0.0, 1.0) * size.width;
      final endX = (max / 100.0).clamp(0.0, 1.0) * size.width;
      
      final rangeRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(startX, midY - 4, endX, midY + 4),
        const Radius.circular(4),
      );
      canvas.drawRRect(rangeRect, Paint()..color = AppTheme.stressColor.withValues(alpha: 0.4));
    }

    // Draw latest dot
    final latestX = (latest / 100.0).clamp(0.0, 1.0) * size.width;
    canvas.drawCircle(
      Offset(latestX, midY),
      8,
      Paint()..color = AppTheme.stressColor,
    );
    // Draw white border for dot
    canvas.drawCircle(
      Offset(latestX, midY),
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(StressGaugePainter old) => old.min != min || old.max != max || old.latest != latest;
}

// ── Setup helpers ───────────────────────────────────────────────────────────────

class SetupField extends StatelessWidget {
  final String label;
  final Widget child;
  const SetupField({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: _inter(10,
                  weight: FontWeight.w700,
                  color: AppTheme.textSec,
                  letterSpacing: 1)),
          const SizedBox(height: 6),
          child,
        ],
      );
}

class StepperTile extends StatelessWidget {
  final int value;
  final String unit;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const StepperTile({
    super.key,
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
            color: AppTheme.card2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.div)),
        child: Row(children: [
          GestureDetector(
            onTap: value > min ? () => onChanged(value - 1) : null,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: AppTheme.div,
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.remove_rounded,
                  color: value > min ? Colors.white : AppTheme.textSec,
                  size: 18),
            ),
          ),
          Expanded(
            child: Center(
              child: RichText(
                text: TextSpan(children: [
                  TextSpan(
                      text: '$value ',
                      style: _inter(20, weight: FontWeight.w700)),
                  TextSpan(text: unit, style: _inter(13, color: AppTheme.textSec)),
                ]),
              ),
            ),
          ),
          GestureDetector(
            onTap: value < max ? () => onChanged(value + 1) : null,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppTheme.danger.withValues(alpha: 0.3))),
              child: Icon(Icons.add_rounded,
                  color: value < max ? AppTheme.danger : AppTheme.textSec,
                  size: 18),
            ),
          ),
        ]),
      );
}

// ── Linear cycle painter ──────────────────────────────────────────────────────

class LinearCyclePainter extends CustomPainter {
  final int currentDay;
  final int cycleLength;
  final int periodLength;
  final int fertileStart;
  final int fertileEnd;
  final int ovulationDay;

  const LinearCyclePainter({
    required this.currentDay,
    required this.cycleLength,
    required this.periodLength,
    required this.fertileStart,
    required this.fertileEnd,
    required this.ovulationDay,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Top ~60px for tooltip, next 12px for track, 16px for dots below
    final trackY = 60.0;
    
    // Spacing between dots/days
    final dotCount = cycleLength;
    final spacing = size.width / (dotCount - 1);

    // Track background
    final trackRect = RRect.fromLTRBR(
      0, trackY - 6, size.width, trackY + 6, const Radius.circular(6)
    );
    canvas.drawRRect(trackRect, Paint()..color = Colors.white.withValues(alpha: 0.15));

    // Period segment (red)
    if (periodLength > 0) {
      final periodW = (periodLength - 1).clamp(0, cycleLength - 1) * spacing;
      final periodRect = RRect.fromLTRBR(
        0, trackY - 6, periodW, trackY + 6, const Radius.circular(6)
      );
      canvas.drawRRect(periodRect, Paint()..color = AppTheme.danger);
    }

    // Fertile segment (teal)
    if (fertileEnd >= fertileStart) {
      final fertX1 = (fertileStart - 1).clamp(0, cycleLength - 1) * spacing;
      final fertX2 = (fertileEnd - 1).clamp(0, cycleLength - 1) * spacing;
      final fertRect = RRect.fromLTRBR(
        fertX1, trackY - 6, fertX2, trackY + 6, const Radius.circular(6)
      );
      canvas.drawRRect(fertRect, Paint()..color = AppTheme.hrvColor);
      
      // Ovulation day on track
      if (ovulationDay >= fertileStart && ovulationDay <= fertileEnd) {
        final ovuX = (ovulationDay - 1).clamp(0, cycleLength - 1) * spacing;
        canvas.drawCircle(Offset(ovuX, trackY), 5, Paint()..color = AppTheme.hrvColor);
        canvas.drawCircle(Offset(ovuX, trackY), 2.5, Paint()..color = Colors.white.withValues(alpha: 0.7));
      }
    }

    // Blood drop at end of track
    final endX = size.width;
    _paintBloodDrop(canvas, Offset(endX + 6, trackY), 3.5);

    // Current day thumb
    final currentX = (currentDay - 1).clamp(0, cycleLength - 1) * spacing;
    canvas.drawCircle(Offset(currentX, trackY), 8, Paint()..color = Colors.white);

    // Tooltip
    _drawTooltip(canvas, Offset(currentX, trackY - 14));

    // Dots below track
    final dotY = trackY + 20;
    for (int i = 0; i < dotCount; i++) {
      final x = i * spacing;
      final day = i + 1;
      
      if (day <= periodLength) {
        _paintBloodDrop(canvas, Offset(x, dotY), 2.5);
      } else if (day == currentDay) {
        canvas.drawCircle(Offset(x, dotY), 3.5, Paint()..color = Colors.white);
      } else if (day >= fertileStart && day <= fertileEnd) {
        canvas.drawCircle(Offset(x, dotY), 3.5, Paint()..color = AppTheme.hrvColor);
      } else {
        canvas.drawCircle(Offset(x, dotY), 3.5, Paint()..color = Colors.white.withValues(alpha: 0.22));
      }
    }
  }

  void _paintBloodDrop(Canvas canvas, Offset pos, double r) {
    final path = Path()
      ..moveTo(pos.dx, pos.dy - r * 0.8) // Top tip
      ..quadraticBezierTo(pos.dx + r * 1.2, pos.dy, pos.dx + r, pos.dy + r)
      ..quadraticBezierTo(pos.dx, pos.dy + r * 2, pos.dx - r, pos.dy + r)
      ..quadraticBezierTo(pos.dx - r * 1.2, pos.dy, pos.dx, pos.dy - r * 0.8);
    canvas.drawPath(path, Paint()..color = AppTheme.danger);
  }

  void _drawTooltip(Canvas canvas, Offset bottomCenter) {
    final tooltipW = 54.0;
    final tooltipH = 50.0;
    final r = 14.0;
    final arrowH = 8.0;
    final arrowW = 12.0;

    final rect = Rect.fromLTRB(
      bottomCenter.dx - tooltipW / 2,
      bottomCenter.dy - arrowH - tooltipH,
      bottomCenter.dx + tooltipW / 2,
      bottomCenter.dy - arrowH
    );

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)))
      ..moveTo(bottomCenter.dx - arrowW / 2, bottomCenter.dy - arrowH)
      ..lineTo(bottomCenter.dx, bottomCenter.dy)
      ..lineTo(bottomCenter.dx + arrowW / 2, bottomCenter.dy - arrowH)
      ..close();

    canvas.drawPath(
      path, 
      Paint()
        ..color = Colors.white.withValues(alpha: 0.05)
        ..style = PaintingStyle.fill
    );
    canvas.drawPath(
      path, 
      Paint()
        ..color = Colors.white.withValues(alpha: 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
    );

    // Text for tooltip
    final textPainterDay = TextPainter(
      text: TextSpan(
        text: 'DAY',
        style: _inter(10, color: Colors.white.withValues(alpha: 0.5), weight: FontWeight.w600, letterSpacing: 1.5)
      ),
      textDirection: TextDirection.ltr,
    );
    textPainterDay.layout();
    
    final textPainterNum = TextPainter(
      text: TextSpan(
        text: '$currentDay',
        style: _inter(18, color: Colors.white, weight: FontWeight.w600)
      ),
      textDirection: TextDirection.ltr,
    );
    textPainterNum.layout();

    final contentY = rect.top + (tooltipH - textPainterDay.height - textPainterNum.height - 2) / 2;
    textPainterDay.paint(canvas, Offset(bottomCenter.dx - textPainterDay.width / 2, contentY));
    textPainterNum.paint(canvas, Offset(bottomCenter.dx - textPainterNum.width / 2, contentY + textPainterDay.height + 2));
  }

  @override
  bool shouldRepaint(LinearCyclePainter old) =>
      old.currentDay != currentDay ||
      old.cycleLength != cycleLength ||
      old.periodLength != periodLength ||
      old.fertileStart != fertileStart ||
      old.fertileEnd != fertileEnd ||
      old.ovulationDay != ovulationDay;
}
