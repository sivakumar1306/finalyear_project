import '../utils/date_keys.dart';
import '../utils/trend_math.dart';

/// Generic cache-then-cloud history helper.
/// Pure date/series logic lives here; widgets only map to setState.
/// Replaces 7× `_load7DayTrend` hand-rolled `List.generate(7, firstWhere date==fmt)` + `reduce(min/max)`.
abstract class HistoryService {
  /// Build 7-day avg series oldest→newest from rows with `date` + `valueKey`.
  static List<int> last7IntSeries(
    List<Map<String, dynamic>> rows,
    String valueKey, {
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    return List.generate(7, (i) {
      final day = ref.subtract(Duration(days: 6 - i));
      final key = DateKeys.fmt(day);
      Map<String, dynamic>? row;
      for (final r in rows) {
        if (r['date'] == key) {
          row = r;
          break;
        }
      }
      return (row?[valueKey] as num? ?? 0).toInt();
    });
  }

  static ({int min, int max}) minMaxForKey(
    List<Map<String, dynamic>> rows,
    String minKey,
    String maxKey,
  ) =>
      TrendMath.minMax(rows, minKey, maxKey);

  /// Half-split delta used by InsightsService trends.
  static ({double first, double second, int delta}) splitDelta(List<int> values) {
    if (values.length < 4) return (first: 0, second: 0, delta: 0);
    final mid = values.length ~/ 2;
    final first = values.sublist(0, mid).fold(0, (a, b) => a + b) / mid;
    final second =
        values.sublist(mid).fold(0, (a, b) => a + b) / (values.length - mid);
    return (first: first, second: second, delta: (second - first).round());
  }
}
