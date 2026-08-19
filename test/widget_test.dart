import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sundr/widgets/data_card.dart';
import 'package:sundr/_deprecated/stat_card.dart';
import 'package:sundr/_deprecated/status_badge.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('StatusBadge', () {
    testWidgets('shows Connected when connected', (tester) async {
      await tester.pumpWidget(_wrap(const StatusBadge(connected: true)));
      expect(find.text('Connected'), findsOneWidget);
    });

    testWidgets('shows Disconnected when not connected', (tester) async {
      await tester.pumpWidget(_wrap(const StatusBadge(connected: false)));
      expect(find.text('Disconnected'), findsOneWidget);
    });
  });

  group('DataCard', () {
    testWidgets('renders label, value and unit', (tester) async {
      await tester.pumpWidget(_wrap(
        const DataCard(label: 'Blood Sugar', value: '5.4', unit: 'mmol/L'),
      ));
      expect(find.text('Blood Sugar'), findsOneWidget);
      expect(find.text('5.4'), findsOneWidget);
      expect(find.text('mmol/L'), findsOneWidget);
    });

    testWidgets('renders icon when provided', (tester) async {
      await tester.pumpWidget(_wrap(
        const DataCard(
          label: 'Blood Lipids',
          value: '--',
          unit: 'mmol/L',
          icon: Icons.water_drop,
        ),
      ));
      expect(find.byIcon(Icons.water_drop), findsOneWidget);
    });
  });

  group('StatCard', () {
    testWidgets('renders label, value and unit', (tester) async {
      await tester.pumpWidget(_wrap(
        const StatCard(label: 'HRV', value: '67', unit: 'ms'),
      ));
      expect(find.text('HRV'), findsOneWidget);
      expect(find.text('67'), findsOneWidget);
      expect(find.text('ms'), findsOneWidget);
    });

    testWidgets('has no dead know-more affordance', (tester) async {
      await tester.pumpWidget(_wrap(
        const StatCard(label: 'HRV', value: '67', unit: 'ms'),
      ));
      expect(find.text('know more >'), findsNothing);
    });
  });
}