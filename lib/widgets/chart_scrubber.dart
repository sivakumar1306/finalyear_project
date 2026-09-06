import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../utils/scrub_helper.dart';
import 'app_typography.dart';

/// Thick track + ball thumb scrubber for health charts.
/// Mirrors QRing's chart scrubber: a 6px glass track with a gold ball thumb
/// that's easy to grab (large hit area) and sits at the bottom of the graph.
class ChartScrubber extends StatelessWidget {
  const ChartScrubber({
    super.key,
    required this.itemCount,
    required this.selectedIndex,
    required this.onChanged,
    required this.accent,
    this.enabled = true,
  });

  final int itemCount;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final Color accent;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (itemCount <= 1) return const SizedBox.shrink();
    final max = (itemCount - 1).toDouble();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Value tooltip - glass pill showing selected index
        // Parent can overlay its own tooltip; this is subtle helper
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 2,
            activeTrackColor: Colors.transparent,
            inactiveTrackColor: AppTheme.white10,
            secondaryActiveTrackColor: Colors.transparent,
            thumbColor: Colors.white,
            overlayColor: Colors.transparent,
            thumbShape: _BallThumbShape(
              thumbRadius: 10,
              accent: accent,
              enabled: enabled,
            ),
            overlayShape: SliderComponentShape.noOverlay,
            trackShape: const _NotchedTrackShape(),
            tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 0),
          ),
          child: Slider(
            value: selectedIndex.clamp(0, max).toDouble(),
            min: 0,
            max: max,
            divisions: itemCount > 1 ? itemCount - 1 : null,
            onChanged: enabled
                ? (v) {
                    final idx = v.round().clamp(0, itemCount - 1);
                    if (idx != selectedIndex) {
                      HapticFeedback.selectionClick();
                      onChanged(idx);
                    }
                  }
                : null,
          ),
        ),
      ],
    );
  }
}

/// Custom thumb: gold ball with soft shadow + thin white border
/// per DESIGN.md glass system - premium, calm, not flat.
class _BallThumbShape extends SliderComponentShape {
  const _BallThumbShape({
    required this.thumbRadius,
    required this.accent,
    required this.enabled,
  });

  final double thumbRadius;
  final Color accent;
  final bool enabled;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(thumbRadius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    bool isDiscrete = false,
    TextPainter? labelPainter,
    RenderBox? parentBox,
    required SliderThemeData sliderTheme,
    TextDirection textDirection = TextDirection.ltr,
    double value = 0,
    double textScaleFactor = 1,
    Size? sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    final fillPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, thumbRadius, fillPaint);
  }
}

class _NotchedTrackShape extends SliderTrackShape {
  const _NotchedTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 2.0;
    final trackLeft = offset.dx;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final Canvas canvas = context.canvas;
    
    final trackPaint = Paint()
      ..color = sliderTheme.inactiveTrackColor ?? AppTheme.white10
      ..style = PaintingStyle.stroke
      ..strokeWidth = sliderTheme.trackHeight ?? 2.0;

    final notchRadius = 14.0;
    final path = Path();
    path.moveTo(offset.dx, thumbCenter.dy);
    
    if (thumbCenter.dx - offset.dx > notchRadius) {
      path.lineTo(thumbCenter.dx - notchRadius, thumbCenter.dy);
      path.arcToPoint(
        Offset(thumbCenter.dx + notchRadius, thumbCenter.dy),
        radius: Radius.circular(notchRadius),
        clockwise: false,
      );
      path.lineTo(offset.dx + parentBox.size.width, thumbCenter.dy);
    } else {
      path.lineTo(offset.dx + parentBox.size.width, thumbCenter.dy);
    }
    
    canvas.drawPath(path, trackPaint);
  }
}

/// Wrapper that adds a scrubber to any MetricChartCard content.
/// Manages selectedIndex internally and exposes it to the painter via builder.
/// Uses glass styling per DESIGN.md.
class ScrubbableChart extends StatefulWidget {
  const ScrubbableChart({
    super.key,
    required this.values,
    required this.maxY,
    required this.yLines,
    this.baseline = 0,
    this.barColor,
    this.colorFor,
    this.accent = AppTheme.gold,
    this.xLabels,
    this.yLabels,
    this.height = 128,
    this.barCount,
    this.headerLabel = '',
    this.rangeLabel = '',
    this.footer,
    this.showScrubber = true,
    this.onScrub,
    this.valueLabelBuilder,
    this.loading = false,
    this.loadingAccent = AppTheme.gold,
  });

