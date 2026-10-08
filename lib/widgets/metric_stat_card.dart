import 'dart:ui';
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.glassCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.glassBorder, width: 0.5),
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.inter(
                fontSize: 11,
                color: captionColor ?? AppTheme.textTertiary,
              ),
            ),
          ],
        ],
          ),
        ),
      ),
    );
  }
}