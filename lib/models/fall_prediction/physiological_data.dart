class PhysiologicalData {
  final double heartRate; // Normalized 0-100
  final double hrv;
  final double bloodPressure;
  final double spo2;
  final double skinTemperature;

  PhysiologicalData({
    required this.heartRate,
    required this.hrv,
    required this.bloodPressure,
    required this.spo2,
    required this.skinTemperature,
  });
}