  final List<num> values;
  final double maxY;
  final List<int> yLines;
  final double baseline;
  final Color? barColor;
  final Color Function(num value)? colorFor;
  final Color accent;
  final List<String>? xLabels;
  final List<String>? yLabels;
  final double height;
  final int? barCount;
  final String headerLabel;
  final String rangeLabel;
  final Widget? footer;
  final bool showScrubber;
  final ValueChanged<int>? onScrub;
  final String Function(int index, num value)? valueLabelBuilder;
  final bool loading;
  final Color loadingAccent;

  @override
  State<ScrubbableChart> createState() => _ScrubbableChartState();
}

class _ScrubbableChartState extends State<ScrubbableChart> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = _initialIndex();
  }

  @override
  void didUpdateWidget(covariant ScrubbableChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.values != widget.values) {
      // Keep selection within bounds, prefer last non-zero
      final newIdx = _initialIndex();
      if (newIdx != _selectedIndex) {
        _selectedIndex = newIdx.clamp(0, (widget.values.length - 1).clamp(0, 999));
      } else if (_selectedIndex >= widget.values.length) {
        _selectedIndex = (widget.values.length - 1).clamp(0, 999);
      }
    }
  }

  int _initialIndex() {
    if (widget.values.isEmpty) return 0;
    // Prefer last non-zero bar (most recent reading) — pure engine
    if (widget.values.first is int) {
      return ScrubHelper.initialIndex(List<int>.from(widget.values as List));
    }
    return ScrubHelper.initialIndexDouble(
        (widget.values as List).map((v) => (v as num).toDouble()).toList());
  }

  @override
  Widget build(BuildContext context) {
    final hasScrubber = widget.showScrubber && widget.values.length > 1;
    final selectedValue =
        widget.values.isNotEmpty && _selectedIndex < widget.values.length
            ? widget.values[_selectedIndex]
            : 0;
    final xLabelForSelected = widget.xLabels != null &&
            widget.xLabels!.length == widget.values.length &&
            _selectedIndex < widget.xLabels!.length
        ? widget.xLabels![_selectedIndex]
        : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            color: AppTheme.glassCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.glassBorder, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.headerLabel,
                    style: AppTypography.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textTertiary,
                      letterSpacing: 0.6,
                    ),
                  ),
              Row(
                children: [
                  Text(
                    widget.rangeLabel,
                    style: AppTypography.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.iconMuted,
                    ),
                  ),
                  if (hasScrubber && selectedValue > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: widget.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: widget.accent.withValues(alpha: 0.22)),
                      ),
                      child: Text(
                        widget.valueLabelBuilder?.call(_selectedIndex, selectedValue) ??
                            (xLabelForSelected != null
                                ? '$xLabelForSelected • $selectedValue'
                                : '$selectedValue'),
                        style: AppTypography.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: widget.accent,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: widget.height,
            width: double.infinity,
            child: widget.loading
                ? Center(
                    child: CircularProgressIndicator(
                      color: widget.loadingAccent,
                      strokeWidth: 2,
                    ),
                  )
                : widget.yLabels != null && widget.yLabels!.isNotEmpty
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 30,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                for (final label in widget.yLabels!)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Text(
                                      label,
                                      style: AppTypography.inter(
                                        fontSize: 10,
                                        color: AppTheme.textTertiary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _buildChartContent(hasScrubber),
                          ),
                        ],
                      )
                    : _buildChartContent(hasScrubber),
          ),
          if (widget.xLabels != null && widget.xLabels!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.only(
                  left: widget.yLabels != null && widget.yLabels!.isNotEmpty ? 30 : 0),
              child: widget.barCount != null &&
                      widget.xLabels!.length == widget.barCount &&
                      widget.xLabels!.every((l) => l.isNotEmpty)
                  ? Row(
                      children: [
                        for (final label in widget.xLabels!)
                          Expanded(
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              style: AppTypography.inter(
                                fontSize: 10,
                                color: AppTheme.textSec,
                              ),
                            ),
                          ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final label in widget.xLabels!)
                          Text(
                            label,
                            style: AppTypography.inter(
                              fontSize: 10,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                      ],
                    ),
            ),
          ],
          if (hasScrubber) ...[
            const SizedBox(height: 14),
            ChartScrubber(
              itemCount: widget.values.length,
              selectedIndex: _selectedIndex,
              accent: widget.accent,
              enabled: !widget.loading,
              onChanged: (idx) {
                setState(() => _selectedIndex = idx);
                widget.onScrub?.call(idx);
              },
            ),
          ],
          if (widget.footer != null) ...[
            const SizedBox(height: 12),
            widget.footer!,
          ],
        ],
          ),
        ),
      ),
    );
  }

  Widget _buildChartContent(bool hasScrubber) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: hasScrubber
              ? (details) {
                  final idx = ScrubHelper.indexFromDx(
                      details.localPosition.dx,
                      constraints.maxWidth,
                      widget.values.length);
                  if (idx != _selectedIndex) {
                    setState(() => _selectedIndex = idx);
                    widget.onScrub?.call(idx);
                    HapticFeedback.selectionClick();
                  }
                }
              : null,
          onTapDown: hasScrubber
              ? (details) {
                  final idx = ScrubHelper.indexFromDx(
                      details.localPosition.dx,
                      constraints.maxWidth,
                      widget.values.length);
                  setState(() => _selectedIndex = idx);
                  widget.onScrub?.call(idx);
                  HapticFeedback.selectionClick();
                }
              : null,
          child: CustomPaint(
            painter: _ScrubbableBarPainter(
              values: widget.values,
              maxY: widget.maxY,
              yLines: widget.yLines,
              baseline: widget.baseline,
              barColor: widget.barColor,
              colorFor: widget.colorFor,
              selectedIndex: hasScrubber ? _selectedIndex : null,
              accent: widget.accent,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

/// Painter that highlights the scrubbed bar with accent and guide line
class _ScrubbableBarPainter extends CustomPainter {
  const _ScrubbableBarPainter({
    required this.values,
    required this.maxY,
    required this.yLines,
    this.baseline = 0,
    this.barColor,
    this.colorFor,
    this.selectedIndex,
    this.accent = AppTheme.gold,
  });

  final List<num> values;
  final double maxY;
  final List<int> yLines;
  final double baseline;
  final Color? barColor;
  final Color Function(num value)? colorFor;
  final int? selectedIndex;
  final Color accent;

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
    final barW = (slotW * 0.55).clamp(2.0, 9.0).toDouble();

    // Guide line for selected index
    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < n &&
        values[selectedIndex!] > 0) {
      final cx = selectedIndex! * slotW + slotW / 2;
      final guidePaint = Paint()
        ..color = accent.withValues(alpha: 0.18)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      // Dashed guide
      const dashH = 3.0;
      const gapH = 3.0;
      double y = 0;
      while (y < size.height) {
        canvas.drawLine(Offset(cx, y), Offset(cx, (y + dashH).clamp(0, size.height)), guidePaint);
        y += dashH + gapH;
      }
      // Soft glow behind selected bar
      final glowPaint = Paint()
        ..color = accent.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      final glowRect = RRect.fromLTRBR(
        cx - slotW / 2 + 2,
        0,
        cx + slotW / 2 - 2,
        size.height,
        const Radius.circular(6),
      );
      canvas.drawRRect(glowRect, glowPaint);
    }

    for (int i = 0; i < n; i++) {
      final v = values[i];
      if (v <= 0) continue;
      final normalized = ((v - baseline) / range).clamp(0.0, 1.0).toDouble();
      final barH = (normalized * size.height).clamp(2.0, size.height).toDouble();
      final x = i * slotW + (slotW - barW) / 2;
      final isSelected = selectedIndex == i;

      final baseColor = colorFor != null ? colorFor!(v) : barColor ?? AppTheme.gold;
      final paint = Paint()
        ..color = isSelected ? accent : baseColor.withValues(alpha: isSelected ? 1.0 : 0.88);

      final rrect = RRect.fromLTRBR(
        x,
        size.height - barH,
        x + barW,
        size.height,
        const Radius.circular(3),
      );

      // Selected bar is slightly brighter + taller nudge
      if (isSelected) {
        // Outer stroke for lift
        final borderPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        canvas.drawRRect(rrect, paint);
        canvas.drawRRect(rrect, borderPaint);
        // Top dot highlight
        final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.55);
        canvas.drawCircle(Offset(x + barW / 2, size.height - barH), 2, dotPaint);
      } else {
        canvas.drawRRect(rrect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScrubbableBarPainter old) =>
      old.values != values ||
      old.maxY != maxY ||
      old.baseline != baseline ||
      old.yLines != yLines ||
      old.barColor != barColor ||
      old.colorFor != colorFor ||
      old.selectedIndex != selectedIndex ||
      old.accent != accent;
}

/// Scrubbable BP chart - dual bars (SBP/DBP) with ball scrubber
class ScrubbableBPChart extends StatefulWidget {
  const ScrubbableBPChart({
    super.key,
    required this.sbpValues,
    required this.dbpValues,
    this.yLabels,
    this.xLabels,
    this.height = 128,
    this.barCount,
    this.headerLabel = '',
    this.rangeLabel = '',
    this.loading = false,
    this.loadingAccent = AppTheme.bpColor,
    this.footer,
    this.showScrubber = true,
    this.accent = AppTheme.bpColor,
    this.onScrub,
  });

  final List<int> sbpValues;
  final List<int> dbpValues;
  final List<String>? yLabels;
  final List<String>? xLabels;
  final double height;
  final int? barCount;
  final String headerLabel;
  final String rangeLabel;
  final bool loading;
  final Color loadingAccent;
  final Widget? footer;
  final bool showScrubber;
  final Color accent;
  final ValueChanged<int>? onScrub;

  @override
  State<ScrubbableBPChart> createState() => _ScrubbableBPChartState();
}

class _ScrubbableBPChartState extends State<ScrubbableBPChart> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = _initialIndex();
  }

  int _initialIndex() {
    if (widget.sbpValues.isEmpty) return 0;
    for (int i = widget.sbpValues.length - 1; i >= 0; i--) {
      if (widget.sbpValues[i] > 0) return i;
    }
    return 0;
  }

  @override
  void didUpdateWidget(covariant ScrubbableBPChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sbpValues != widget.sbpValues ||
        oldWidget.dbpValues != widget.dbpValues) {
      final newIdx = _initialIndex();
      if (newIdx != _selectedIndex) {
        _selectedIndex = newIdx.clamp(0, (widget.sbpValues.length - 1).clamp(0, 999));
      } else if (_selectedIndex >= widget.sbpValues.length) {
        _selectedIndex = (widget.sbpValues.length - 1).clamp(0, 999);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasScrubber = widget.showScrubber && widget.sbpValues.length > 1;
    final selSbp = widget.sbpValues.isNotEmpty && _selectedIndex < widget.sbpValues.length
        ? widget.sbpValues[_selectedIndex]
        : 0;
    final selDbp = widget.dbpValues.isNotEmpty && _selectedIndex < widget.dbpValues.length
        ? widget.dbpValues[_selectedIndex]
        : 0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            color: AppTheme.glassCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.glassBorder, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.headerLabel,
                style: AppTypography.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textTertiary,
                  letterSpacing: 0.6,
                ),
              ),
              Row(
                children: [
                  Text(
                    widget.rangeLabel,
                    style: AppTypography.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.iconMuted,
                    ),
                  ),
                  if (hasScrubber && selSbp > 0 && selDbp > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: widget.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: widget.accent.withValues(alpha: 0.22)),
                      ),
                      child: Text(
                        '$selSbp/$selDbp',
                        style: AppTypography.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: widget.accent,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: widget.height,
            width: double.infinity,
            child: widget.loading
                ? Center(child: CircularProgressIndicator(color: widget.loadingAccent, strokeWidth: 2))
                : widget.yLabels != null && widget.yLabels!.isNotEmpty
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 30,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                for (final l in widget.yLabels!)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Text(l,
                                        style: AppTypography.inter(fontSize: 10, color: AppTheme.textTertiary)),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(child: _buildChart(hasScrubber)),
                        ],
                      )
                    : _buildChart(hasScrubber),
          ),
          if (widget.xLabels != null && widget.xLabels!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.only(left: widget.yLabels != null && widget.yLabels!.isNotEmpty ? 30 : 0),
              child: widget.barCount != null && widget.xLabels!.length == widget.barCount
                  ? Row(
                      children: [
                        for (final l in widget.xLabels!)
                          Expanded(
                              child: Text(l,
                                  textAlign: TextAlign.center,
                                  style: AppTypography.inter(fontSize: 10, color: AppTheme.textSec))),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final l in widget.xLabels!)
                          Text(l, style: AppTypography.inter(fontSize: 10, color: AppTheme.textTertiary)),
                      ],
                    ),
            ),
          ],
          if (hasScrubber) ...[
            const SizedBox(height: 14),
            ChartScrubber(
              itemCount: widget.sbpValues.length,
              selectedIndex: _selectedIndex,
              accent: widget.accent,
              enabled: !widget.loading,
              onChanged: (idx) {
                setState(() => _selectedIndex = idx);
                widget.onScrub?.call(idx);
              },
            ),
          ],
          if (widget.footer != null) ...[
            const SizedBox(height: 12),
            widget.footer!,
          ],
        ],
          ),
        ),
      ),
    );
  }

  Widget _buildChart(bool hasScrubber) {
    return LayoutBuilder(builder: (context, c) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: hasScrubber
            ? (d) {
                final idx = ((d.localPosition.dx / c.maxWidth) * widget.sbpValues.length)
                    .floor()
                    .clamp(0, widget.sbpValues.length - 1);
                if (idx != _selectedIndex) {
                  setState(() => _selectedIndex = idx);
                  widget.onScrub?.call(idx);
                  HapticFeedback.selectionClick();
                }
              }
            : null,
        onTapDown: hasScrubber
            ? (d) {
                final idx = ((d.localPosition.dx / c.maxWidth) * widget.sbpValues.length)
                    .floor()
                    .clamp(0, widget.sbpValues.length - 1);
                setState(() => _selectedIndex = idx);
                widget.onScrub?.call(idx);
                HapticFeedback.selectionClick();
              }
            : null,
        child: CustomPaint(
          painter: _ScrubbableBPBarPainter(
            sbpValues: widget.sbpValues,
            dbpValues: widget.dbpValues,
            selectedIndex: hasScrubber ? _selectedIndex : null,
            accent: widget.accent,
          ),
          child: const SizedBox.expand(),
        ),
      );
    });
  }
}

