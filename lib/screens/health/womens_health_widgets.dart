import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/womens_health_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_typography.dart';

const _kToday = AppTheme.softBlue; // blue

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

// ── Cycle ring painter ────────────────────────────────────────────────────────

class CycleRingPainter extends CustomPainter {
  final int currentDay;
  final int cycleLength;

  const CycleRingPainter({required this.currentDay, required this.cycleLength});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 18;
    const strokeW = 14.0;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW,
    );

    final progress = (currentDay / cycleLength).clamp(0.0, 1.0);
    if (progress <= 0) return;

    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round
        ..shader = const LinearGradient(
          colors: [AppTheme.womenColor, Color(0xFFA855F7)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(CycleRingPainter old) =>
      old.currentDay != currentDay || old.cycleLength != cycleLength;
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
    final markerRatio = ((cycle.cycleLength - 14) / cycle.cycleLength).clamp(0.05, 0.95);

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
            child: CyclePatternTrack(markerRatio: markerRatio),
          ),
        ),
        const SizedBox(width: 10),
        Text(rangeLabel, style: _inter(11, color: AppTheme.textSec)),
      ],
    );
  }
}

class CyclePatternTrack extends StatelessWidget {
  final double markerRatio;
  const CyclePatternTrack({super.key, required this.markerRatio});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        const markerSize = 20.0;
        return Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(w, 22),
              painter: CyclePatternDotsPainter(markerRatio: markerRatio),
            ),
            Positioned(
              left: (markerRatio * w - markerSize / 2).clamp(0.0, w - markerSize),
              child: Container(
                width: markerSize,
                height: markerSize,
                decoration: const BoxDecoration(
                  color: _kToday,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.circle, color: Colors.white, size: 8),
              ),
            ),
          ],
        );
      },
    );
  }
}

class CyclePatternDotsPainter extends CustomPainter {
  final double markerRatio;
  const CyclePatternDotsPainter({required this.markerRatio});

  static const _dotCount = 26;

  @override
  void paint(Canvas canvas, Size size) {
    final gap = size.width / (_dotCount - 1);
    for (int i = 0; i < _dotCount; i++) {
      final ratio = i / (_dotCount - 1);
      if ((ratio - markerRatio).abs() < 0.06) continue;
      final color = ratio < markerRatio
          ? AppTheme.hrvColor.withValues(alpha: 0.7)
          : AppTheme.womenColor.withValues(alpha: 0.45);
      canvas.drawCircle(
        Offset(i * gap, size.height / 2),
        2.2,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(CyclePatternDotsPainter old) =>
      old.markerRatio != markerRatio;
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
                  color: AppTheme.womenColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppTheme.womenColor.withValues(alpha: 0.3))),
              child: Icon(Icons.add_rounded,
                  color: value < max ? AppTheme.womenColor : AppTheme.textSec,
                  size: 18),
            ),
          ),
        ]),
      );
}