/// Pure date helpers — no BuildContext, no Widget.
/// Replaces 16× `_fmt` + 7× `_isToday` + 6× `dayStartMs` duplicates.
abstract class DateKeys {
  static String fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static bool isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String dateKey(DateTime d) => fmt(dateOnly(d));

  static int dayIndexFor(DateTime d) {
    final today = dateOnly(DateTime.now());
    return today.difference(dateOnly(d)).inDays;
  }

  static bool isFuture(DateTime d) => dateOnly(d).isAfter(dateOnly(DateTime.now()));

  static int dayStartMs(DateTime d) =>
      DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;

  static int dayEndMs(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999).millisecondsSinceEpoch;

  static List<String> trendXLabels() {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();
    return List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return days[d.weekday - 1];
    });
  }

  static List<String> trendDayLabelsShort() {
    const n = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final now = DateTime.now();
    return List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return n[d.weekday - 1];
    });
  }
}
