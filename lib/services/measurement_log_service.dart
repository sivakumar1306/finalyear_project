import 'dart:convert';
import 'ble_service.dart';

/// Grouped measurement log: auto cycles (grouped by cycleId) + manual singletons.
/// Local Room only, last 3 days default.
class GroupedCycle {
  final int cycleId;
  final int startedAt;
  final int? completedAt;
  final String status;
  final List<Map<String, dynamic>> attempts;
  const GroupedCycle({
    required this.cycleId,
    required this.startedAt,
    this.completedAt,
    required this.status,
    required this.attempts,
  });

  int get failedCount => attempts.where((a) => (a['status'] as String? ?? 'success') != 'success').length;
  bool get isManual => attempts.length == 1 &&
      (attempts.first['source'] as String? ?? '') != 'auto_cycle';
}

class MeasurementLogService {
  final BleService _ble = BleService();

  static bool isFailed(Map<String, dynamic> a) =>
      (a['status'] as String? ?? 'success') != 'success';

  Future<List<GroupedCycle>> getGroupedLog({required DateTime from, required DateTime to, bool failedOnly = false}) async {
    final fromMs = from.millisecondsSinceEpoch;
    final toMs = to.millisecondsSinceEpoch;
    final cyclesJson = await _ble.getMeasurementCycleHistory(fromMs: fromMs, toMs: toMs);
    final attemptsJson = failedOnly
        ? await _ble.getFailedMeasurementAttempts(fromMs: fromMs, toMs: toMs)
        : await _ble.getMeasurementAttempts(fromMs: fromMs, toMs: toMs);
    final cycles = (jsonDecode(cyclesJson) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final attempts = (jsonDecode(attemptsJson) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final byCycle = <int, List<Map<String, dynamic>>>{};
    for (final a in attempts) {
      final cid = (a['cycleId'] as num?)?.toInt() ?? 0;
      byCycle.putIfAbsent(cid, () => []).add(a);
    }
    final out = <GroupedCycle>[];
    for (final c in cycles) {
      final id = (c['id'] as num?)?.toInt() ?? 0;
      final list = byCycle.remove(id) ?? <Map<String, dynamic>>[];
      if (failedOnly && list.every((a) => !isFailed(a))) continue;
      out.add(GroupedCycle(
        cycleId: id,
        startedAt: (c['startedAt'] as num?)?.toInt() ?? 0,
        completedAt: (c['completedAt'] as num?)?.toInt(),
        status: c['status'] as String? ?? '',
        attempts: list,
      ));
    }
    // Orphan attempts (cycle row purged or phantom) → singleton groups
    byCycle.forEach((cid, list) {
      if (failedOnly && list.every((a) => !isFailed(a))) return;
      final start = list.map((a) => (a['startedAt'] as num?)?.toInt() ?? 0).fold(0, (a, b) => a > b ? a : b);
      out.add(GroupedCycle(cycleId: cid, startedAt: start, status: 'ORPHAN', attempts: list));
    });
    out.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return out;
  }
}
