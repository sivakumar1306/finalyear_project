import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sundr/screens/assist/cycle_chat_card.dart';
import 'package:sundr/screens/assist/key_change_card.dart';
import 'package:sundr/screens/health/activity_description_screen.dart';
import 'package:sundr/screens/health/womens_health_widgets.dart';
import 'package:sundr/screens/home/cards/home_insight_cards.dart';
import 'package:sundr/screens/home/cards/home_vitals_cards.dart';
import 'package:sundr/screens/home/side_panel.dart';
import 'package:sundr/screens/workouts/workouts_screen.dart';
import 'package:sundr/theme/app_theme.dart';
import 'package:sundr/widgets/glass_header.dart';
import 'package:sundr/widgets/chart_card.dart';
import 'package:sundr/widgets/chart_scrubber.dart';
import 'package:sundr/widgets/data_card.dart';
import 'package:sundr/widgets/date_scroll_row.dart';
import 'package:sundr/widgets/legend_dot.dart';
import 'package:sundr/widgets/metric_chart_card.dart';
import 'package:sundr/widgets/metric_stat_card.dart';
import 'package:sundr/widgets/real_time_card.dart';
import 'package:sundr/widgets/stat_card.dart';

/// Lays a tile out at a phone width and a text scale, and fails if Flutter
/// reports a RenderFlex overflow.
Future<void> _expectFits(
  WidgetTester tester,
  Widget child, {
  double width = 320,
  double scale = 1,
  double height = 900,
}) async {
  await tester.binding.setSurfaceSize(Size(width, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: Size(width, height),
        textScaler: TextScaler.linear(scale),
      ),
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('activity description chips fit a narrow phone', (tester) async {
    await _expectFits(tester, const ActivityDescriptionScreen(), width: 320);
    await _expectFits(
      tester,
      const ActivityDescriptionScreen(),
      width: 360,
      scale: 1.3,
    );
  });

  testWidgets('date strip fits at a larger text scale', (tester) async {
    await _expectFits(
      tester,
      DateScrollRow(selectedDate: DateTime(2026, 10, 8), onDateSelected: (_) {}),
      width: 320,
      scale: 1.3,
    );
  });

  testWidgets('three metric tiles fit side by side', (tester) async {
    Widget row(double width) => SizedBox(
          width: width,
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: MetricStatCard(
                  label: 'AVG BLOOD OXYGEN',
                  value: '98',
                  unit: 'percent',
                  caption: 'Within range',
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: MetricStatCard(
                  label: 'DEEP SLEEP',
                  value: '2h 48m',
                  unit: '',
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: MetricStatCard(
                  label: 'TOTAL MILEAGE',
                  value: '12.34',
                  unit: 'km',
                ),
              ),
            ],
          ),
        );

    await _expectFits(tester, row(320), width: 320);
    await _expectFits(tester, row(360), width: 360, scale: 1.3);
  });

  testWidgets('stat, data and realtime cards fit a narrow width', (tester) async {
    await _expectFits(
      tester,
      const StatCard(label: 'TOTAL MILEAGE', value: '12.34', unit: 'kilometers'),
      width: 110,
    );
    await _expectFits(
      tester,
      const DataCard(label: 'Blood pressure reading', value: '128/82', unit: 'mmHg'),
      width: 160,
      scale: 1.3,
    );
    await _expectFits(
      tester,
      const RealTimeCard(
        title: 'Real Time Blood Pressure',
        value: '128/82',
        unit: 'mmHg',
        accent: AppTheme.bpColor,
        measuring: false,
        enabled: true,
      ),
      width: 320,
      scale: 1.3,
    );
  });

  testWidgets('chart headers and legends fit a narrow phone', (tester) async {
    const footer = Wrap(
      spacing: 10,
      runSpacing: 6,
      children: [
        LegendDot(color: AppTheme.danger, label: 'Very Low'),
        LegendDot(color: AppTheme.stressColor, label: 'Low'),
        LegendDot(color: AppTheme.amber, label: 'Moderate'),
        LegendDot(color: AppTheme.success, label: 'Good'),
        LegendDot(color: AppTheme.hrvColor, label: 'Excellent'),
      ],
    );
    await _expectFits(
      tester,
      ScrubbableChart(
        values: const [40, 55, 70, 80, 62],
        maxY: 100,
        yLines: const [100, 75, 50, 25],
        yLabels: const ['100', '75', '50', '25'],
        xLabels: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
        headerLabel: 'LAST 7 DAYS TREND',
        rangeLabel: 'avg 72 · range 40-80',
        valueLabelBuilder: (i, v) => 'Wed • $v bpm',
        footer: footer,
        barColor: AppTheme.hrvColor,
      ),
      width: 320,
      scale: 1.3,
    );
    await _expectFits(
      tester,
      MetricChartCard(
        headerLabel: 'SLEEP STAGES',
        rangeLabel: '10:45 pm – 6:30 am · score 86',
        yLabels: const ['Awake', 'REM', 'Light', 'Deep'],
        xLabels: const ['10pm', '12am', '3am', '6am'],
        child: const SizedBox.expand(),
      ),
      width: 320,
      scale: 1.3,
    );
    await _expectFits(
      tester,
      ChartCard(
        headerLabel: 'HEART RATE',
        rangeLabel: 'min 52 · max 148 bpm',
        values: const [60, 70, 80],
        xLabels: const ['12am', '6am', '12pm', '6pm', '12am'],
        yLabels: const ['160', '120', '80', '40'],
        loading: false,
        barColor: AppTheme.hrColor,
        createPainter: (_) => _EmptyPainter(),
      ),
      width: 320,
    );
  });

  testWidgets('home activity and metric tiles fit', (tester) async {
    await _expectFits(
      tester,
      FigmaExpandedCard(
        orbColor: AppTheme.focus,
        height: 158,
        icon: Icons.directions_walk,
        title: 'ACTIVITY',
        status: 'Moderately active',
        value: const Text('100 pts'),
        chart: const SizedBox.expand(),
        footnoteLead: '12,345 / 10K steps',
        footnoteRest: ' · 12.34 km · 123 min active',
      ),
      width: 320,
      scale: 1.3,
    );
    await _expectFits(
      tester,
      SizedBox(
        width: 320,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: HomeCard(
                  label: 'Blood Oxygen',
                  value: '98',
                  unit: '%',
                  status: 'Normal range',
                  statusColor: AppTheme.spo2Color,
                  orbColor: AppTheme.spo2Color,
                  sparkData: const [0.2, 0.5, 0.4, 0.8],
                  connected: true,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: MiniCard(
                  label: "Women's Health",
                  value: 'Day 14 • Ovulation',
                  sub: '85% AWHE Confidence',
                  color: AppTheme.womenColor,
                  icon: Icons.woman,
                ),
              ),
            ],
          ),
        ),
      ),
      width: 320,
      scale: 1.3,
    );
  });

  testWidgets('cycle prediction columns fit a third of a narrow phone', (tester) async {
    await _expectFits(
      tester,
      const Row(
        children: [
          Expanded(
            child: PredictionCol(
              label: 'Next Period',
              value: '12',
              valueSuffix: ' Days',
              subtitle: 'Till Oct 20',
            ),
          ),
          Expanded(
            child: PredictionCol(
              label: 'Fertility',
              value: 'Inactive',
              subtitle: 'Till Oct 18',
            ),
          ),
          Expanded(
            child: PredictionCol(
              label: 'Phase',
              value: 'Follicular',
              subtitle: 'Till Oct 16',
            ),
          ),
        ],
      ),
      width: 320,
      scale: 1.3,
    );
  });

  testWidgets('headers, banners and chat tiles fit a narrow phone', (tester) async {
    await _expectFits(
      tester,
      const GlassHeader(title: 'Schedule meditation'),
      width: 320,
      scale: 1.5,
    );
    await _expectFits(
      tester,
      SidePanelItem(label: 'Goal Setting', onTap: () {}),
      width: 200,
      scale: 1.4,
    );
    await _expectFits(
      tester,
      FallEventBanner(countdown: 30, onCardTap: () {}, onCancel: () {}),
      width: 320,
      scale: 1.3,
    );
    await _expectFits(
      tester,
      CycleChatCard(
        data: const {
          'period_start': 'Oct 1',
          'cycle_length': 28,
          'period_length': 5,
          'current_day': 14,
          'phase': 'Follicular Phase',
          'days_until_next': 14,
        },
        onTap: () {},
      ),
      width: 320,
      scale: 1.3,
    );
    await _expectFits(
      tester,
      KeyChangeCard(
        title: 'Resting heart rate is higher than usual',
        delta: '+18 bpm',
        subtitle: 'Compared with your 7-day baseline',
        onTap: () {},
      ),
      width: 280,
      scale: 1.3,
    );
  });

  testWidgets('strength training workout pads fit a narrow phone', (tester) async {
    const row = {
      'workout_type': 'Strength Training',
      'started_at': '2026-10-09T18:42:00',
      'duration_s': 3725,
      'calories': 480,
      'avg_hr': 142,
      'steps': 1860,
      'distance_m': 2400,
      'source': 'ring',
    };
    await _expectFits(
      tester,
      const WorkoutSpotlightCard(row: row),
      width: 200,
      scale: 1,
    );
    await _expectFits(
      tester,
      const WorkoutSpotlightCard(row: row),
      width: 200,
      scale: 1.3,
      height: 420,
    );
    await _expectFits(
      tester,
      const WorkoutHistoryTile(row: row),
      width: 320,
      scale: 1.3,
    );
  });
}

class _EmptyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
