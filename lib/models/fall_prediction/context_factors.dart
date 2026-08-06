class ContextFactors {
  final double age;
  final double sleepDebt;
  final double stressTrend;
  final double womensHealthPhase;

  // V2 SPEC: Fall history (FH) is strictly forbidden from context factors to prevent triple-counting. It enters exactly once in Layer 3.

  ContextFactors({
    this.age = 1.0,
    this.sleepDebt = 1.0,
    this.stressTrend = 1.0,
    this.womensHealthPhase = 1.0,
  });
}
