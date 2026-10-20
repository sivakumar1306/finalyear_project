import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vital_monitoring/models/fall_prediction/engine_outputs.dart';
import 'package:vital_monitoring/services/fall_prediction/fall_prediction_engine.dart';

void main() {
  test('layer weights are ln(OR) / sum ln(OR) from the published odds ratios', () {
    const ors = {'fh': 2.8, 'mo': 2.1, 'p': 1.73, 'rc': 1.27};
    final total = ors.values.map(log).reduce((a, b) => a + b);
    double lambda(String k) => log(ors[k]!) / total;

    expect(FallPredictionEngine.lambdaFallHistory, closeTo(lambda('fh'), 0.001));
    expect(FallPredictionEngine.lambdaMotion, closeTo(lambda('mo'), 0.001));
    expect(FallPredictionEngine.lambdaPhysiology, closeTo(lambda('p'), 0.001));
    expect(FallPredictionEngine.lambdaRecovery, closeTo(lambda('rc'), 0.001));
  });

  test('tiers: LOW < 40, MODERATE 40-69, HIGH >= 70', () {
    expect(0.0.riskBand, FrsRiskBand.low);
    expect(39.9.riskBand, FrsRiskBand.low);
    expect(40.0.riskBand, FrsRiskBand.moderate);
    expect(69.9.riskBand, FrsRiskBand.moderate);
    expect(70.0.riskBand, FrsRiskBand.high);
    expect(100.0.riskBand, FrsRiskBand.high);
  });
}
