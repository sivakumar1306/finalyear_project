import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_typography.dart';

// Tier labels for display only — the actual score comes from the native
// FallRiskAnalyzer (see BleProvider.getFallRiskScore), not computed here.
enum FallTier { low, medium, high }

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: AppTypography.inter(
          color: Colors.white.withValues(alpha: 0.35),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class HeroCard extends StatelessWidget {
  final FallTier tier;
  final String message;
  final VoidCallback onIgnore;

  const HeroCard({
    super.key,
    required this.tier,
    required this.message,
    required this.onIgnore,
  });

  @override
  Widget build(BuildContext context) {
    final isHigh = tier == FallTier.high;
    final accent = isHigh ? AppTheme.hrColor : AppTheme.tempColor;
    final title = isHigh ? 'You might fall soon...' : 'We are concerned ...';
    final body = isHigh
        ? 'We have detected multiple signs that you might fall down in the next 2-3 minutes. '
              'Take a seat and rest until you feel steady.'
        : message;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.25), width: 0.5),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.30), AppTheme.card],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FALL PREDICTION',
            style: AppTypography.inter(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: AppTypography.inter(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: AppTypography.inter(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: onIgnore,
              child: Text(
                'ignore',
                style: AppTypography.inter(
                  color: AppTheme.danger,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const ActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.div),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: AppTypography.inter(color: Colors.white, fontSize: 14),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.3),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class FallHistorySheet extends StatelessWidget {
  final List<Map<String, dynamic>> events;
  const FallHistorySheet({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, HH:mm');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fall history',
              style: AppTypography.inter(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Logged by the on-device motion detector — real events only.',
              style: AppTypography.inter(color: AppTheme.textSec, fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (events.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No fall events logged yet.',
                  style: AppTypography.inter(
                    color: AppTheme.textSec,
                    fontSize: 13,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: events.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final e = events[i];
                    final detectedAt = (e['detectedAt'] as num?)?.toInt() ?? 0;
                    final confidence = ((e['confidence'] as num?) ?? 0)
                        .toDouble();
                    final corroborated = e['corroborated'] as bool? ?? false;
                    final source =
                        e['corroborationSource'] as String? ?? 'none';
                    final eventType = e['eventType'] as String? ?? 'DETECTED';
                    final isPrediction = eventType == 'PREDICTED';
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.div),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isPrediction
                                ? Icons.trending_up_rounded
                                : (corroborated
                                      ? Icons.warning_amber_rounded
                                      : Icons.help_outline_rounded),
                            color: isPrediction
                                ? AppTheme.tempColor
                                : (corroborated
                                      ? AppTheme.hrColor
                                      : AppTheme.textSec),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  detectedAt > 0
                                      ? fmt.format(
                                          DateTime.fromMillisecondsSinceEpoch(
                                            detectedAt,
                                          ),
                                        )
                                      : 'Unknown time',
                                  style: AppTypography.inter(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  isPrediction
                                      ? 'Predicted fall risk'
                                      : (corroborated
                                            ? 'Confirmed by $source'
                                            : 'Not confirmed'),
                                  style: AppTypography.inter(
                                    color: AppTheme.textSec,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${(confidence * 100).toInt()}%',
                            style: AppTypography.inter(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
