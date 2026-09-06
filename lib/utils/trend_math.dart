/// Pure trend math — replaces 12× reduce(min/max) + fold avg dup.
abstract class TrendMath {
  static int avg(List<int> v) => v.isEmpty ? 0 : v.fold(0, (a, b) => a + b) ~/ v.length;
  static double avgDouble(List<double> v) => v.isEmpty ? 0 : v.fold(0.0, (a, b) => a + b) / v.length;
  static int minVal(List<int> v) => v.reduce((a, b) => a < b ? a : b);
  static int maxVal(List<int> v) => v.reduce((a, b) => a > b ? a : b);
  static double minDouble(List<double> v) => v.reduce((a, b) => a < b ? a : b);
  static double maxDouble(List<double> v) => v.reduce((a, b) => a > b ? a : b);

  static ({int min, int max}) minMax(List<Map<String, dynamic>> rows, String minKey, String maxKey) {
    final mins = rows.map((r) => (r[minKey] as num?)?.toInt() ?? 0).where((v) => v > 0).toList();
    final maxs = rows.map((r) => (r[maxKey] as num?)?.toInt() ?? 0).where((v) => v > 0).toList();
    if (mins.isEmpty || maxs.isEmpty) return (min: 0, max: 0);
    return (min: mins.reduce((a, b) => a < b ? a : b), max: maxs.reduce((a, b) => a > b ? a : b));
  }

  static ({int min, int max, int avg}) statsForKey(List<Map<String, dynamic>> rows, String valueKey) {
    final vals = rows.map((r) => (r[valueKey] as num?)?.toInt() ?? 0).where((v) => v > 0).toList();
    if (vals.isEmpty) return (min: 0, max: 0, avg: 0);
    return (min: minVal(vals), max: maxVal(vals), avg: avg(vals));
  }

  /// Sleep history helpers
  static int avgHistoryScore(List<Map<String, dynamic>> rows) {
    final vals = rows.map((r) => (r['sleep_score'] as num? ?? 0).toInt()).where((v) => v > 0).toList();
    if (vals.isEmpty) return 0;
    return vals.fold(0, (a, b) => a + b) ~/ vals.length;
  }

  static int avgHistoryDuration(List<Map<String, dynamic>> rows) {
    final vals = rows.map((r) => (r['total_duration'] as num? ?? 0).toInt()).where((v) => v > 0).toList();
    if (vals.isEmpty) return 0;
    return vals.fold(0, (a, b) => a + b) ~/ vals.length;
  }

  static List<int> last7Bars(List<Map<String, dynamic>> rows) {
    final now = DateTime.now();
    final bars = <int>[];
    for (int i = 6; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final row = rows.firstWhere((r) => r['date'] == key, orElse: () => <String, dynamic>{});
      bars.add((row['total_duration'] as num? ?? 0).toInt());
    }
    return bars;
  }

  /// Minimum non-zero days required before a 7-day trend chart is shown.
  /// Gates all `NotEnoughTrendDataCard` checks (2+ days per user decision).
  static const kMinTrendDays = 2;

  static bool hasEnoughTrendData(List<num> values, {int minDays = kMinTrendDays}) =>
      values.where((v) => v > 0).length >= minDays;

  static bool hasEnoughBpTrendData(List<int> sbp, List<int> dbp, {int minDays = kMinTrendDays}) {
    final n = sbp.length < dbp.length ? sbp.length : dbp.length;
    int count = 0;
    for (int i = 0; i < n; i++) {
      if (sbp[i] > 0 && dbp[i] > 0) count++;
    }
    return count >= minDays;
  }
}
