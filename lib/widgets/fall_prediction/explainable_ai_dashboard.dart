import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/fall_prediction/fall_prediction_provider.dart';
import '../../theme/app_theme.dart';
import '../app_typography.dart';

class ExplainableAIDashboard extends StatelessWidget {
  const ExplainableAIDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FallPredictionProvider>(
      builder: (context, provider, child) {
        final result = provider.currentResult;
        if (result == null) {
          return const SizedBox.shrink();
        }

        final chain = result.reasoningChain;

        return Card(
          color: AppTheme.card,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppTheme.div, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.psychology, color: AppTheme.spo2Color, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'AI Reasoning',
                      style: AppTypography.inter(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: AppTheme.div, height: 1),
                const SizedBox(height: 16),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: chain.length,
                  separatorBuilder: (context, index) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Center(
                      child: Icon(Icons.arrow_downward_rounded, size: 18, color: AppTheme.textSec)
                    ),
                  ),
                  itemBuilder: (context, index) {
                    final item = chain[index];
                    bool isRecommendation = item.startsWith('Recommendation:');
                    
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isRecommendation ? AppTheme.spo2Color.withAlpha(25) : Colors.white.withAlpha(10),
                        borderRadius: BorderRadius.circular(12),
                        border: isRecommendation ? Border.all(color: AppTheme.spo2Color.withAlpha(76)) : Border.all(color: Colors.transparent),
                      ),
                      child: Text(
                        item,
                        style: AppTypography.inter(
                          fontWeight: isRecommendation ? FontWeight.w600 : FontWeight.w400,
                          color: isRecommendation ? AppTheme.spo2Color : Colors.white,
                          fontSize: 14,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
