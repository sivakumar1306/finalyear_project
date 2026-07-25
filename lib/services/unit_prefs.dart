import 'package:shared_preferences/shared_preferences.dart';

enum UnitSystem { metric, us }

enum TempUnit { celsius, fahrenheit }

/// Display-only unit preferences. Every stored value — Supabase columns
/// (height_cm, weight_kg), OnboardingData, local DB readings — stays in its
/// existing canonical unit (kg, cm, °C) no matter what this is set to; only
/// what's shown to / typed in by the user gets converted at the UI edge.
class UnitPrefs {
  static const _systemKey = 'unit_system'; // 'metric' | 'us'
  static const _tempKey = 'temp_unit'; // 'C' | 'F'

  static Future<UnitSystem> loadSystem() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_systemKey) ?? 'metric') == 'us'
        ? UnitSystem.us
        : UnitSystem.metric;
  }

  static Future<void> saveSystem(UnitSystem system) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_systemKey, system == UnitSystem.us ? 'us' : 'metric');
  }

  static Future<TempUnit> loadTempUnit() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_tempKey) ?? 'C') == 'F'
        ? TempUnit.fahrenheit
        : TempUnit.celsius;
  }

  static Future<void> saveTempUnit(TempUnit unit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tempKey, unit == TempUnit.fahrenheit ? 'F' : 'C');
  }

  // ── Conversions (display-only) ──────────────────────────────────────────

  static double kgToLbs(double kg) => kg * 2.2046226218;
  static double lbsToKg(double lbs) => lbs / 2.2046226218;
  static double cmToInches(double cm) => cm / 2.54;
  static double inchesToCm(double inches) => inches * 2.54;
  static double celsiusToFahrenheit(double c) => c * 9 / 5 + 32;
  static double fahrenheitToCelsius(double f) => (f - 32) * 5 / 9;

  static String formatWeightKg(double kg, UnitSystem system) {
    if (system == UnitSystem.us) {
      return '${kgToLbs(kg).toStringAsFixed(1)} lbs';
    }
    return '${kg.toStringAsFixed(1)} kg';
  }

  static String formatHeightCm(num cm, UnitSystem system) {
    if (system == UnitSystem.metric) return '${cm.round()} cm';
    final totalInches = cmToInches(cm.toDouble());
    final feet = totalInches ~/ 12;
    final inches = (totalInches % 12).round();
    return "$feet' $inches\"";
  }

  static String formatTempC(double c, TempUnit unit) {
    if (unit == TempUnit.fahrenheit) {
      return '${celsiusToFahrenheit(c).toStringAsFixed(1)}°F';
    }
    return '${c.toStringAsFixed(1)}°C';
  }
}
