class MotionData {
  final double impact; // Normalized 0-100
  final double orientation;
  final double recoveryAttempts;
  final double fallHistory; // 0-100
  final double accelerationMagnitude; // Raw A = sqrt(x^2 + y^2 + z^2)

  MotionData({
    required this.impact,
    required this.orientation,
    required this.recoveryAttempts,
    required this.fallHistory,
    required this.accelerationMagnitude,
  });
}
