import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_typography.dart';

class CycleChatCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback? onTap;

  const CycleChatCard({
    super.key,
    required this.data,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final periodStart = data['period_start'] as String? ?? 'Unknown';
    final cycleLength = (data['cycle_length'] as num? ?? 28).toInt();
    final periodLength = (data['period_length'] as num? ?? 5).toInt();
    final currentDay = (data['current_day'] as num? ?? 1).toInt();
    final phase = data['phase'] as String? ?? 'Follicular Phase';
    final daysUntilNext = (data['days_until_next'] as num? ?? cycleLength).toInt();

    const accentColor = AppTheme.womenColor;
    final progress = (currentDay / cycleLength).clamp(0.0, 1.0);

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.white04,
                border: Border.all(
                  color: AppTheme.glassButtonBorder,
                  width: 0.5,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.3),
                            width: 0.5,
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.calendar_today_rounded,
                            size: 13,
                            color: accentColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'CYCLE & MENSTRUAL HEALTH',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                            color: AppTheme.white60,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Day $currentDay',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.inter(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.white96,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              phase,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: accentColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'In $daysUntilNext days',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: AppTypography.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.white92,
                              ),
                            ),
                            Text(
                              'Next Period',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.inter(
                                fontSize: 10.5,
                                color: AppTheme.white40,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      children: [
                        Container(
                          height: 6,
                          width: double.infinity,
                          color: AppTheme.white10,
                        ),
                        FractionallySizedBox(
                          widthFactor: progress,
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  accentColor.withValues(alpha: 0.6),
                                  accentColor,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(child: _StatBadge(label: 'Start Date', value: periodStart)),
                      Expanded(child: _StatBadge(label: 'Cycle Length', value: '${cycleLength}d')),
                      Expanded(child: _StatBadge(label: 'Period Length', value: '${periodLength}d')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;

  const _StatBadge({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.inter(
            fontSize: 9.5,
            color: AppTheme.white40,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.inter(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: AppTheme.white85,
          ),
        ),
      ],
    );
  }
}
