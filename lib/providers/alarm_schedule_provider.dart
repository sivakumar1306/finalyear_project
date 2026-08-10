import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted schedule for the Alarms card. Only owns `focusEnd` —
/// meditation and wind-down times live in PrayerSchedulePrefs and the
/// sleep-reminder prefs respectively, since those already have dedicated
/// edit screens (PrayerScheduleScreen, SleepScheduleScreen).
class AlarmScheduleProvider extends ChangeNotifier {
  static const _kFocusEndKey = 'alarm_focus_end';
  static const _kFocusScheduledKey = 'alarm_focus_scheduled';
  static const _kPushingAppsCountKey = 'alarm_pushing_apps_count';

  TimeOfDay _focusEnd = const TimeOfDay(hour: 13, minute: 0);
  bool _isFocusScheduled = false;
  int _pushingAppsCount = 0;

  TimeOfDay get focusEnd => _focusEnd;
  bool get isFocusScheduled => _isFocusScheduled;
  int get pushingAppsCount => _pushingAppsCount;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _focusEnd = _parse(prefs.getString(_kFocusEndKey)) ?? _focusEnd;
    _isFocusScheduled = prefs.getBool(_kFocusScheduledKey) ?? false;
    _pushingAppsCount = prefs.getInt(_kPushingAppsCountKey) ?? 0;
    _loaded = true;
    notifyListeners();
  }

  TimeOfDay? _parse(String? raw) {
    if (raw == null) return null;
    final parts = raw.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> setFocusEnd(TimeOfDay t) async {
    _focusEnd = t;
    _isFocusScheduled = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFocusEndKey, _fmt(t));
    await prefs.setBool(_kFocusScheduledKey, true);
  }

  Future<void> clearFocusSchedule() async {
    _isFocusScheduled = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFocusScheduledKey, false);
  }

  /// Formats a [TimeOfDay] as "1:00 pm" (lowercase am/pm, no leading zero).
  String label(TimeOfDay t) {
    final h12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final period = t.period == DayPeriod.am ? 'am' : 'pm';
    final m = t.minute.toString().padLeft(2, '0');
    return '$h12:$m $period';
  }
}
