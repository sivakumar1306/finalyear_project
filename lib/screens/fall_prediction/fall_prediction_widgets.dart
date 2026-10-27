import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/fall_prediction/demo_patients.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/glass_card.dart';

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

/// Shown above the score while a demo patient is open: who it is, how the
/// score changed from the user's own, and a way to add a fall or go back.
class DemoPatientCard extends StatelessWidget {
  final DemoPatient patient;
  final double? ownScore;
  final double? demoScore;
  final VoidCallback onAddFall;
  final VoidCallback onBack;
  const DemoPatientCard({
    super.key,
    required this.patient,
    required this.ownScore,
    required this.demoScore,
    required this.onAddFall,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final own = ownScore?.round();
    final theirs = demoScore?.round();
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DEMO PATIENT · SYNTHETIC DATA',
            style: AppTypography.inter(
              color: AppTheme.gold,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            patient.name,
            style: AppTypography.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            patient.summary,
            style: AppTypography.inter(color: AppTheme.textSec, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Text(
            theirs == null
                ? 'Calculating…'
                : own == null
                    ? '${patient.name}\'s score: $theirs'
                    : 'Your score $own  →  ${patient.name} $theirs',
            style: AppTypography.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _DemoButton(label: 'Simulate a fall', color: AppTheme.gold, onPressed: onAddFall)),
              const SizedBox(width: 8),
              Expanded(child: _DemoButton(label: 'Back to my data', color: Colors.white70, onPressed: onBack)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DemoButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;
  const _DemoButton({required this.label, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.03),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(vertical: 12),
        foregroundColor: color,
      ),
      child: Text(label, style: AppTypography.inter(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
