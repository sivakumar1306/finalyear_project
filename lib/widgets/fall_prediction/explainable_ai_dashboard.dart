import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/fall_prediction/fall_prediction_provider.dart';
import 'attribution_report_card.dart';

class ExplainableAIDashboard extends StatelessWidget {
  const ExplainableAIDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FallPredictionProvider>(
      builder: (context, provider, child) {
        final result = provider.currentResult;
        if (result == null || result.explainability == null) {
          return const SizedBox.shrink();
        }

        return AttributionReportCard(
          payload: result.explainability!,
          frs30Score: result.frs30.value,
          frs24Value: result.frs24.value,
        );
      },
    );
  }
}
