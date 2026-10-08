import 'package:flutter/material.dart';
import 'app_typography.dart';
import 'glass_card.dart';

class ChartCard extends StatelessWidget {
  final String headerLabel;
  final String rangeLabel;
  final List<int> values;
  final List<String> xLabels;
  final List<String> yLabels;
  final bool loading;
  final Color barColor;
  final CustomPainter Function(List<int> values) createPainter;

  const ChartCard({
    super.key,
    required this.headerLabel,
    required this.rangeLabel,
    required this.values,
    required this.xLabels,
    required this.yLabels,
    required this.loading,
    required this.barColor,
    required this.createPainter,
  });

  static const _yAxisW = 30.0;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
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
                  style: AppTypography.inter(fontSize: 11, weight: FontWeight.w600, color: kSec, letterSpacing: 0.6),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  rangeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: AppTypography.inter(fontSize: 11, weight: FontWeight.w500, color: const Color(0xFF999999)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 128,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: _yAxisW,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: yLabels
                        .map((l) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  l,
                                  maxLines: 1,
                                  softWrap: false,
                                  style: AppTypography.inter(fontSize: 10, color: kSec),
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ),
                Expanded(
                  child: loading
                      ? Center(child: CircularProgressIndicator(color: barColor, strokeWidth: 2))
                      : CustomPaint(painter: createPainter(values), child: const SizedBox.expand()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: _yAxisW),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: xLabels
                  .map((l) => Expanded(
                        child: Text(
                          l,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: AppTypography.inter(fontSize: 10, color: kSec),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
