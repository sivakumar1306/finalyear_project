import 'dart:ui' as dart_ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/fall_prediction/fall_prediction_provider.dart';
import '../../providers/ble_provider.dart';
import '../../models/fall_prediction/engine_outputs.dart';
import '../../theme/app_theme.dart';
import '../app_typography.dart';
import '../../utils/formatters.dart';

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

        final score = result.frs24.value.round();
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
                Flexible(
                  child: Text(
                    'FALL RISK SCORE',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.inter(
                      color: AppTheme.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
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
                        value: bleProvider.todayAvgHr > 0 ? bleProvider.todayAvgHr.toString() : '--',
                        unit: 'bpm',
                        valueColor: AppTheme.hrColor,
                        showChevron: true,
                        trailing: const Icon(Icons.waves_rounded, color: AppTheme.hrColor, size: 28),
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
                        value: bleProvider.latestTempC > 0 ? bleProvider.latestTempC.fixed2() : '--',
                        unit: '°C',
                        valueColor: AppTheme.tempColor,
                        subtitle: bleProvider.latestTempC <= 0 ? 'No data' : (bleProvider.latestTempC < 36.0 ? 'Low' : (bleProvider.latestTempC <= 37.2 ? 'Normal' : 'Elevated')),
                        subtitleColor: AppTheme.tempColor,
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
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.glassCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.glassBorder, width: 0.5),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Glassmorphism blur orb (bottom right)
          Positioned(
            bottom: -56,
            right: -56,
            child: RepaintBoundary(
              child: ImageFiltered(
                imageFilter: dart_ui.ImageFilter.blur(sigmaX: 60, sigmaY: 60, tileMode: TileMode.decal),
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: valueColor.withAlpha(70), // orbAlpha equivalent
                  ),
                ),
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
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
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: RichText(
              maxLines: 1,
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
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.inter(
                color: subtitleColor ?? valueColor,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    ),
  ],
),
    );
  }
}
