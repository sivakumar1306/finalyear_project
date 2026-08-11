import 'package:flutter/material.dart';

class RulerPicker extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final bool isInteger;
  final Axis axis;

  const RulerPicker({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.isInteger = true,
    this.axis = Axis.horizontal,
  });

  @override
  State<RulerPicker> createState() => _RulerPickerState();
}

class _RulerPickerState extends State<RulerPicker> {
  // Continuous, unsnapped drag position. This is what actually tracks
  // the finger 1:1 — every pixel of movement accumulates here, so the
  // ruler never "eats" small drag deltas.
  late double _raw;

  // Snapped value that's shown in labels and reported via onChanged.
  late double _value;

  static const double _pixelsPerUnit = 14.0;

  @override
  void initState() {
    super.initState();
    _raw = widget.value;
    _value = widget.value;
  }

  double _snap(double raw) {
    final step = widget.isInteger ? 1.0 : 0.5;
    return ((raw / step).round() * step).clamp(widget.min, widget.max);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // Accumulate every pixel of movement into the continuous position.
    // For vertical, finger moving up (negative delta dy) should mean moving to higher values.
    // So we add -dy. Or we subtract dy.
    setState(() {
      final delta = widget.axis == Axis.horizontal 
          ? d.delta.dx 
          : -d.delta.dy;
      _raw = (_raw - delta / _pixelsPerUnit).clamp(widget.min, widget.max);
      final snapped = _snap(_raw);
      if (snapped != _value) {
        _value = snapped;
        widget.onChanged(_value);
      }
    });
  }

  void _onDragEnd(DragEndDetails d) {
    // Settle the raw position onto the snapped value so the ruler
    // doesn't visually drift from the tick it landed on.
    setState(() => _raw = _value);
  }

  @override
  void didUpdateWidget(covariant RulerPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep in sync if the parent changes value externally.
    if (widget.value != oldWidget.value && widget.value != _value) {
      _raw = widget.value;
      _value = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.axis == Axis.horizontal) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Triangle indicator
          const Icon(Icons.arrow_drop_down, color: Color(0xFFC9A86E), size: 28),
          const SizedBox(height: 2),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            child: SizedBox(
              height: 48,
              child: CustomPaint(
                size: const Size(double.infinity, 48),
                painter: _RulerPainter(
                  value: _raw,
                  pixelsPerUnit: _pixelsPerUnit,
                  axis: widget.axis,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Range labels
          Builder(
            builder: (ctx) {
              final w = MediaQuery.of(ctx).size.width;
              final unitsVisible = (w / _pixelsPerUnit / 2).floor();
              final leftVal = (_value - unitsVisible)
                  .clamp(widget.min, widget.max)
                  .round();
              final rightVal = (_value + unitsVisible)
                  .clamp(widget.min, widget.max)
                  .round();
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$leftVal',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  Text(
                    '${_value.round()}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  Text(
                    '$rightVal',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              );
            },
          ),
        ],
      );
    } else {
      // Vertical layout
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        child: SizedBox(
          width: 140,
          child: CustomPaint(
            size: const Size(140, double.infinity),
            painter: _RulerPainter(
              value: _raw,
              pixelsPerUnit: _pixelsPerUnit,
              axis: widget.axis,
            ),
          ),
        ),
      );
    }
  }
}

class _RulerPainter extends CustomPainter {
  final double value;
  final double pixelsPerUnit;
  final Axis axis;

  _RulerPainter({
    required this.value, 
    required this.pixelsPerUnit,
    this.axis = Axis.horizontal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1.5;

    final majorPaint = Paint()
      ..color = Colors.white60
      ..strokeWidth = 2;

    if (axis == Axis.horizontal) {
      final centerX = size.width / 2;
      final unitsVisible = (size.width / pixelsPerUnit).ceil() + 4;
      final startUnit = (value - unitsVisible / 2).floor();
      final endUnit = (value + unitsVisible / 2).ceil();

      for (int u = startUnit; u <= endUnit; u++) {
        final x = centerX + (u - value) * pixelsPerUnit;
        if (x < 0 || x > size.width) continue;
        final isMajor = u % 5 == 0;
        final tickH = isMajor ? 20.0 : 10.0;
        canvas.drawLine(
          Offset(x, size.height - tickH),
          Offset(x, size.height),
          isMajor ? majorPaint : linePaint,
        );
      }
    } else {
      final centerY = size.height / 2;
      final unitsVisible = (size.height / pixelsPerUnit).ceil() + 4;
      final startUnit = (value - unitsVisible / 2).floor();
      final endUnit = (value + unitsVisible / 2).ceil();

      final tickStartX = 80.0;

      for (int u = startUnit; u <= endUnit; u++) {
        // For vertical, higher values should be visually higher (smaller y)
        final y = centerY - (u - value) * pixelsPerUnit;
        if (y < 0 || y > size.height) continue;
        final isMajor = u % 5 == 0;
        final tickW = isMajor ? 20.0 : 10.0;
        
        // Draw tick lines
        canvas.drawLine(
          Offset(tickStartX, y),
          Offset(tickStartX + tickW, y),
          isMajor ? majorPaint : linePaint,
        );

        if (isMajor) {
          final textPainter = TextPainter(
            text: TextSpan(
              text: '$u',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            textDirection: TextDirection.ltr,
          );
          textPainter.layout();
          textPainter.paint(
            canvas,
            Offset(65.0 - textPainter.width, y - textPainter.height / 2),
          );
        }
      }

      final path = Path();
      path.moveTo(tickStartX - 16, centerY - 6);
      path.lineTo(tickStartX - 4, centerY);
      path.lineTo(tickStartX - 16, centerY + 6);
      path.close();
      canvas.drawPath(path, Paint()..color = const Color(0xFFC9A86E));
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) => 
      old.value != value || old.axis != axis;
}
