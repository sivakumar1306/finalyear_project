import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'app_typography.dart';

/// Small metric summary card: a label and a value with its unit.
class MetricStatCard extends StatelessWidget {
  const MetricStatCard({
    super.key,
    required this.label,
    required this.value,
    this.unit = '',
    this.caption,
    this.captionColor,
  });

  final String label;
  final String value;
  final String unit;

  /// Optional status line below the value (e.g. a stress level label).
  final String? caption;
  final Color? captionColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.div),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTypography.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppTheme.textTertiary,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: AppTypography.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                if (unit.isNotEmpty)
                  Text(
                    unit,
                    style: AppTypography.inter(
                      fontSize: 11,
                      color: AppTheme.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 6),
            Text(
              caption!,
              style: AppTypography.inter(
                fontSize: 11,
                color: captionColor ?? AppTheme.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}