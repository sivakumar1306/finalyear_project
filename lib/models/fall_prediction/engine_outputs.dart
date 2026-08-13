class HsiBase {
  final double value;

  HsiBase(this.value) {
    assert(value >= 0.0 && value <= 100.0, 'HSI Base must be between 0 and 100');
  }
}

class HsiAdj {
  final double value;

  HsiAdj(this.value) {
    assert(value >= 0.0 && value <= 100.0, 'HSI Adj must be between 0 and 100');
  }
}

enum FrsRiskBand { low, moderate, high }

extension FrsRiskBandClassification on double {
  FrsRiskBand get riskBand {
    if (this <= 30.0) return FrsRiskBand.low;
    if (this <= 60.0) return FrsRiskBand.moderate;
    return FrsRiskBand.high;
  }
}

class Frs24 {
  final double value;

  Frs24(this.value) {
    assert(value >= 0.0 && value <= 100.0, 'FRS-24 must be between 0 and 100');
  }
}

class Frs30 {
  final double value;

  Frs30(this.value) {
    assert(value >= 0.0 && value <= 100.0, 'FRS-30 must be between 0 and 100');
  }
}

class PredictionHorizon {
  final Duration tau; // e.g., 24 hours, 7 days

  PredictionHorizon(this.tau);
}

class CoverageScore {
  final double q;

  CoverageScore(this.q) {
    assert(q >= 0.0 && q <= 100.0, 'Coverage Score must be between 0 and 100');
  }
}

class AttributionDeltas {
  final int contextShiftDelta;
  final int physiologicalDelta;

  AttributionDeltas({
    required this.contextShiftDelta,
    required this.physiologicalDelta,
  });
}

class ExplainabilityPayload {
  final int hsiBase;
  final int hsiBaseline;
  final int hsiAdj;
  final AttributionDeltas attributionDeltas;
  final int frs24Score;
  final FrsRiskBand frs24Band;
  final List<String> topContributors;
  final List<String> frsContributors;
  final double coverageScoreQ;
  final List<String> coverageDetails;
  final String recommendationAction;

  final Map<String, int> frsBreakdown;

  ExplainabilityPayload({
    required this.hsiBase,
    required this.hsiBaseline,
    required this.hsiAdj,
    required this.attributionDeltas,
    required this.frs24Score,
    required this.frs24Band,
    required this.topContributors,
    required this.frsContributors,
    required this.coverageScoreQ,
    required this.coverageDetails,
    required this.recommendationAction,
    required this.frsBreakdown,
  });
}
