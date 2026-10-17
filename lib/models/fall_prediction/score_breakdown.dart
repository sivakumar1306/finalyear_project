/// Measure-level explanation of one Fall Risk Score computation.
///
/// Built by [FallPredictionEngine] from the same normalisation functions and
/// weights that produce the score, so every number shown on the score-details
/// screen adds up to the score itself:
///
///   layer score  = Σ measure.share × measure.subScore   (measured only)
///   FRS-24       = Σ layer.lambda × (100 − layer.score) + λ_FH × FH_norm
library;

class MeasureDetail {
  final String key;
  final String label;

  /// Today's reading, formatted with its unit (e.g. "72 bpm").
  final String? reading;

  /// The personal baseline or reference it is compared against.
  final String? reference;

  /// 0–100, higher = more stable. Null when the measure was not available.
  final double? subScore;

  /// Base weight inside its layer (before renormalisation).
  final double baseWeight;

  /// Share of the layer score after renormalising over measured inputs.
  /// 0 when not measured.
  final double share;

  /// One-line description of how the reading becomes a 0–100 sub-score.
  final String method;

  const MeasureDetail({
    required this.key,
    required this.label,
    required this.reading,
    required this.reference,
    required this.subScore,
    required this.baseWeight,
    required this.share,
    required this.method,
  });

  bool get measured => subScore != null;

  /// Points this measure contributes to its layer score.
  double get points => measured ? share * subScore! : 0.0;
}

class LayerDetail {
  final String key;
  final String label;
  final String description;

  /// 0–100 layer score (100 = fully stable).
  final double score;

  /// FRS-24 weight λ for this layer.
  final double lambda;

  final List<MeasureDetail> measures;

  const LayerDetail({
    required this.key,
    required this.label,
    required this.description,
    required this.score,
    required this.lambda,
    required this.measures,
  });

  bool get hasData => measures.any((m) => m.measured);

  /// Risk points this layer adds to FRS-24: λ × (100 − score).
  double get frsPoints => lambda * (100.0 - score);
}

class FallHistoryDetail {
  /// Falls in the trailing 365 days (simulated rows excluded).
  final int falls;

  /// Σ exp(−ln2 · days_ago / 90) — recent falls count more.
  final double weightedFalls;

  /// Walking exposure used as the denominator (floored at 168 h).
  final double ambulationHours;
  final bool belowAmbulationFloor;

  /// Weighted falls per ambulation-hour.
  final double rate;

  /// Rate scaled to 0–100 (100 = 1 fall per 100 walking hours).
  final double normalized;

  final double lambda;

  const FallHistoryDetail({
    required this.falls,
    required this.weightedFalls,
    required this.ambulationHours,
    required this.belowAmbulationFloor,
    required this.rate,
    required this.normalized,
    required this.lambda,
  });

  double get frsPoints => lambda * normalized;
}

class WomensHealthDetail {
  final bool applicable;
  final double? score;
  final int? daysSinceLastPeriod;
  final bool isPMS;
  final double? confidence;

  const WomensHealthDetail({
    required this.applicable,
    required this.score,
    required this.daysSinceLastPeriod,
    required this.isPMS,
    required this.confidence,
  });
}

class ScoreBreakdown {
  /// Physiology, Recovery, Motion — in that order.
  final List<LayerDetail> layers;
  final FallHistoryDetail fallHistory;
  final WomensHealthDetail womensHealth;

  final double frs24;
  final double frs30;
  final double coverage;
  final List<String> coverageDetails;

  /// Health Stability Index — weighted average of all layers incl. women's health.
  final double hsi;
  final Map<String, double> hsiWeights;

  const ScoreBreakdown({
    required this.layers,
    required this.fallHistory,
    required this.womensHealth,
    required this.frs24,
    required this.frs30,
    required this.coverage,
    required this.coverageDetails,
    required this.hsi,
    required this.hsiWeights,
  });
}
