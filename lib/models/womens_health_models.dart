/// Four core menstrual cycle phases defined in AWHE (adaptive women.docx)
enum MenstrualPhase {
  menstrual,
  follicular,
  ovulation,
  lateLuteal,
}

extension MenstrualPhaseExt on MenstrualPhase {
  String get displayName {
    switch (this) {
      case MenstrualPhase.menstrual:
        return 'Menstrual Phase';
      case MenstrualPhase.follicular:
        return 'Follicular Phase';
      case MenstrualPhase.ovulation:
        return 'Ovulation Phase';
      case MenstrualPhase.lateLuteal:
        return 'Approaching Your Period';
    }
  }

  String get physiologicalSummary {
    switch (this) {
      case MenstrualPhase.menstrual:
        return 'Lower activity, recovery begins';
      case MenstrualPhase.follicular:
        return 'Higher HRV, lower resting heart rate, stable temperature';
      case MenstrualPhase.ovulation:
        return 'Slight rise in skin temperature; resting heart rate begins increasing';
      case MenstrualPhase.lateLuteal:
        return 'You might notice increased stress sensitivity as your body prepares for your next cycle.';
    }
  }
}

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
  final MenstrualPhase estimatedPhase;
  final List<String> explainableReasons;
  final bool isVitalsOnlyPath;
  final int phaseRemainingDays;

  PredictionResult({
    required this.basePrediction,
    required this.finalPrediction,
    required this.ovulationDate,
    required this.fertileWindowStart,
    required this.fertileWindowEnd,
    required this.confidenceScore,
    required this.confidenceLevel,
    required this.estimatedPhase,
    required this.explainableReasons,
    this.isVitalsOnlyPath = false,
    this.phaseRemainingDays = 3,
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
      'estimatedPhase': estimatedPhase.name,
      'explainableReasons': explainableReasons,
      'isVitalsOnlyPath': isVitalsOnlyPath,
      'phaseRemainingDays': phaseRemainingDays,
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
      estimatedPhase: MenstrualPhase.values.firstWhere(
        (e) => e.name == json['estimatedPhase'],
        orElse: () => MenstrualPhase.lateLuteal,
      ),
      explainableReasons: (json['explainableReasons'] as List?)?.cast<String>() ?? const [],
      isVitalsOnlyPath: json['isVitalsOnlyPath'] == true,
      phaseRemainingDays: (json['phaseRemainingDays'] as num? ?? 3).toInt(),
    );
  }
}

// ── Cycle data ─────────────────────────────────────────────────────────────────

class CycleData {
  final String id;
  final DateTime periodStart;
  final int cycleLength;
  final int periodLength;
  final String? notes;

  const CycleData({
    required this.id,
    required this.periodStart,
    required this.cycleLength,
    required this.periodLength,
    this.notes,
  });

  DateTime get ovulationDate =>
      periodStart.add(Duration(days: cycleLength - 14));
  DateTime get fertileStart =>
      periodStart.add(Duration(days: cycleLength - 14 - 5));
  DateTime get fertileEnd =>
      periodStart.add(Duration(days: cycleLength - 14 + 1));
  DateTime get periodEnd =>
      periodStart.add(Duration(days: periodLength - 1));
  DateTime get nextPeriod => periodStart.add(Duration(days: cycleLength));

  factory CycleData.fromMap(Map<String, dynamic> m) => CycleData(
        id: m['id'] as String? ?? 'derived_${m['period_start']}',
        periodStart: DateTime.parse(m['period_start'] as String),
        cycleLength: (m['cycle_length'] as num? ?? 28).toInt(),
        periodLength: (m['period_length'] as num? ?? 5).toInt(),
        notes: m['notes'] as String?,
      );
}
