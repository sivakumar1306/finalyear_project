import 'package:shared_preferences/shared_preferences.dart';

/// Centralised persistence for which health-event alerts the user wants to
/// be notified about (Select Notifications screen). Mirrors GoalPrefs /
/// HomeCardPrefs's SharedPreferences pattern. Read by BleProvider's live
/// threshold checks to decide whether a crossed threshold should actually
/// fire a phone notification.
class NotificationPrefs {
  static const _prefix = 'alert_enabled_';

  static const Map<String, bool> defaults = {
    'High Heart Rate': true,
    'Low Heart Rate': false,
    'High BP': false,
    'Low BP': false,
    'High SpO2': false,
    'Low SpO2': false,
    'Step count achieved': false,
    'High temperature notification': false,
    'Low Battery': true,
  };

  static Future<Map<String, bool>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final entry in defaults.entries)
        entry.key: prefs.getBool('$_prefix${entry.key}') ?? entry.value,
    };
  }

  static Future<void> setEnabled(String key, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix$key', enabled);
  }

  static Future<bool> isEnabled(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefix$key') ?? (defaults[key] ?? false);
  }
}
