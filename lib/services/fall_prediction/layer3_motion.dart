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



  /// The last full day's steps (yesterday, or up to 7 days back) and the
  /// median and robust spread of the 28 days before it, as in the report's
  /// personal baseline (median, 1.4826 × MAD, at least 7 days, spread ≥ 500).
  /// The baseline fields are null when there are fewer than 7 earlier days.
  static ({double? steps, double? median, double? spread}) stepsBaseline(
    Map<DateTime, int> dailySteps, {
    DateTime? today,
  }) {
    final t = today ?? DateTime.now();
    int stepsOn(int daysBack, DateTime from) =>
        dailySteps[DateTime(from.year, from.month, from.day - daysBack)] ?? 0;
    DateTime? latest;
    for (var back = 1; back <= 7; back++) {
      if (stepsOn(back, t) > 0) {
        latest = DateTime(t.year, t.month, t.day - back);
        break;
      }
    }
    if (latest == null) return (steps: null, median: null, spread: null);
    final steps = stepsOn(0, latest).toDouble();
    final history = <double>[
      for (var back = 1; back <= 28; back++)
        if (stepsOn(back, latest) > 0) stepsOn(back, latest).toDouble(),
    ];
    if (history.length < 7) return (steps: steps, median: null, spread: null);
    final median = _median(history);
    final mad = _median([for (final v in history) (v - median).abs()]);
    return (steps: steps, median: median, spread: max(1.4826 * mad, 500.0));
  }

  static double _median(List<double> values) {
    final v = [...values]..sort();
    final mid = v.length ~/ 2;
    return v.length.isOdd ? v[mid] : (v[mid - 1] + v[mid]) / 2.0;
  }

  /// Daily-steps stability (0-100): 100 − dead-zone strain of the robust
  /// z-score, where fewer steps than your own median is worse. Same mapping as
  /// the report's engine: no strain below 0.5 SD, full strain at 3 SD.
  double calculateSteps(double steps, double median, double spread) {
    final z = (median - steps) / spread;
    final strain = ((z - 0.5) / 2.5).clamp(0.0, 1.0) * 100.0;
    return 100.0 - strain;
  }

  /// Near-fall stability (0-100): each fall alert in 14 days removes 50.
  double calculateNearFalls(int alerts) =>
      100.0 - min(100.0, 50.0 * alerts);

  MotionStabilityScore calculateMO(Layer3MotionData data, {required Map<String, double> wPrime}) {
    double moRaw = 0.0;
    double totalWeight = 0.0;

    final wSteps = wPrime['steps'] ?? 0.5;
    final wNear = wPrime['nearFalls'] ?? 0.5;

    if (data.hasSteps) {
      moRaw += wSteps * calculateSteps(data.steps!, data.stepsMedian!, data.stepsSpread!);
      totalWeight += wSteps;
    }

    if (data.hasNearFalls) {
      moRaw += wNear * calculateNearFalls(data.nearFalls14d!);
      totalWeight += wNear;
    }

    double mo = totalWeight > 0 ? (moRaw / totalWeight) : 100.0;
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
