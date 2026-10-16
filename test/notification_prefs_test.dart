import 'package:flutter_test/flutter_test.dart';
import 'package:vital_monitoring/services/notification_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults match expected alert keys', () {
    expect(NotificationPrefs.defaults['High Heart Rate'], isTrue);
    expect(NotificationPrefs.defaults['Low Battery'], isTrue);
    expect(NotificationPrefs.defaults['Low Heart Rate'], isFalse);
    expect(NotificationPrefs.defaults.containsKey('High BP'), isTrue);
  });

  test('load returns defaults when unset', () async {
    final map = await NotificationPrefs.load();
    expect(map, NotificationPrefs.defaults);
  });

  test('setEnabled overrides a single key', () async {
    await NotificationPrefs.setEnabled('Low Heart Rate', true);
    expect(await NotificationPrefs.isEnabled('Low Heart Rate'), isTrue);
    expect(await NotificationPrefs.isEnabled('High Heart Rate'), isTrue);

    final map = await NotificationPrefs.load();
    expect(map['Low Heart Rate'], isTrue);
    expect(map['High BP'], isFalse);
  });

  test('unknown key isEnabled falls back to false', () async {
    expect(await NotificationPrefs.isEnabled('Not A Real Alert'), isFalse);
  });
}
