import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistence for Prayer Mode's scheduled quiet-hours window. Mirrors
/// alarms_notifications_screen.dart's sleep-reminder key pattern: values
/// stored as strings (not setInt) since the Android shared_preferences
/// backend stores Dart ints as Long, and a native getInt() read would crash.
class PrayerSchedulePrefs {
  static const _startHourKey = 'prayer_mode_start_hour';
  static const _startMinuteKey = 'prayer_mode_start_minute';
  static const _endHourKey = 'prayer_mode_end_hour';
  static const _endMinuteKey = 'prayer_mode_end_minute';

  static const defaultStart = TimeOfDay(hour: 22, minute: 30);
  static const defaultEnd = TimeOfDay(hour: 6, minute: 30);

  static Future<(TimeOfDay start, TimeOfDay end)> load() async {
    final prefs = await SharedPreferences.getInstance();
    final start = TimeOfDay(
      hour: int.tryParse(prefs.getString(_startHourKey) ?? '') ?? defaultStart.hour,
      minute: int.tryParse(prefs.getString(_startMinuteKey) ?? '') ?? defaultStart.minute,
    );
    final end = TimeOfDay(
      hour: int.tryParse(prefs.getString(_endHourKey) ?? '') ?? defaultEnd.hour,
      minute: int.tryParse(prefs.getString(_endMinuteKey) ?? '') ?? defaultEnd.minute,
    );
    return (start, end);
  }

  static Future<void> save(TimeOfDay start, TimeOfDay end) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_startHourKey, start.hour.toString());
    await prefs.setString(_startMinuteKey, start.minute.toString());
    await prefs.setString(_endHourKey, end.hour.toString());
    await prefs.setString(_endMinuteKey, end.minute.toString());
  }
}
