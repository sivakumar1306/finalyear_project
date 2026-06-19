import 'package:flutter/material.dart';

class RulerPicker extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final bool isInteger;

  const RulerPicker({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.isInteger = true,
  });

  @override
  State<RulerPicker> createState() => _RulerPickerState();
}

class _RulerPickerState extends State<RulerPicker> {
  late double _value;
  static const double _pixelsPerUnit = 14.0;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Triangle indicator
        const Icon(Icons.arrow_drop_down, color: Color(0xFFF0A030), size: 28),
        const SizedBox(height: 2),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) {
            final delta = -d.delta.dx / _pixelsPerUnit;
            final step = widget.isInteger ? 1.0 : 0.5;
            final newRaw = _value + delta;
            final snapped = (newRaw / step).round() * step;
            final clamped = snapped.clamp(widget.min, widget.max);
            if (clamped != _value) {
              setState(() => _value = clamped);
              widget.onChanged(_value);
            }
          },
          child: SizedBox(
            height: 48,
            child: CustomPaint(
              size: const Size(double.infinity, 48),
              painter: _RulerPainter(value: _value, pixelsPerUnit: _pixelsPerUnit),
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Range labels
        Builder(builder: (ctx) {
          final w = MediaQuery.of(ctx).size.width;
          final unitsVisible = (w / _pixelsPerUnit / 2).floor();
          final leftVal = (_value - unitsVisible).clamp(widget.min, widget.max).round();
          final rightVal = (_value + unitsVisible).clamp(widget.min, widget.max).round();
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$leftVal', style: const TextStyle(color: Colors.white38, fontSize: 11)),
              Text('${_value.round()}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
              Text('$rightVal', style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          );
        }),
      ],
    );
  }
}

class _RulerPainter extends CustomPainter {
  final double value;
  final double pixelsPerUnit;

  _RulerPainter({required this.value, required this.pixelsPerUnit});

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final unitsVisible = (size.width / pixelsPerUnit).ceil() + 4;
    final startUnit = (value - unitsVisible / 2).floor();
    final endUnit = (value + unitsVisible / 2).ceil();

    final linePaint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1.5;

    final majorPaint = Paint()
      ..color = Colors.white60
      ..strokeWidth = 2;

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
  }

  @override
  bool shouldRepaint(_RulerPainter old) => old.value != value;
}
