import 'package:flutter/material.dart';
import '../../models/fall_prediction/engine_outputs.dart';
import '../../theme/app_theme.dart';

class AttributionReportCard extends StatelessWidget {
  final ExplainabilityPayload payload;

  const AttributionReportCard({
    super.key,
    required this.payload,
  });

  String _formatRiskBand(FrsRiskBand band) {
    switch (band) {
      case FrsRiskBand.low:
        return 'Low';
      case FrsRiskBand.moderate:
        return 'Moderate';
      case FrsRiskBand.high:
        return 'High';
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalDrop = payload.hsiBaseline - payload.hsiAdj;
    
    return Card(
      elevation: 0,
      color: AppTheme.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.div),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            const Text(
              'Attribution Report',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // HSI Base vs Baseline
            RichText(
              text: TextSpan(
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                children: [
                  const TextSpan(text: 'HSI_base: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: '${payload.hsiBase} / 100 '),
                  TextSpan(
                    text: '(personal baseline: ${payload.hsiBaseline})',
                    style: const TextStyle(color: AppTheme.textSec, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            
            // HSI Adj
            RichText(
              text: TextSpan(
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                children: [
                  const TextSpan(text: 'HSI_adj: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: '${payload.hsiAdj} / 100 '),
                  TextSpan(
                    text: "(today's context-weighted score)",
                    style: const TextStyle(color: AppTheme.textSec, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            
            // Deltas
            Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('→ ', style: TextStyle(color: AppTheme.textSec)),
                      Expanded(
                        child: Text(
                          '${payload.attributionDeltas.contextShiftDelta} points of the $totalDrop-point drop from baseline is attributable to context reweighting (e.g., environmental or lifecycle shifts), not a physiological change',
                          style: const TextStyle(color: AppTheme.textSec, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('→ ', style: TextStyle(color: AppTheme.textSec)),
                      Expanded(
                        child: Text(
                          '${payload.attributionDeltas.physiologicalDelta} points is attributable to a genuine physiological/behavioral decline',
                          style: const TextStyle(color: AppTheme.textSec, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // FRS
            RichText(
              text: TextSpan(
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                children: [
                  const TextSpan(text: 'FRS-24: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: '${payload.frs24Score} / 100 '),
                  TextSpan(text: '(${_formatRiskBand(payload.frs24Band)}) '),
                  TextSpan(
                    text: '- horizon: next 24 hours',
                    style: const TextStyle(color: AppTheme.textSec, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            
            // Contributors & Coverage
            Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Top contributors: ${payload.topContributors.join(", ")}',
                    style: const TextStyle(color: AppTheme.textSec, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Coverage (Q): ${(payload.coverageScoreQ / 100.0).toStringAsFixed(2)} - ${payload.coverageDetails.join(", ")}',
                    style: const TextStyle(color: AppTheme.textSec, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Recommendation
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.gold.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.gold.withAlpha(50)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline, color: AppTheme.gold, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                        children: [
                          const TextSpan(text: 'Recommendation: ', style: TextStyle(fontWeight: FontWeight.bold)),
                          TextSpan(text: payload.recommendationAction),
                        ],
                      ),
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
}
