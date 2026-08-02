class WomensHealthData {
  final bool isApplicable;
  final int daysSinceLastPeriod;
  final int cycleLength;
  final bool isPMS;

  WomensHealthData({
    required this.isApplicable,
    required this.daysSinceLastPeriod,
    required this.cycleLength,
    required this.isPMS,
  });
}
