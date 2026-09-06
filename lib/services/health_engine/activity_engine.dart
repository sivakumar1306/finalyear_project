import 'dart:convert';

/// Pure activity domain — no Widget.
class ActivityEngine {
  /// Parse ring interval JSON (96 slots) handling obfuscated keys d/f/e/g
  static DaySnapshot? parseIntervalJson(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      final list = decoded is List ? decoded : <dynamic>[];
      if (list.isEmpty) return null;
      final stepSlots = List<int>.filled(96, 0);
      final calSlotsRaw = List<int>.filled(96, 0);
      final distSlots = List<double>.filled(96, 0.0);
      int totalSteps = 0, totalCalRaw = 0;
      double totalDist = 0.0;
      for (final item in list) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final slot = (m['d'] as num?)?.toInt() ?? (m['timeIndex'] as num?)?.toInt() ?? -1;
        final steps = (m['f'] as num?)?.toInt() ?? (m['walkSteps'] as num?)?.toInt() ?? 0;
        final runSteps = (m['runSteps'] as num?)?.toInt() ?? 0;
        final stepTotal = steps + runSteps;
        final calRaw = (m['e'] as num?)?.toInt() ?? (m['calorie'] as num?)?.toInt() ?? 0;
        final dist = (m['g'] as num?)?.toDouble() ?? (m['distance'] as num?)?.toDouble() ?? 0.0;
        totalSteps += stepTotal;
        totalCalRaw += calRaw;
        totalDist += dist;
        if (slot >= 0 && slot < 96) {
          stepSlots[slot] += stepTotal;
          calSlotsRaw[slot] += calRaw;
          distSlots[slot] += dist;
        }
      }
      final totalCal = totalCalRaw >= 1000 ? totalCalRaw ~/ 1000 : (totalCalRaw > 0 ? 1 : 0);
      final calSlots = calSlotsRaw.map((c) => c >= 1000 ? c ~/ 1000 : (c > 0 ? 1 : 0)).toList();
      if (totalSteps <= 0 && totalCal <= 0 && totalDist <= 0) return null;
      return DaySnapshot(steps: totalSteps, cal: totalCal, distM: totalDist, stepSlots: stepSlots, calSlots: calSlots, distSlots: distSlots);
    } catch (_) {
      return null;
    }
  }

  static int normalizeCalories(int rawCal, int steps) {
    if (rawCal >= 1000) return rawCal ~/ 1000;
    if (rawCal > 0) return 1;
    return 0;
  }

  // Supabase variant
  static int normalizeSupabaseCalories(int rawCal, int steps) {
    if (rawCal >= 500 && steps < 4000) return rawCal ~/ 1000;
    return rawCal;
  }

  static ({List<int> stepSlots, List<int> calSlots, List<double> distSlots}) distributeSteps(int curSteps, int curCal, double curDist, int nowSlot) {
    final stepSlots = List<int>.filled(96, 0);
    final calSlots = List<int>.filled(96, 0);
    final distSlots = List<double>.filled(96, 0.0);
    if (curSteps <= 0) return (stepSlots: stepSlots, calSlots: calSlots, distSlots: distSlots);
    final activeSlotsCount = (nowSlot - 28).clamp(1, 96);
    final stepsPerSlot = (curSteps / activeSlotsCount).round();
    final calPerSlot = (curCal / activeSlotsCount).round();
    final distPerSlot = curDist / activeSlotsCount;
    for (int i = 28; i <= nowSlot && i < 96; i++) {
      stepSlots[i] = stepsPerSlot;
      calSlots[i] = calPerSlot;
      distSlots[i] = distPerSlot;
    }
    return (stepSlots: stepSlots, calSlots: calSlots, distSlots: distSlots);
  }

  static List<double> toHourlyInt(List<int> slots96) {
    assert(slots96.length == 96);
    return List.generate(24, (h) => slots96.sublist(h * 4, h * 4 + 4).fold(0, (a, b) => a + b).toDouble());
  }

  static List<double> toHourlyDouble(List<double> slots96) {
    assert(slots96.length == 96);
    return List.generate(24, (h) => slots96.sublist(h * 4, h * 4 + 4).fold(0.0, (a, b) => a + b));
  }
}

class DaySnapshot {
  final int steps, cal;
  final double distM;
  final List<int> stepSlots, calSlots;
  final List<double> distSlots;
  const DaySnapshot({required this.steps, required this.cal, required this.distM, required this.stepSlots, required this.calSlots, required this.distSlots});
  bool get hasTotals => steps > 0 || cal > 0 || distM > 0;
  bool get hasIntervals => stepSlots.any((v) => v > 0) || calSlots.any((v) => v > 0) || distSlots.any((v) => v > 0);
}
