import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'app_typography.dart';
import 'glass_card.dart';

/// Single glass card shown when a detail day has no data.
/// Reuses `GlassCard` (DESIGN.md: glass 6% + border 9% + blur 28 + 20 radius + 16 pad)
/// so no new design tokens are introduced.
class NotEnoughDataCard extends StatelessWidget {
  final String metric;
  final DateTime? date;
  final bool isConnected;
  final VoidCallback? onMeasure;
  final String? measureLabel;

  const NotEnoughDataCard({
    super.key,
    required this.metric,
    this.date,
    this.isConnected = false,
    this.onMeasure,
    this.measureLabel,
  });

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final dateStr = date != null ? _fmt(date!) : 'this day';
    return GlassCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insights_rounded, size: 28, color: AppTheme.textTertiary.withValues(alpha: 0.6)),
          const SizedBox(height: 10),
          Text('NOT ENOUGH DATA',
            style: AppTypography.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textTertiary, letterSpacing: 1.2)),
          const SizedBox(height: 6),
          Text('No $metric records for $dateStr — wear your ring and ${onMeasure != null ? 'tap Measure' : 'measure'} to fill this day.',
            textAlign: TextAlign.center, style: AppTypography.inter(fontSize: 13, color: AppTheme.textSec, height: 1.4)),
          if (!isConnected) ...[
            const SizedBox(height: 8),
            Text('Connect your ring or pull to refresh.',
              textAlign: TextAlign.center, style: AppTypography.inter(fontSize: 11, color: AppTheme.textTertiary)),
          ],
          if (onMeasure != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: isConnected ? onMeasure : null,
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.03),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  foregroundColor: AppTheme.gold,
                ),
                child: Text(measureLabel ?? 'Measure now',
                  style: AppTypography.inter(fontSize: 13, fontWeight: FontWeight.w600, color: isConnected ? AppTheme.gold : AppTheme.textTertiary)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Variant for trend section when 7-day history is empty.
class NotEnoughTrendDataCard extends StatelessWidget {
  final String metric;
  const NotEnoughTrendDataCard({super.key, required this.metric});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.show_chart_rounded, size: 24, color: AppTheme.textTertiary.withValues(alpha: 0.6)),
          const SizedBox(height: 10),
          Text('NOT ENOUGH TREND DATA',
            style: AppTypography.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textTertiary, letterSpacing: 1.2)),
          const SizedBox(height: 6),
          Text('No $metric trend yet — 2+ days of data are needed. Keep wearing your ring.',
            textAlign: TextAlign.center, style: AppTypography.inter(fontSize: 13, color: AppTheme.textSec, height: 1.4)),
        ],
      ),
    );
  }
}
