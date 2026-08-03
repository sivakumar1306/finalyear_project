import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/fall_prediction/fall_prediction_provider.dart';
import '../../models/fall_prediction/prediction_result.dart';
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
        switch (result.riskLevel) {
          case RiskClassification.low:
            riskColor = AppTheme.success;
            riskText = 'LOW RISK';
            break;
          case RiskClassification.moderate:
            riskColor = AppTheme.stressColor;
            riskText = 'MODERATE RISK';
            break;
          case RiskClassification.high:
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
                Text(
                  'Fall Confidence Score',
                  style: AppTypography.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(
                  result.fcs.toStringAsFixed(1),
                  style: AppTypography.inter(
                    fontSize: 48,
                    fontWeight: FontWeight.w300,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            ),
          ),
        );
      },
    );
  }
}
