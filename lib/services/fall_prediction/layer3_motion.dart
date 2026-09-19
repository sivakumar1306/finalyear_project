import 'dart:convert';
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

  /// Parses native Room `fall_event` rows (via `BleProvider.getFallEvents`)
  /// into [FallEvent]s for the trailing-history rate.
  ///
  /// Row shape (Gson-serialized `FallEventEntity`): `detectedAt` (epoch ms),
  /// `confidence` (0-1 float), `corroborated`, `corroborationSource`,
  /// `metadataJson` (stringified JSON with `peakG`/`peakGyro`/`stillnessRatio`
  /// for real detections, or `{"simulated":true}` for dev-triggered rows).
  ///
  /// Dev-simulated rows are excluded — they are not real falls and must not
  /// inflate the history rate. Rows older than [since] are excluded.
  /// Severity is mapped to the 0-100 scale (`confidence * 100`) to match the
  /// Supabase `falls.severity` convention. Note: `calculateFHRate` currently
  /// weights by recency only; severity is carried for future use.
  static List<FallEvent> parseNativeFallEvents(
    List<Map<String, dynamic>> rows, {
    required DateTime since,
  }) {
    final events = <FallEvent>[];
    for (final row in rows) {
      try {
        final detectedAt = row['detectedAt'];
        if (detectedAt is! num) continue;
        final timestamp =
            DateTime.fromMillisecondsSinceEpoch(detectedAt.toInt());
        if (timestamp.isBefore(since) || timestamp.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
          continue;
        }
        if (_isSimulatedRow(row)) continue;
        final confidence = row['confidence'];
        final severity = confidence is num
            ? (confidence.toDouble() * 100.0).clamp(0.0, 100.0)
            : 50.0;
        events.add(FallEvent(timestamp: timestamp, severity: severity));
      } catch (_) {
        continue;
      }
    }
    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return events;
  }

  static bool _isSimulatedRow(Map<String, dynamic> row) {
    final meta = row['metadataJson'];
    try {
      final decoded = meta is String ? jsonDecode(meta) : meta;
      if (decoded is Map && decoded['simulated'] == true) return true;
    } catch (_) {}
    return false;
  }

  /// Returns the (peakG, peakGyro) of the most recent non-simulated native
  /// event carrying motion peaks, provided it is within [maxAge] of now.
  /// These feed Layer 3 `acc`/`gyr` as an event-driven (not continuous)
  /// impact signal. Returns null when there is no fresh peak to report —
  /// callers must keep `acc`/`gyr` null (unknown), never substitute a
  /// healthy constant.
  static ({double acc, double gyr})? recentMotionPeak(
    List<Map<String, dynamic>> rows, {
    Duration maxAge = const Duration(hours: 24),
  }) {
    final cutoff = DateTime.now().subtract(maxAge);
    Map<String, dynamic>? best;
    var bestAt = 0;
    for (final row in rows) {
      try {
        if (_isSimulatedRow(row)) continue;
        final detectedAt = row['detectedAt'];
        if (detectedAt is! num) continue;
        final atMs = detectedAt.toInt();
        if (atMs <= bestAt) continue;
        if (DateTime.fromMillisecondsSinceEpoch(atMs).isBefore(cutoff)) {
          continue;
        }
        final meta = row['metadataJson'];
        final decoded = meta is String ? jsonDecode(meta) : meta;
        if (decoded is! Map) continue;
        final peakG = decoded['peakG'];
        final peakGyro = decoded['peakGyro'];
        if (peakG is! num || peakGyro is! num) continue;
        best = row;
        bestAt = atMs;
      } catch (_) {
        continue;
      }
    }
    if (best == null) return null;
    final decoded = best['metadataJson'] is String
        ? jsonDecode(best['metadataJson'] as String) as Map
        : best['metadataJson'] as Map;
    return (
      acc: (decoded['peakG'] as num).toDouble(),
      gyr: (decoded['peakGyro'] as num).toDouble(),
    );
  }

  /// Step-pattern variability proxy for Layer 3 `gait` from the 96 daily
  /// 15-minute step slots (`BleProvider.todayStepsByInterval`).
  ///
  /// This is a HEURISTIC PROXY, not clinical gait analysis: it measures the
  /// coefficient of variation across today's active slots (erratic
  /// stop-start accumulation vs. steady walking). Only slots up to [now]'s
  /// slot are considered so future slots don't dilute the statistic.
  ///
  /// Mapping is deliberately conservative: CV <= 1.0 (normal day-to-day
  /// lumpiness) maps to 0.0 (no penalty); extreme erraticness saturates at
  /// 0.5 so the proxy alone can never dominate the motion score. Returns
  /// null when fewer than 6 active slots exist (insufficient data) — callers
  /// must keep `gait` null, not zero-fill.
  static double? gaitVariabilityFromStepSlots(
    List<int> slots, {
    DateTime? now,
  }) {
    if (slots.isEmpty) return null;
    final at = now ?? DateTime.now();
    final currentSlot = ((at.hour * 60 + at.minute) ~/ 15).clamp(0, 95);
    final usable = slots.length > 96 ? slots.sublist(0, 96) : slots;
    final horizon = currentSlot.clamp(0, usable.length - 1);
    final active = <double>[];
    for (var i = 0; i <= horizon; i++) {
      final steps = usable[i];
      if (steps > 0) active.add(steps.toDouble());
    }
    if (active.length < 6) return null;
    final mean = active.reduce((a, b) => a + b) / active.length;
    if (mean <= 0) return null;
    var sumSq = 0.0;
    for (final v in active) {
      final d = v - mean;
      sumSq += d * d;
    }
    final cv = sqrt(sumSq / active.length) / mean;
    return ((cv - 1.0) / 2.0).clamp(0.0, 0.5);
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
