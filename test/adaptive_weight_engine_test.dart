import 'package:flutter_test/flutter_test.dart';
import 'package:qring_flutter/models/fall_prediction/context_factors.dart';
import 'package:qring_flutter/services/fall_prediction/adaptive_weight_engine.dart';

void main() {
  group('AdaptiveWeightEngine', () {
    test('neutral context keeps relative base weights', () {
      final base = {
        'physiological': 0.20,
        'recovery': 0.20,
        'motion': 0.40,
        'womens_health': 0.20,
      };
      final w = AdaptiveWeightEngine.calculateAdaptiveWeights(
        base,
        ContextFactors(),
      );
      final sum = w.values.fold(0.0, (a, b) => a + b);
      expect(sum, closeTo(1.0, 1e-9));
      expect(w['motion'], closeTo(0.40, 1e-9));
      expect(w['physiological'], closeTo(0.20, 1e-9));
    });

    test('age boosts physiological after normalize', () {
      final base = {
        'physiological': 0.25,
        'recovery': 0.25,
        'motion': 0.25,
        'womens_health': 0.25,
      };
      final w = AdaptiveWeightEngine.calculateAdaptiveWeights(
        base,
        ContextFactors(age: 2.0),
      );
      expect(w.values.fold(0.0, (a, b) => a + b), closeTo(1.0, 1e-9));
      expect(w['physiological']!, greaterThan(w['motion']!));
      expect(w['physiological']!, greaterThan(w['recovery']!));
    });

    test('zero total base yields zeros without divide-by-zero', () {
      final w = AdaptiveWeightEngine.calculateAdaptiveWeights(
        {'physiological': 0, 'recovery': 0},
        ContextFactors(),
      );
      expect(w['physiological'], 0);
      expect(w['recovery'], 0);
    });

    test('sleep debt multiplies recovery only', () {
      final base = {
        'physiological': 0.5,
        'recovery': 0.5,
      };
      final w = AdaptiveWeightEngine.calculateAdaptiveWeights(
        base,
        ContextFactors(sleepDebt: 2.0, stressTrend: 1.0),
      );
      expect(w['recovery']!, greaterThan(w['physiological']!));
      expect(w.values.fold(0.0, (a, b) => a + b), closeTo(1.0, 1e-9));
    });
  });
}
