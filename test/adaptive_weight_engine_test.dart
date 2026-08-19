import 'package:flutter_test/flutter_test.dart';
import 'package:sundr/models/fall_prediction/context_factors.dart';
import 'package:sundr/services/fall_prediction/adaptive_weight_engine.dart';

void main() {
  group('AdaptiveWeightEngine', () {
    test('neutral context keeps relative base weights', () {
      final base = {
        'physiological': 0.20,
        'recovery': 0.20,
        'motion': 0.40,
        'womens_health': 0.20,
      };
      final multipliers = {
        'physiological': 1.0,
        'recovery': 1.0,
        'motion': 1.0,
        'womens_health': 1.0,
      };
      final w = AdaptiveWeightEngine.renormalizeWeights(
        base,
        multipliers,
      );
      final sum = w.values.fold(0.0, (a, b) => a + b);
      expect(sum, closeTo(1.0, 1e-9));
      expect(w['motion'], closeTo(0.40, 1e-9));
      expect(w['physiological'], closeTo(0.20, 1e-9));
    });

    test('age boosts physiological after normalize', () {
      final w = AdaptiveWeightEngine.getHsiGlobalWeights(
        ContextFactors(age: 2.0),
      );
      expect(w.values.fold(0.0, (a, b) => a + b), closeTo(1.0, 1e-9));
      expect(w['physiological']!, greaterThan(0.35)); // Base is 0.35, should increase
      expect(w['physiological']!, greaterThan(w['motion']!));
    });

    test('zero total base yields zeros without divide-by-zero', () {
      final w = AdaptiveWeightEngine.renormalizeWeights(
        {'physiological': 0.0, 'recovery': 0.0},
        {'physiological': 1.0, 'recovery': 1.0},
      );
      expect(w['physiological'], 0.0);
      expect(w['recovery'], 0.0);
    });

    test('sleep debt multiplies recovery only', () {
      final w = AdaptiveWeightEngine.getHsiGlobalWeights(
        ContextFactors(sleepDebt: 2.0, stressTrend: 1.0),
      );
      expect(w['recovery']!, greaterThan(0.30)); // Base is 0.30, should increase
      expect(w.values.fold(0.0, (a, b) => a + b), closeTo(1.0, 1e-9));
    });
  });
}
