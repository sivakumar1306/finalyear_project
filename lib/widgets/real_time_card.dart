import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'app_typography.dart';

/// Real-time measurement card: a live value with a unit and a tap target that
/// starts a ring measurement (spinner while measuring).
class RealTimeCard extends StatelessWidget {
  const RealTimeCard({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.accent,
    required this.measuring,
    required this.enabled,
    this.onTap,
  });

  final String title;
  final String value;
  final String unit;
  final Color accent;
  final bool measuring;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final highlighted = value != '--';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.div),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: AppTypography.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value,
                    style: AppTypography.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: highlighted ? Colors.white : AppTheme.textSec,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    unit,
                    style: AppTypography.inter(
                      fontSize: 11,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? onTap : null,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.surfaceMid,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.dividerSoft),
              ),
              child: Center(
                child: measuring
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: accent,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Click to start measurement',
                        style: AppTypography.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: enabled ? Colors.white70 : AppTheme.textTertiary,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}