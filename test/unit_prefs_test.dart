import 'package:flutter_test/flutter_test.dart';
import 'package:sundr/services/unit_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('UnitPrefs conversions', () {
    test('weight round-trips kg ↔ lbs', () {
      const kg = 70.0;
      final lbs = UnitPrefs.kgToLbs(kg);
      expect(lbs, closeTo(154.32, 0.01));
      expect(UnitPrefs.lbsToKg(lbs), closeTo(kg, 0.001));
    });

    test('height round-trips cm ↔ inches', () {
      const cm = 180.0;
      final inches = UnitPrefs.cmToInches(cm);
      expect(inches, closeTo(70.866, 0.01));
      expect(UnitPrefs.inchesToCm(inches), closeTo(cm, 0.001));
    });

    test('temperature round-trips C ↔ F', () {
      expect(UnitPrefs.celsiusToFahrenheit(0), 32);
      expect(UnitPrefs.celsiusToFahrenheit(100), 212);
      expect(UnitPrefs.celsiusToFahrenheit(37), closeTo(98.6, 0.01));
      expect(UnitPrefs.fahrenheitToCelsius(32), 0);
      expect(UnitPrefs.fahrenheitToCelsius(212), 100);
    });
  });

  group('UnitPrefs formatting', () {
    test('formatWeightKg metric and us', () {
      expect(UnitPrefs.formatWeightKg(70, UnitSystem.metric), '70 kg');
      expect(UnitPrefs.formatWeightKg(70, UnitSystem.us), '154.32 lbs');
    });

    test('formatHeightCm metric and us', () {
      expect(UnitPrefs.formatHeightCm(180, UnitSystem.metric), '180 cm');
      final us = UnitPrefs.formatHeightCm(180, UnitSystem.us);
      expect(us, contains("'"));
      expect(us, contains('"'));
    });

    test('formatTempC', () {
      expect(UnitPrefs.formatTempC(36.5, TempUnit.celsius), '36.5°C');
      expect(UnitPrefs.formatTempC(0, TempUnit.fahrenheit), '32°F');
      expect(UnitPrefs.formatTempC(36.6666667, TempUnit.celsius), '36.67°C');
    });
  });

  group('UnitPrefs persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to metric and celsius', () async {
      expect(await UnitPrefs.loadSystem(), UnitSystem.metric);
      expect(await UnitPrefs.loadTempUnit(), TempUnit.celsius);
    });

    test('save and load system/temp', () async {
      await UnitPrefs.saveSystem(UnitSystem.us);
      await UnitPrefs.saveTempUnit(TempUnit.fahrenheit);
      expect(await UnitPrefs.loadSystem(), UnitSystem.us);
      expect(await UnitPrefs.loadTempUnit(), TempUnit.fahrenheit);
    });
  });
}