class _ScrubbableBPBarPainter extends CustomPainter {
  const _ScrubbableBPBarPainter({
    required this.sbpValues,
    required this.dbpValues,
    this.selectedIndex,
    this.accent = AppTheme.bpColor,
  });
  final List<int> sbpValues;
  final List<int> dbpValues;
  final int? selectedIndex;
  final Color accent;
  static const _maxY = 160.0;
  static const _yLines = [160, 120, 80, 40];
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()..color = AppTheme.grid..strokeWidth = 0.5;
    for (final y in _yLines) {
      final yPos = size.height - (y / _maxY) * size.height;
      canvas.drawLine(Offset(0, yPos), Offset(size.width, yPos), gridPaint);
    }
    if (sbpValues.isEmpty) return;
    final n = sbpValues.length;
    final slotW = size.width / n;
    final barW = (slotW * 0.3).clamp(1.5, 5.0);

    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < n &&
        sbpValues[selectedIndex!] > 0) {
      final cx = selectedIndex! * slotW + slotW / 2;
      final guide = Paint()..color = accent.withValues(alpha: 0.18)..strokeWidth = 1;
      double y = 0;
      const dash = 3.0, gap = 3.0;
      while (y < size.height) {
        canvas.drawLine(Offset(cx, y), Offset(cx, (y + dash).clamp(0, size.height)), guide);
        y += dash + gap;
      }
      final glow = Paint()
        ..color = accent.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawRRect(
        RRect.fromLTRBR(cx - slotW / 2 + 2, 0, cx + slotW / 2 - 2, size.height, const Radius.circular(6)),
        glow,
      );
    }

    final sbpPaint = Paint()..color = AppTheme.bpColor.withValues(alpha: 0.88);
    final dbpPaint = Paint()..color = AppTheme.softViolet.withValues(alpha: 0.88);
    final selSbpPaint = Paint()..color = accent.withValues(alpha: 0.95);
    final selDbpPaint = Paint()..color = accent.withValues(alpha: 0.65);
    for (int i = 0; i < n; i++) {
      final cx = i * slotW + slotW / 2;
      final isSel = selectedIndex == i;
      final sbp = sbpValues[i];
      if (sbp > 0) {
        final ratio = (sbp / _maxY).clamp(0.0, 1.0);
        final h = (ratio * size.height).clamp(2.0, size.height);
        final r = RRect.fromLTRBR(cx - barW - 1, size.height - h, cx - 1, size.height, const Radius.circular(2));
        canvas.drawRRect(r, isSel ? selSbpPaint : sbpPaint);
        if (isSel) {
          canvas.drawRRect(r, Paint()..color = Colors.white.withValues(alpha: 0.18)..style = PaintingStyle.stroke..strokeWidth = 1);
        }
      }
      final dbp = i < dbpValues.length ? dbpValues[i] : 0;
      if (dbp > 0) {
        final ratio = (dbp / _maxY).clamp(0.0, 1.0);
        final h = (ratio * size.height).clamp(2.0, size.height);
        final r = RRect.fromLTRBR(cx + 1, size.height - h, cx + barW + 1, size.height, const Radius.circular(2));
        canvas.drawRRect(r, isSel ? selDbpPaint : dbpPaint);
        if (isSel) {
          canvas.drawRRect(r, Paint()..color = Colors.white.withValues(alpha: 0.18)..style = PaintingStyle.stroke..strokeWidth = 1);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScrubbableBPBarPainter old) =>
      old.sbpValues != sbpValues || old.dbpValues != dbpValues || old.selectedIndex != selectedIndex || old.accent != accent;
}
