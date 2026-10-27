import '../../models/fall_prediction/layer_inputs.dart';
import 'layer2_recovery.dart';
import 'layer3_motion.dart';

/// The five synthetic demo users of the report (Section 3.3.2, Table 3.2),
/// as fixed readings for the on-phone engine. Picking one on the Fall Risk
/// tab replaces the live ring data until "My data" is chosen again; nothing
/// is stored or uploaded.
class DemoPatient {
  final String id;
  final String name;
  final String summary;

  // Physiology: today's readings and the personal baselines.
  final Layer1PhysiologyData physiology;

  // Recovery: last night and today.
  final double? sleepMinutes;
  final double? deepSleepMinutes;
  final int? stepsToday;

  // Motion: the last full day's steps against the 28-day baseline, and fall
  // alerts in the last 14 days.
  final double? stepsLastDay;
  final double? stepsMedian;
  final double? stepsSpread;
  final int nearFalls14d;

  // Falls in the past year, as days ago.
  final List<int> fallDaysAgo;

  // Women's health (cycle day; null when not applicable).
  final int? cycleDay;

  const DemoPatient({
    required this.id,
    required this.name,
    required this.summary,
    required this.physiology,
    this.sleepMinutes,
    this.deepSleepMinutes,
    this.stepsToday,
    this.stepsLastDay,
    this.stepsMedian,
    this.stepsSpread,
    this.nearFalls14d = 0,
    this.fallDaysAgo = const [],
    this.cycleDay,
  });

  List<FallEvent> falls(DateTime now) => [
        for (final d in fallDaysAgo)
          FallEvent(timestamp: now.subtract(Duration(days: d)), severity: 80),
      ];

  /// Engine inputs for this patient; [extraFalls] are falls added from the
  /// "Simulate a fall" button (they count as recent fall alerts too).
  ({
    Layer1PhysiologyData pData,
    Layer2RecoveryData rData,
    Layer3MotionData mData,
    Layer4WomensHealthData wData,
    List<FallEvent> falls,
  }) engineInputs({List<FallEvent> extraFalls = const [], DateTime? now}) {
    final recovery = recoveryFromReadings(
      sleepMinutes: sleepMinutes,
      deepSleepMinutes: deepSleepMinutes,
      steps: stepsToday,
      hrv: physiology.hrv,
    );
    final allFalls = [...extraFalls, ...falls(now ?? DateTime.now())];
    return (
      pData: physiology,
      rData: recovery.$1,
      mData: Layer3MotionData(
        steps: stepsLastDay,
        stepsMedian: stepsMedian,
        stepsSpread: stepsSpread,
        nearFalls14d: nearFalls14d + extraFalls.length,
        fh: allFalls.length.toDouble(),
        actExp: recovery.$2 ?? const ActivityExposure(100.0),
      ),
      wData: womensHealth,
      falls: allFalls,
    );
  }

  Layer4WomensHealthData get womensHealth => cycleDay == null
      ? Layer4WomensHealthData(
          isApplicable: false,
          hasConsentedToWomensHealth: false,
          cycleState: CycleState.optedOut,
          daysSinceLastPeriod: 0,
          cycleLength: 28,
          isPMS: false,
        )
      : Layer4WomensHealthData(
          isApplicable: true,
          hasConsentedToWomensHealth: true,
          cycleState: CycleState.active,
          daysSinceLastPeriod: cycleDay!,
          cycleLength: 28,
          isPMS: cycleDay! >= 21 && cycleDay! <= 28,
        );
}

final List<DemoPatient> demoPatients = [
  DemoPatient(
    id: 'arun',
    name: 'Arun',
    summary: '29 M · stable and healthy',
    physiology: Layer1PhysiologyData(
      hr: 66, hrv: 54, bp: null, spo2: 98, temp: 36.5, sys: 118, dia: 76,
      baselines: const Layer1Baselines(
        rolling14DayMedianHR: 63, rolling28DayMeanHRV: 56, rolling28DayStdDevHRV: 7,
        baselineAdjustedTemp: 36.5, baselineSys: 118, baselineDia: 76,
      ),
    ),
    sleepMinutes: 460, deepSleepMinutes: 95, stepsToday: 9400,
    stepsLastDay: 8100, stepsMedian: 9000, stepsSpread: 900,
  ),
  DemoPatient(
    id: 'meera',
    name: 'Meera',
    summary: '31 F · luteal phase, poor recovery, one past fall',
    physiology: Layer1PhysiologyData(
      hr: 84, hrv: 36, bp: null, spo2: 96, temp: 36.9, sys: 112, dia: 72,
      baselines: const Layer1Baselines(
        rolling14DayMedianHR: 70, rolling28DayMeanHRV: 52, rolling28DayStdDevHRV: 7,
        baselineAdjustedTemp: 36.5, baselineSys: 114, baselineDia: 74,
      ),
    ),
    sleepMinutes: 290, deepSleepMinutes: 35, stepsToday: 4200,
    stepsLastDay: 5600, stepsMedian: 7500, stepsSpread: 800,
    fallDaysAgo: const [30],
    cycleDay: 22,
  ),
  DemoPatient(
    id: 'ravi',
    name: 'Ravi',
    summary: '67 M · ring not synced for four days',
    physiology: Layer1PhysiologyData(
      hr: 74, hrv: null, bp: null, spo2: 96, temp: null,
      baselines: const Layer1Baselines(
        rolling14DayMedianHR: 67, rolling28DayMeanHRV: 40, rolling28DayStdDevHRV: 6,
        baselineAdjustedTemp: 36.4,
      ),
    ),
    stepsLastDay: 6100, stepsMedian: 6200, stepsSpread: 700,
  ),
  DemoPatient(
    id: 'lakshmi',
    name: 'Lakshmi',
    summary: '72 F · three falls this year, a recent near-fall',
    physiology: Layer1PhysiologyData(
      hr: 82, hrv: 27, bp: null, spo2: 94, temp: 36.3, sys: 108, dia: 66,
      baselines: const Layer1Baselines(
        rolling14DayMedianHR: 72, rolling28DayMeanHRV: 36, rolling28DayStdDevHRV: 5,
        baselineAdjustedTemp: 36.4, baselineSys: 124, baselineDia: 78,
      ),
    ),
    sleepMinutes: 320, deepSleepMinutes: 30, stepsToday: 1800,
    stepsLastDay: 2300, stepsMedian: 4600, stepsSpread: 600,
    nearFalls14d: 1,
    fallDaysAgo: const [18, 110, 240],
  ),
  DemoPatient(
    id: 'priya',
    name: 'Priya',
    summary: '27 F · healthy, luteal phase',
    physiology: Layer1PhysiologyData(
      hr: 67, hrv: 52, bp: null, spo2: 98, temp: 36.8, sys: 110, dia: 70,
      baselines: const Layer1Baselines(
        rolling14DayMedianHR: 64, rolling28DayMeanHRV: 55, rolling28DayStdDevHRV: 8,
        baselineAdjustedTemp: 36.5, baselineSys: 110, baselineDia: 70,
      ),
    ),
    sleepMinutes: 470, deepSleepMinutes: 90, stepsToday: 8700,
    stepsLastDay: 8800, stepsMedian: 8500, stepsSpread: 800,
    cycleDay: 23,
  ),
];
