import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/fall_prediction/fall_prediction_provider.dart';
import '../../models/fall_prediction/engine_outputs.dart';
import '../../theme/app_theme.dart';
import '../app_typography.dart';

class FallRiskScoreCard extends StatelessWidget {
  const FallRiskScoreCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FallPredictionProvider>(
      builder: (context, provider, child) {
        final result = provider.currentResult;
        if (result == null) {
          return Card(
            color: AppTheme.card,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppTheme.div, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                'Calculating Risk Score...',
                style: AppTypography.inter(color: AppTheme.textSec),
              ),
            ),
          );
        }

        Color riskColor;
        String riskText;
        switch (result.frs24.value.riskBand) {
          case FrsRiskBand.low:
            riskColor = AppTheme.success;
            riskText = 'LOW RISK';
            break;
          case FrsRiskBand.moderate:
            riskColor = AppTheme.stressColor;
            riskText = 'MODERATE RISK';
            break;
          case FrsRiskBand.high:
            riskColor = AppTheme.hrColor;
            riskText = 'HIGH RISK';
            break;
        }

        return Card(
          color: AppTheme.card,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppTheme.div, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: Text(
                        'Fall Risk Score',
                        style: AppTypography.inter(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Align(
                      alignment: Alignment.centerRight,
                      child: Icon(Icons.chevron_right_rounded, color: AppTheme.textSec, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (result.q.q < 10.0)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.card2,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.div),
                    ),
                    child: Text(
                      'We don\'t have enough data to calculate your score today.',
                      textAlign: TextAlign.center,
                      style: AppTypography.inter(
                        color: AppTheme.textSec,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )
                else ...[
                  Text(
                    result.frs24.value.toStringAsFixed(1),
                    style: AppTypography.inter(
                      fontSize: 48,
                      fontWeight: FontWeight.w300,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '30-Day Trend: ${result.frs30.value.toStringAsFixed(1)}',
                    style: AppTypography.inter(
                      color: AppTheme.textSec,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: riskColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: riskColor.withAlpha(76)),
                    ),
                    child: Text(
                      riskText,
                      style: AppTypography.inter(
                        color: riskColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Data Confidence: ${result.q.q.toStringAsFixed(0)}%',
                  style: AppTypography.inter(
                    color: AppTheme.textSec,
                    fontSize: 14,
                  ),
                ),

              ],
            ),
          ),
        );
      },
    );
  }
}
