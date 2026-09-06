import 'dart:convert';

import '../utils/date_keys.dart';
import 'ble_service.dart';

/// Local-first vitals access over the native Room DB (`qring_local.db`).
///
/// Read order for day summaries / multi-day trends:
/// 1. Local Room (raw samples + `daily_vital_summary` rollups)
/// 2. Optional cloud fetch (caller supplies), then cache back into Room
///
/// This keeps health screens usable offline and avoids round-tripping every
/// past-day / 7-day chart request to Supabase.
class LocalVitalsService {
  LocalVitalsService({BleService? ble}) : _ble = ble ?? BleService();

  final BleService _ble;

  static int dayStartMs(DateTime d) => DateKeys.dayStartMs(d);

  static int dayEndMs(DateTime d) => DateKeys.dayEndMs(d);

  static String dateStr(DateTime d) => DateKeys.fmt(d);

  /// Day aggregate from local Room only (no network).
  Future<Map<String, dynamic>> getDaySummary(String vital, DateTime date) async {
    final json = await _ble.getDaySummary(
      vital,
      dayStartMs: dayStartMs(date),
      dayEndMs: dayEndMs(date),
    );
    final decoded = jsonDecode(json);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{};
  }

  /// True when local has useful data for the day.
  bool hasData(Map<String, dynamic> summary) {
    final count = (summary['count'] as num?)?.toInt() ?? 0;
    final steps = (summary['steps'] as num?)?.toInt() ?? 0;
    final avg = (summary['avg'] as num?)?.toDouble() ?? 0;
    return count > 0 || steps > 0 || avg > 0;
  }

  /// 7-day (or N-day) history from local rollups. Keys by `dateStr`.
  Future<List<Map<String, dynamic>>> getHistory(
    String vital, {
    int days = 7,
    DateTime? end,
  }) async {
    final to = end ?? DateTime.now();
    final from = DateTime(to.year, to.month, to.day)
        .subtract(Duration(days: days - 1));
    final json = await _ble.getLocalHistory(
      vital,
      fromDayStartMs: dayStartMs(from),
      toDayStartMs: dayStartMs(to),
    );
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Build a fixed-length avg series aligned to calendar days (oldest → newest).
  Future<List<int>> historyAvgSeries(
    String vital, {
    int days = 7,
    String avgKey = 'avg',
  }) async {
    final now = DateTime.now();
    final rows = await getHistory(vital, days: days, end: now);
    final byDate = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final key = r['dateStr'] as String? ?? '';
      if (key.isNotEmpty) byDate[key] = r;
    }
    return List.generate(days, (i) {
      final day = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: days - 1 - i));
      final row = byDate[dateStr(day)];
      if (row == null) return 0;
      return (row[avgKey] as num?)?.round() ?? 0;
    });
  }

  /// Cache a simple avg/min/max day into Room after a successful cloud fetch.
  Future<void> cacheSimpleDay({
    required String vital,
    required DateTime date,
    required num? avg,
    required num? min,
    required num? max,
    int count = 1,
  }) async {
    if (avg == null && min == null && max == null) return;
    await _ble.cacheCloudDaySummary(
      vital: vital,
      dayStartMs: dayStartMs(date),
      avg: avg?.toDouble(),
      min: min?.toDouble(),
      max: max?.toDouble(),
      count: count <= 0 ? 1 : count,
    );
  }

  Future<void> cacheStepsDay({
    required DateTime date,
    required int? steps,
    int? caloriesKcal,
    double? distanceM,
  }) async {
    if (steps == null || steps <= 0) return;
    await _ble.cacheCloudDaySummary(
      vital: 'steps',
      dayStartMs: dayStartMs(date),
      avg: steps.toDouble(),
      min: steps.toDouble(),
      max: steps.toDouble(),
      count: 1,
      steps: steps,
      caloriesKcal: caloriesKcal,
      distanceM: distanceM,
    );
  }

  Future<void> cacheBpDay({
    required DateTime date,
    required num? avgSbp,
    required num? minSbp,
    required num? maxSbp,
    required num? avgDbp,
    required num? minDbp,
    required num? maxDbp,
    int count = 1,
  }) async {
    if (avgSbp == null && avgDbp == null) return;
    await _ble.cacheCloudDaySummary(
      vital: 'blood_pressure',
      dayStartMs: dayStartMs(date),
      avg: avgSbp?.toDouble(),
      min: minSbp?.toDouble(),
      max: maxSbp?.toDouble(),
      avgSecondary: avgDbp?.toDouble(),
      minSecondary: minDbp?.toDouble(),
      maxSecondary: maxDbp?.toDouble(),
      count: count <= 0 ? 1 : count,
    );
  }

  /// Raw local samples for hour charts (works offline while samples are retained).
  Future<List<Map<String, dynamic>>> getReadings(
    String vital,
    DateTime date, {
    int limit = 1000,
  }) async {
    final json = await _ble.getReadings(
      vital,
      fromMs: dayStartMs(date),
      toMs: dayEndMs(date),
      limit: limit,
    );
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> dbStats() async {
    final json = await _ble.getLocalDbStats();
    final decoded = jsonDecode(json);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{};
  }
}
