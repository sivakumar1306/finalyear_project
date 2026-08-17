import 'package:flutter/material.dart';
import '../widgets/app_typography.dart';
import '../widgets/glass_card.dart';

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppTypography.inter(fontSize: 10, weight: FontWeight.w600, color: kSec, letterSpacing: 0.7)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: AppTypography.inter(fontSize: 17, weight: FontWeight.w600)),
              const SizedBox(width: 4),
              Text(unit, style: AppTypography.inter(fontSize: 11, color: kSec)),
            ],
          ),
        ],
      ),
    );
  }
}
