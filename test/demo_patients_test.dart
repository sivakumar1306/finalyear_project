import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vital_monitoring/screens/fall_prediction/fall_prediction_widgets.dart';
import 'package:vital_monitoring/models/fall_prediction/context_factors.dart';
import 'package:vital_monitoring/models/fall_prediction/engine_outputs.dart';
import 'package:vital_monitoring/models/fall_prediction/prediction_result.dart';
import 'package:vital_monitoring/services/fall_prediction/demo_patients.dart';
import 'package:vital_monitoring/services/fall_prediction/fall_prediction_engine.dart';
import 'package:vital_monitoring/services/fall_prediction/layer1_physiology.dart' show BpSource;
import 'package:vital_monitoring/services/fall_prediction/layer3_motion.dart';
import 'package:vital_monitoring/services/fall_prediction/red_flag_override.dart';

class _NoEscalation extends EscalationService {
  @override
  void triggerAlert({required EscalationLadder ladder, required String reason}) =>
      fail('demo patients must not raise alerts: $reason');
}

class _NoCorroboration extends CorroborationService {
  @override
  Future<bool> verifyDualSource(CorroborationSource source) async => false;
}

Future<FallRiskScoreV2Result> _score(DemoPatient p, {List<FallEvent> extraFalls = const []}) async {
  final engine = FallPredictionEngine(
    redFlagService: RedFlagOverrideService(),
    escalationService: _NoEscalation(),
    corroborationService: _NoCorroboration(),
  );
  final i = p.engineInputs(extraFalls: extraFalls);
  return (await engine.calculateFRSv2(
    pData: i.pData,
    rData: i.rData,
    mData: i.mData,
    wData: i.wData,
    bpSource: BpSource.none,
    context: ContextFactors(),
    trailingFalls: i.falls,
  ))!;
}

void main() {
  DemoPatient byId(String id) => demoPatients.firstWhere((p) => p.id == id);

  test('the five demo patients land in the report tiers', () async {
    final expected = {
      'arun': FrsRiskBand.low,
      'meera': FrsRiskBand.moderate,
      'ravi': FrsRiskBand.low,
      'lakshmi': FrsRiskBand.high,
      'priya': FrsRiskBand.low,
    };
    for (final e in expected.entries) {
      final r = await _score(byId(e.key));
      // ignore: avoid_print
      print('${e.key}: FRS ${r.frs24.value.toStringAsFixed(1)}  Q ${r.coverageScore.q.toStringAsFixed(0)}');
      expect(r.frs24.value.riskBand, e.value, reason: e.key);
      expect(r.breakdown, isNotNull, reason: e.key);
    }
  });

  test('Ravi has the lowest data coverage (stale ring)', () async {
    final ravi = (await _score(byId('ravi'))).coverageScore.q;
    for (final p in demoPatients.where((p) => p.id != 'ravi')) {
      expect((await _score(p)).coverageScore.q, greaterThan(ravi), reason: p.id);
    }
  });

  test('a simulated fall raises the score', () async {
    final arun = byId('arun');
    final before = (await _score(arun)).frs24.value;
    final after = (await _score(arun, extraFalls: [FallEvent(timestamp: DateTime.now(), severity: 80)])).frs24.value;
    expect(after, greaterThan(before + 10));
  });

  testWidgets('demo card shows the score change and its actions', (tester) async {
    var falls = 0, back = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DemoPatientCard(
          patient: byId('lakshmi'),
          ownScore: 13.2,
          demoScore: 71.0,
          onAddFall: () => falls++,
          onBack: () => back++,
        ),
      ),
    ));
    expect(find.text('DEMO PATIENT · SYNTHETIC DATA'), findsOneWidget);
    expect(find.text('Your score 13  →  Lakshmi 71'), findsOneWidget);
    await tester.tap(find.text('Simulate a fall'));
    await tester.tap(find.text('Back to my data'));
    expect((falls, back), (1, 1));
  });
}
