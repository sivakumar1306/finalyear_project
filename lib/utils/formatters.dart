/// Pure string formatters — no Widget.
/// Consolidates sleep_duration, sleepTimeLabel, hourLabel etc. duplicated 4-7×.
abstract class Formatters {
  static String sleepDuration(int secs) {
    if (secs <= 0) return '--';
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  // sleep_screen: _fmt(secs) variant with padded minutes "2h 05m" vs "2h 5m" — keep both flavors?
  // We expose padded variant as well for detail hero.
  static String sleepDurationPadded(int secs) {
    if (secs <= 0) return '--';
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m}m';
  }

  static String sleepTimeLabel(int ts) {
    if (ts <= 0) return '--';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final suffix = h < 12 ? 'am' : 'pm';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$m$suffix';
  }

  static String fmtTime(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = h < 12 ? 'AM' : 'PM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$m $ampm';
  }

  static String hourLabel(int hour) {
    if (hour == 0) return '12am';
    if (hour < 12) return '${hour}am';
    if (hour == 12) return '12pm';
    return '${hour - 12}pm';
  }

  static String halfHourLabel(int slot) {
    final minutes = slot * 30;
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final ampm = h < 12 ? 'am' : 'pm';
    final mm = m == 0 ? '00' : '30';
    return '$h12:$mm$ampm';
  }

  static String greetingForHour(int hour) {
    if (hour < 12) return 'Good Morning,';
    if (hour < 17) return 'Good Afternoon,';
    if (hour < 21) return 'Good Evening,';
    return 'Good Night,';
  }

  /// At most [places] fractional digits. Trailing zeros are dropped so a whole
  /// number stays short in a tight card (`70` rather than `70.00`) while a raw
  /// value such as `36.6666667` cannot blow out the row.
  static String fixed(num value, {int places = 2}) {
    final digits = places < 0 ? 0 : places;
    var text = value.toStringAsFixed(digits);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      text = text.replaceFirst(RegExp(r'\.$'), '');
    }
    if (text == '-0') return '0';
    return text;
  }

  static String dateLabel(DateTime now) {
    const d = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const m = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
    return '${d[now.weekday - 1]} · ${now.day.toString().padLeft(2, '0')} ${m[now.month - 1]}';
  }
}

extension MetricNumber on num {
  /// At most two fractional digits, with trailing zeros removed.
  String fixed2() => Formatters.fixed(this);
}
