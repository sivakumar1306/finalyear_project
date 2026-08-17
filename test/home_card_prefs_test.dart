import 'package:flutter_test/flutter_test.dart';
import 'package:sundr/screens/home/home_card_id.dart';
import 'package:sundr/services/home_card_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('loadOrder defaults to full enum list', () async {
    final order = await HomeCardPrefs.loadOrder();
    expect(order, HomeCardId.values);
  });

  test('order round-trip preserves sequence', () async {
    final custom = [
      HomeCardId.heartRate,
      HomeCardId.bloodPressure,
      HomeCardId.activity,
      ...HomeCardId.values.where(
        (id) =>
            id != HomeCardId.heartRate &&
            id != HomeCardId.bloodPressure &&
            id != HomeCardId.activity,
      ),
    ];
    await HomeCardPrefs.saveOrder(custom);
    final loaded = await HomeCardPrefs.loadOrder();
    expect(loaded.take(3).toList(), [
      HomeCardId.heartRate,
      HomeCardId.bloodPressure,
      HomeCardId.activity,
    ]);
    expect(loaded.toSet(), HomeCardId.values.toSet());
  });

  test('legacy composite ids expand on load', () async {
    SharedPreferences.setMockInitialValues({
      'home_card_order': <String>['alarmActivity', 'sleepHrv', 'temperature'],
    });
    final order = await HomeCardPrefs.loadOrder();
    expect(order.contains(HomeCardId.alarms), isTrue);
    expect(order.contains(HomeCardId.activity), isTrue);
    expect(order.contains(HomeCardId.sleep), isTrue);
    expect(order.contains(HomeCardId.hrv), isTrue);
    expect(order.contains(HomeCardId.temperature), isTrue);
    expect(order.length, HomeCardId.values.length);
  });

  test('hidden and expanded round-trip', () async {
    await HomeCardPrefs.saveHidden({HomeCardId.womensHealth, HomeCardId.stress});
    final hidden = await HomeCardPrefs.loadHidden();
    expect(hidden, {HomeCardId.womensHealth, HomeCardId.stress});

    await HomeCardPrefs.saveExpanded({HomeCardId.activity});
    final expanded = await HomeCardPrefs.loadExpanded();
    expect(expanded, {HomeCardId.activity});
  });

  test('loadExpanded defaults alarms when unset', () async {
    final expanded = await HomeCardPrefs.loadExpanded();
    expect(expanded, {HomeCardId.alarms});
  });

  test('compact mode round-trip', () async {
    expect(await HomeCardPrefs.loadCompactMode(), isFalse);
    await HomeCardPrefs.saveCompactMode(true);
    expect(await HomeCardPrefs.loadCompactMode(), isTrue);

    await HomeCardPrefs.saveCompact({HomeCardId.heartRate});
    expect(await HomeCardPrefs.loadCompact(), {HomeCardId.heartRate});
  });
}
