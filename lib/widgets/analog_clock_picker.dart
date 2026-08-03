import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import './app_typography.dart';

/// A basic, clean drag-to-set analog clock — tap or drag anywhere on the
/// dial to move both hands to that position (classic single-gesture clock
/// picker), with a small AM/PM pill below. No numerals, no clutter — just
/// ticks and two hands, per DESIGN.md's soft-glassmorphism spec.
class AnalogClockPicker extends StatefulWidget {
  final TimeOfDay initialTime;
  final ValueChanged<TimeOfDay> onChanged;
  final double size;

  const AnalogClockPicker({
    super.key,
    required this.initialTime,
    required this.onChanged,
    this.size = 240,
  });

  @override
  State<AnalogClockPicker> createState() => _AnalogClockPickerState();
}

class _AnalogClockPickerState extends State<AnalogClockPicker> {
  late TimeOfDay _time = widget.initialTime;

  @override
  void didUpdateWidget(covariant AnalogClockPicker old) {
    super.didUpdateWidget(old);
    if (old.initialTime != widget.initialTime) _time = widget.initialTime;
  }

  void _updateFromLocal(Offset local) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final v = local - center;
    // 0 rad = 12 o'clock, increasing clockwise.
    var angle = math.atan2(v.dx, -v.dy);
    if (angle < 0) angle += 2 * math.pi;
    final totalMinutes = (angle / (2 * math.pi) * 720).round() % 720;
    final snapped = ((totalMinutes / 5).round() * 5) % 720;
    final hour12 = snapped ~/ 60;
    final minute = snapped % 60;
    final isPM = _time.hour >= 12;
    final hour24 = (hour12 % 12) + (isPM ? 12 : 0);
    final next = TimeOfDay(hour: hour24, minute: minute);
    if (next != _time) {
      setState(() => _time = next);
      widget.onChanged(next);
    }
  }

  void _setPeriod(bool isPM) {
    final currentlyPM = _time.hour >= 12;
    if (isPM == currentlyPM) return;
    final next = TimeOfDay(hour: (_time.hour + 12) % 24, minute: _time.minute);
    setState(() => _time = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final hour12 = _time.hourOfPeriod == 0 ? 12 : _time.hourOfPeriod;
    final minuteFraction = _time.minute / 60;
    final hourAngle = (hour12 % 12 + minuteFraction) / 12 * 2 * math.pi;
    final minuteAngle = _time.minute / 60 * 2 * math.pi;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onPanStart: (d) => _updateFromLocal(d.localPosition),
          onPanUpdate: (d) => _updateFromLocal(d.localPosition),
          onTapDown: (d) => _updateFromLocal(d.localPosition),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              painter: _ClockFacePainter(
                hourAngle: hourAngle,
                minuteAngle: minuteAngle,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _AmPmToggle(
          isPM: _time.hour >= 12,
          onChanged: _setPeriod,
        ),
      ],
    );
  }
}

/// Two-segment AM/PM toggle — tap either side to select that period
/// directly, rather than cycling through a single pill.
class _AmPmToggle extends StatelessWidget {
  final bool isPM;
  final ValueChanged<bool> onChanged;

  const _AmPmToggle({required this.isPM, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AmPmSegment(label: 'AM', selected: !isPM, onTap: () => onChanged(false)),
          _AmPmSegment(label: 'PM', selected: isPM, onTap: () => onChanged(true)),
        ],
      ),
    );
  }
}

class _AmPmSegment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AmPmSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.gold.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: selected
              ? Border.all(color: AppTheme.gold.withValues(alpha: 0.4))
              : null,
        ),
        child: Text(
          label,
          style: AppTypography.inter(
            color: selected ? AppTheme.gold : Colors.white.withValues(alpha: 0.4),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

class _ClockFacePainter extends CustomPainter {
  final double hourAngle;
  final double minuteAngle;
  const _ClockFacePainter({required this.hourAngle, required this.minuteAngle});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()..color = Colors.white.withValues(alpha: 0.04),
    );
    canvas.drawCircle(
      center,
      radius - 0.5,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.09)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    for (int i = 0; i < 12; i++) {
      final a = i / 12 * 2 * math.pi;
      final isCardinal = i % 3 == 0;
      final outer = Offset(
        center.dx + math.sin(a) * (radius - 10),
        center.dy - math.cos(a) * (radius - 10),
      );
      final inner = Offset(
        center.dx + math.sin(a) * (radius - (isCardinal ? 20 : 16)),
        center.dy - math.cos(a) * (radius - (isCardinal ? 20 : 16)),
      );
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = Colors.white.withValues(alpha: isCardinal ? 0.35 : 0.15)
          ..strokeWidth = isCardinal ? 2 : 1
          ..strokeCap = StrokeCap.round,
      );
    }

    final hourLen = radius * 0.45;
    canvas.drawLine(
      center,
      Offset(
        center.dx + math.sin(hourAngle) * hourLen,
        center.dy - math.cos(hourAngle) * hourLen,
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round,
    );

    final minLen = radius * 0.68;
    canvas.drawLine(
      center,
      Offset(
        center.dx + math.sin(minuteAngle) * minLen,
        center.dy - math.cos(minuteAngle) * minLen,
      ),
      Paint()
        ..color = AppTheme.gold
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(center, 4, Paint()..color = AppTheme.gold);
    canvas.drawCircle(
      center,
      4,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_ClockFacePainter old) =>
      old.hourAngle != hourAngle || old.minuteAngle != minuteAngle;
}
