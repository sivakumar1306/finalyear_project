import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/fall_prediction/fall_prediction_provider.dart';
import '../../providers/ble_provider.dart';
import '../../models/fall_prediction/engine_outputs.dart';
import '../../theme/app_theme.dart';
import '../app_typography.dart';

class FallRiskScoreCard extends StatelessWidget {
  final VoidCallback? onTapRiskDetails;
  final VoidCallback? onTapHeartRate;
  final VoidCallback? onTapTemperature;

  const FallRiskScoreCard({
    super.key,
    this.onTapRiskDetails,
    this.onTapHeartRate,
    this.onTapTemperature,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer2<FallPredictionProvider, BleProvider>(
      builder: (context, provider, bleProvider, child) {
        final result = provider.currentResult;
        if (result == null) {
          return const Center(
            child: Text('Calculating Risk Score...', style: TextStyle(color: Colors.white)),
          );
        }

        if (result.q.q < 10.0) {
          return Container(
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
          );
        }

        final score = result.frs24.value.toInt();
        String riskText;
        switch (result.frs24.value.riskBand) {
          case FrsRiskBand.low:
            riskText = 'Low chance of falling';
            break;
          case FrsRiskBand.moderate:
            riskText = 'Moderate chance of falling';
            break;
          case FrsRiskBand.high:
            riskText = 'High chance of falling';
            break;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'FALL RISK SCORE',
                  style: AppTypography.inter(
                    color: AppTheme.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                if (onTapRiskDetails != null)
                  GestureDetector(
                    onTap: onTapRiskDetails,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      color: Colors.transparent, // expand hit area
                      child: const Icon(Icons.chevron_right_rounded, color: AppTheme.textSec, size: 20),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              score.toString(),
              style: AppTypography.inter(
                color: Colors.white,
                fontSize: 48,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              riskText,
              style: AppTypography.inter(
                color: AppTheme.textSec,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: onTapHeartRate,
                      child: _MiniCard(
                        title: 'Heart Rate',
                        value: bleProvider.todayMaxHr > 0 ? bleProvider.todayMaxHr.toString() : '--',
                        unit: 'bpm',
                        valueColor: const Color(0xFFC96B6B),
                        showChevron: true,
                        trailing: const Icon(Icons.waves_rounded, color: Color(0xFFC96B6B), size: 28),
                        subtitle: bleProvider.todayMinHr > 0 && bleProvider.todayMaxHr > 0 
                            ? 'Range: ${bleProvider.todayMinHr}-${bleProvider.todayMaxHr}bpm'
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: onTapTemperature,
                      child: _MiniCard(
                        title: 'Temperature',
                        value: bleProvider.latestTempC > 0 ? bleProvider.latestTempC.toStringAsFixed(1) : '--',
                        unit: '°C',
                        valueColor: const Color(0xFFE3B76A),
                        subtitle: bleProvider.latestTempC <= 0 ? 'No data' : (bleProvider.latestTempC < 36.0 ? 'Low' : (bleProvider.latestTempC <= 37.2 ? 'Normal' : 'Elevated')),
                        subtitleColor: const Color(0xFFE3B76A),
                        showChevron: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MiniCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final Color valueColor;
  final String? subtitle;
  final Color? subtitleColor;
  final bool showChevron;
  final Widget? trailing;

  const _MiniCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.valueColor,
    this.subtitle,
    this.subtitleColor,
    this.showChevron = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x0FFFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x17FFFFFF), width: 0.5),
        gradient: RadialGradient(
          center: const Alignment(0.8, -0.8),
          radius: 1.2,
          colors: [
            valueColor.withAlpha(60),
            const Color(0x0FFFFFFF),
          ],
          stops: const [0.0, 1.0],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: AppTypography.inter(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (showChevron)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chevron_right_rounded, color: Colors.white70, size: 16),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (trailing != null) Align(alignment: Alignment.centerRight, child: trailing),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: AppTypography.inter(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: AppTypography.inter(
                    color: AppTheme.textSec,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: AppTypography.inter(
                color: subtitleColor ?? valueColor,
                fontSize: 12,
              ),
            ),
          ]
        ],
      ),
    );
  }
}
