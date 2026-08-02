enum RiskClassification { low, moderate, high }

class PredictionResult {
  final double hsi; // 0-100
  final double fcs; // 0-100
  final RiskClassification riskLevel;
  final List<String> reasoningChain;

  PredictionResult({
    required this.hsi,
    required this.fcs,
    required this.riskLevel,
    required this.reasoningChain,
  });
}
