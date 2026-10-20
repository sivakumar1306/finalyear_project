import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vital_monitoring/config.dart';
import 'package:vital_monitoring/providers/ble_provider.dart';
import 'package:vital_monitoring/screens/home/cards/home_insight_cards.dart';

class _FakeBle extends BleProvider {
  _FakeBle({required this.connected, required this.name, this.level = -1});
  final bool connected;
  final String name;
  final int level;
  bool disconnected = false;

  @override
  bool get isConnected => connected;
  @override
  bool get isReconnecting => false;
  @override
  String get deviceName => name;
  @override
  String get deviceAddress => name.isEmpty ? '' : 'AA:BB:CC:DD:EE:FF';
  @override
  int get battery => level;
  @override
  Future<void> disconnect() async => disconnected = true;
}

Future<void> _pump(WidgetTester tester, BleProvider ble) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: RingStatusCard(ble: ble),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel(AppConfig.bleMethodChannel), (_) async => null);
    messenger.setMockStreamHandler(
        const EventChannel(AppConfig.bleEventChannel), MockStreamHandler.inline(onListen: (_, _) {}));
  });

  testWidgets('connected ring shows battery percent and Disconnect only', (tester) async {
    final ble = _FakeBle(connected: true, name: 'R09_AC12', level: 82);
    await _pump(tester, ble);
    expect(find.text('R09_AC12'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('82%'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
    expect(find.text('Pair Ring'), findsNothing);
    expect(find.text('Pair again'), findsNothing);

    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Disconnect'));
    await tester.pumpAndSettle();
    expect(ble.disconnected, isTrue);
  });

  testWidgets('paired but offline ring offers Pair again and Disconnect', (tester) async {
    await _pump(tester, _FakeBle(connected: false, name: 'R09_AC12', level: 15));
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('15%'), findsOneWidget);
    expect(find.text('Pair again'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
  });

  testWidgets('no ring paired offers Pair Ring only', (tester) async {
    await _pump(tester, _FakeBle(connected: false, name: ''));
    expect(find.text('No ring paired'), findsOneWidget);
    expect(find.text('Pair Ring'), findsOneWidget);
    expect(find.text('Disconnect'), findsNothing);
    expect(find.textContaining('%'), findsNothing);
  });
}
