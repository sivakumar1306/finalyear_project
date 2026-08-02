class ContextFactors {
  final double ageFactor;
  final double sleepDebtFactor;
  final double stressTrendFactor;
  final double previousFallsFactor;
  final double cyclePhaseFactor;

  ContextFactors({
    this.ageFactor = 1.0,
    this.sleepDebtFactor = 1.0,
    this.stressTrendFactor = 1.0,
    this.previousFallsFactor = 1.0,
    this.cyclePhaseFactor = 1.0,
  });
}
