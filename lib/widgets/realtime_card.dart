import 'package:flutter/material.dart';
import 'app_typography.dart';
import 'glass_card.dart';

class RealtimeCard extends StatelessWidget {
  final String label;
  final String unitLabel;
  final int latestValue;
  final String valueLabel;
  final bool measuring;
  final bool enabled;
  final Color accentColor;
  final VoidCallback? onTap;

  const RealtimeCard({
    super.key,
    required this.label,
    required this.unitLabel,
    required this.latestValue,
    required this.valueLabel,
    required this.measuring,
    required this.enabled,
    required this.accentColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayText = measuring
        ? '···'
        : latestValue > 0
            ? '$latestValue'
            : '--';

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: AppTypography.inter(14, weight: FontWeight.w500)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    displayText,
                    style: AppTypography.inter(
                      15,
                      weight: FontWeight.w600,
                      color: measuring || latestValue > 0 ? Colors.white : kSec2,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(unitLabel, style: AppTypography.inter(11, color: kSec)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: enabled ? onTap : null,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2E2E2E)),
              ),
              child: Center(
                child: measuring
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: enabled ? accentColor : kSec,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Click to start measurement',
                        style: AppTypography.inter(
                          14,
                          weight: FontWeight.w500,
                          color: enabled ? Colors.white70 : kSec,
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
