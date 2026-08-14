import 'package:flutter/material.dart';
import '../../models/fall_prediction/engine_outputs.dart';
import '../../theme/app_theme.dart';

class AttributionReportCard extends StatelessWidget {
  final ExplainabilityPayload payload;
  final double frs30Score;
  final double frs24Value;

  const AttributionReportCard({
    super.key,
    required this.payload,
    required this.frs30Score,
    required this.frs24Value,
  });

  Color _getRiskColor(FrsRiskBand band) {
    switch (band) {
      case FrsRiskBand.low:
        return AppTheme.success;
      case FrsRiskBand.moderate:
        return AppTheme.focus;
      case FrsRiskBand.high:
        return AppTheme.danger;
    }
  }

  String _formatRiskBand(FrsRiskBand band) {
    switch (band) {
      case FrsRiskBand.low:
        return 'Low Risk';
      case FrsRiskBand.moderate:
        return 'Moderate Risk';
      case FrsRiskBand.high:
        return 'High Risk';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.div),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Section - Fall Risk Score Breakdown
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.analytics_rounded, color: AppTheme.gold, size: 22),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Fall Risk Score Breakdown',
                          style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildRiskBadge(payload.frs24Band),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Main Score Overview
                  Center(
                    child: Column(
                      children: [
                        const Text(
                          'Fall Risk Score',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          frs24Value.toStringAsFixed(1),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 56,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Fall Risk Factors
                  if (!(payload.frsContributors.length == 1 && payload.frsContributors.first == 'Low Risk Factors')) ...[
                    const Text(
                      'Fall Risk Factors',
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: payload.frsContributors.map((c) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.card2,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          c,
                          style: const TextStyle(color: AppTheme.textSec, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      )).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],
                  
                  // Score Breakdown
                  if (payload.frsBreakdown.isNotEmpty) ...[
                    const Text(
                      'Score Breakdown',
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    ...payload.frsBreakdown.entries.map((entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: _buildDeltaRow(
                        icon: Icons.add_circle_outline_rounded,
                        color: AppTheme.danger,
                        text: '+${entry.value} points from ${entry.key}.',
                      ),
                    )),
                    const SizedBox(height: 12),
                  ],

                  // Coverage Details
                  ...payload.coverageDetails.map((detail) => Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded, color: AppTheme.textSec, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            detail,
                            style: const TextStyle(color: AppTheme.textSec, fontSize: 13, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),
            
            // Recommendation Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _getRiskColor(payload.frs24Band).withValues(alpha: 0.1),
                border: Border(top: BorderSide(color: _getRiskColor(payload.frs24Band).withValues(alpha: 0.2))),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    payload.frs24Band == FrsRiskBand.low ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
                    color: _getRiskColor(payload.frs24Band),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recommendation',
                          style: TextStyle(color: _getRiskColor(payload.frs24Band), fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          payload.recommendationAction,
                          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRiskBadge(FrsRiskBand band) {
    final color = _getRiskColor(band);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.speed_rounded, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            _formatRiskBand(band),
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildDeltaRow({required IconData icon, required Color color, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 14),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: AppTheme.textSec, fontSize: 13, height: 1.4),
          ),
        ),
      ],
    );
  }
}
