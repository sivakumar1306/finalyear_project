import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'app_typography.dart';

/// Metric chart card frame: header + range label, Y-axis tick column, the
/// chart child (or a loading spinner), and optional X-axis labels.
class MetricChartCard extends StatelessWidget {
  const MetricChartCard({
    super.key,
    required this.headerLabel,
    required this.rangeLabel,
    required this.child,
    this.height = 128,
    this.xLabels,
    this.yLabels,
    this.loading = false,
    this.loadingAccent = AppTheme.gold,
    this.barCount,
    this.footer,
  });

  final String headerLabel;
  final String rangeLabel;
  final double height;
  final Widget child;
  final List<String>? xLabels;
  final List<String>? yLabels;
  final bool loading;
  final Color loadingAccent;

  /// Number of bars in the chart; enables the equal-width x-label slots mode
  /// (one label per bar). Without it labels are laid out as axis ticks.
  final int? barCount;

  /// Optional row shown below the x-axis labels (e.g. a chart legend).
  final Widget? footer;

  static const yAxisWidth = 30.0;

  @override
  Widget build(BuildContext context) {
    final hasY = yLabels != null && yLabels!.isNotEmpty;
    final slotsMode = barCount != null &&
        xLabels != null &&
        xLabels!.length == barCount &&
        xLabels!.isNotEmpty &&
        xLabels!.every((l) => l.isNotEmpty);
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
            children: [
              Expanded(
                child: Text(
                  headerLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textTertiary,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  rangeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: AppTypography.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.iconMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: height,
            width: double.infinity,
            child: hasY
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: yAxisWidth,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (final label in yLabels!)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    label,
                                    maxLines: 1,
                                    softWrap: false,
                                    style: AppTypography.inter(
                                      fontSize: 10,
                                      color: AppTheme.textTertiary,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: loading
                            ? Center(
                                child: CircularProgressIndicator(
                                  color: loadingAccent,
                                  strokeWidth: 2,
                                ),
                              )
                            : child,
                      ),
                    ],
                  )
                : loading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: loadingAccent,
                          strokeWidth: 2,
                        ),
                      )
                    : child,
          ),
          // Equal-width columns so each label sits under its bar slot.
          // Offset by Y-axis width when present so labels stay under the bars.
          if (xLabels != null && xLabels!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.only(left: hasY ? yAxisWidth : 0),
              child: slotsMode
                  ? Row(
                      children: [
                        for (final label in xLabels!)
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                        for (final label in xLabels!)
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: AppTypography.inter(
                                fontSize: 10,
                                color: AppTheme.textTertiary,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
          if (footer != null) ...[
            const SizedBox(height: 12),
            footer!,
          ],
        ],
          ),
        ),
      ),
    );
  }
}