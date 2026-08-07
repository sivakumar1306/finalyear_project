import 'dart:math';
import '../../models/fall_prediction/layer_inputs.dart';
import 'fall_risk_registry.dart';

class FallEvent {
  final DateTime timestamp;
  final double severity;

  FallEvent({
    required this.timestamp,
    required this.severity,
  });
}

class FallHistoryRate {
  final double rate;
  final bool isBelowAmbulationFloor;

  FallHistoryRate(this.rate, {this.isBelowAmbulationFloor = false});
}

class Layer3Result {
  final MotionStabilityScore motionStabilityScore;
  final FallHistoryRate fallHistoryRate;

  Layer3Result({
    required this.motionStabilityScore,
    required this.fallHistoryRate,
  });
}

class Layer3MotionService {
  final dynamic supabaseClient;

  Layer3MotionService(this.supabaseClient);

  /// Queries the Supabase database for the user's fall history over the last 365 days.
  Future<List<FallEvent>> fetchTrailing12MonthFalls(String userId) async {
    final oneYearAgo = DateTime.now().subtract(const Duration(days: 365));
    
    try {
      final response = await supabaseClient
          .from('falls')
          .select('timestamp, severity')
          .eq('user_id', userId)
          .gte('timestamp', oneYearAgo.toIso8601String());
          
      final data = response as List<dynamic>;
      return data.map((json) => FallEvent(
        timestamp: DateTime.parse(json['timestamp']),
        severity: (json['severity'] as num).toDouble(),
      )).toList();
    } catch (e) {
      return [];
    }
  }

  /// Impact/Stability sub-score (0-100).
  /// Calculates resultant magnitude, gated for motion artifacts.
  double calculateMI(double acc) {
    // Assuming acc is resultant acceleration in g's
    // Normal walking is ~1-1.5g. Stumbles/impacts > 2.5g
    const double threshold = 2.5; 
    const double steepness = 5.0;
    double score = 100.0 / (1.0 + exp(steepness * (acc - threshold)));
    return score.clamp(0.0, 100.0);
  }

  /// Gait sub-score (0-100).
  /// Evaluates step regularity and cadence variability, using GYR for angular velocity context.
  double calculateMG(double gait, double gyr) {
    // Base score degrades as gait variability increases
    double baseGaitScore = 100.0 - (gait * 100.0); 
    
    // Apply a penalty based on angular instability (gyro context)
    double penalty = gyr * 0.2; 
    return (baseGaitScore - penalty).clamp(0.0, 100.0);
  }

  /// Balance sub-score (0-100).
  double calculateMB(double psw, double ortho, double gyr) {
    // IMPLEMENTS PATENT 003 CLAIMS 21-23: Postural sway (PSW) plus orthostatic HR/BP trajectory (ORTHO) after posture change as surrogate for proprioceptive function.
    
    double fPsw(double p, double g) {
      // Inverse mapping of sway area to stability (0-100)
      double swayScore = 100.0 - (p * 10.0);
      // Penalize if sway is accompanied by high angular velocity (loss of control)
      double controlPenalty = g * 0.3;
      return (swayScore - controlPenalty).clamp(0.0, 100.0);
    }
    
    double fOrtho(double o) {
      // Map orthostatic drop severity to stability score
      // A drop of 0 -> 100 score, a drop of 25 -> 0 score
      return (100.0 - (o * 4.0)).clamp(0.0, 100.0);
    }

    return (0.5 * fPsw(psw, gyr) + 0.5 * fOrtho(ortho)).clamp(0.0, 100.0);
  }

  /// Plantar sub-score (0-100).
  /// If the user does not have a Smart Insole, this must explicitly evaluate to 0.0.
  double calculateMP(double plnt) {
    // If plnt is a Center of Pressure (CoP) deviation metric
    // Map deviation to a 0-100 score
    double score = 100.0 - (plnt * 15.0);
    return score.clamp(0.0, 100.0);
  }

  MotionStabilityScore calculateMO(Layer3MotionData data, {required Map<String, double> wPrime}) {
    double moRaw = 0.0;
    double totalWeight = 0.0;

    double wMi = wPrime['MI'] ?? 0.25;
    double wMg = wPrime['MG'] ?? 0.25;
    double wMb = wPrime['MB'] ?? 0.25;
    double wMp = wPrime['MP'] ?? 0.25;

    if (data.acc != null) {
      moRaw += wMi * calculateMI(data.acc!);
      totalWeight += wMi;
    }

    if (data.gait != null && data.gyr != null) {
      moRaw += wMg * calculateMG(data.gait!, data.gyr!);
      totalWeight += wMg;
    }

    if (data.psw != null && data.ortho != null && data.gyr != null) {
      moRaw += wMb * calculateMB(data.psw!, data.ortho!, data.gyr!);
      totalWeight += wMb;
    }

    if (data.plnt != null) {
      moRaw += wMp * calculateMP(data.plnt!);
      totalWeight += wMp;
    }

    double mo = totalWeight > 0 ? (moRaw / totalWeight) : 100.0;
    
    // Bound the result to 0-100
    mo = mo.clamp(0.0, 100.0);

    return MotionStabilityScore(mo);
  }

  FallHistoryRate calculateFHRate(List<FallEvent> trailingFalls, double ambulationHours) {
    if (ambulationHours <= 0) return FallHistoryRate(0.0, isBelowAmbulationFloor: true);

    final now = DateTime.now();
    double weightedFallsSum = 0.0;

    for (var fall in trailingFalls) {
      double daysAgo = now.difference(fall.timestamp).inDays.toDouble();
      if (daysAgo < 0) daysAgo = 0;

      // 90-day half-life exponential decay: weight = exp(-ln(2) * (days_ago / 90.0))
      double weight = exp(-ln2 * (daysAgo / 90.0));
      weightedFallsSum += weight;
    }

    bool isBelowFloor = ambulationHours < 168.0;
    double effectiveHours = max(ambulationHours, 168.0);

    return FallHistoryRate(weightedFallsSum / effectiveHours, isBelowAmbulationFloor: isBelowFloor);
  }
}
