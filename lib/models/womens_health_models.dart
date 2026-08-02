class HealthMetrics {
  /// Temperature (normalized between 0-100)
  final double temperature;
  
  /// Heart Rate Variability (normalized between 0-100)
  final double hrv;
  
  /// Resting Heart Rate (normalized between 0-100)
  final double heartRate;
  
  /// Sleep Quality (normalized between 0-100)
  final double sleepQuality;
  
  /// Stress Level (normalized between 0-100)
  final double stress;
  
  /// Activity Level (normalized between 0-100)
  final double activityLevel;

  HealthMetrics({
    required this.temperature,
    required this.hrv,
    required this.heartRate,
    required this.sleepQuality,
    required this.stress,
    required this.activityLevel,
  }) : assert(temperature >= 0 && temperature <= 100),
       assert(hrv >= 0 && hrv <= 100),
       assert(heartRate >= 0 && heartRate <= 100),
       assert(sleepQuality >= 0 && sleepQuality <= 100),
       assert(stress >= 0 && stress <= 100),
       assert(activityLevel >= 0 && activityLevel <= 100);

  // Standard copyWith, toJson, fromJson could be added here later
  // if required for remote backend swapping.
  
  Map<String, dynamic> toJson() {
    return {
      'temperature': temperature,
      'hrv': hrv,
      'heartRate': heartRate,
      'sleepQuality': sleepQuality,
      'stress': stress,
      'activityLevel': activityLevel,
    };
  }

  factory HealthMetrics.fromJson(Map<String, dynamic> json) {
    return HealthMetrics(
      temperature: (json['temperature'] as num).toDouble(),
      hrv: (json['hrv'] as num).toDouble(),
      heartRate: (json['heartRate'] as num).toDouble(),
      sleepQuality: (json['sleepQuality'] as num).toDouble(),
      stress: (json['stress'] as num).toDouble(),
      activityLevel: (json['activityLevel'] as num).toDouble(),
    );
  }
}

class PredictionResult {
  final DateTime basePrediction;
  final DateTime finalPrediction;
  final DateTime ovulationDate;
  final DateTime fertileWindowStart;
  final DateTime fertileWindowEnd;
  final double confidenceScore;
  final String confidenceLevel;

  PredictionResult({
    required this.basePrediction,
    required this.finalPrediction,
    required this.ovulationDate,
    required this.fertileWindowStart,
    required this.fertileWindowEnd,
    required this.confidenceScore,
    required this.confidenceLevel,
  });

  Map<String, dynamic> toJson() {
    return {
      'basePrediction': basePrediction.toIso8601String(),
      'finalPrediction': finalPrediction.toIso8601String(),
      'ovulationDate': ovulationDate.toIso8601String(),
      'fertileWindowStart': fertileWindowStart.toIso8601String(),
      'fertileWindowEnd': fertileWindowEnd.toIso8601String(),
      'confidenceScore': confidenceScore,
      'confidenceLevel': confidenceLevel,
    };
  }

  factory PredictionResult.fromJson(Map<String, dynamic> json) {
    return PredictionResult(
      basePrediction: DateTime.parse(json['basePrediction']),
      finalPrediction: DateTime.parse(json['finalPrediction']),
      ovulationDate: DateTime.parse(json['ovulationDate']),
      fertileWindowStart: DateTime.parse(json['fertileWindowStart']),
      fertileWindowEnd: DateTime.parse(json['fertileWindowEnd']),
      confidenceScore: (json['confidenceScore'] as num).toDouble(),
      confidenceLevel: json['confidenceLevel'],
    );
  }
}
