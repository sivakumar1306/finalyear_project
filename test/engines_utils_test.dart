import 'package:flutter_test/flutter_test.dart';
import 'package:sundr/utils/date_keys.dart';
import 'package:sundr/utils/formatters.dart';
import 'package:sundr/utils/hourly_aggregator.dart';
import 'package:sundr/utils/trend_math.dart';
import 'package:sundr/utils/scrub_helper.dart';
import 'package:sundr/services/health_engine/sleep_engine.dart';
import 'package:sundr/services/health_engine/activity_engine.dart';
import 'package:sundr/services/health_engine/cycle_engine.dart';
import 'package:sundr/services/history_service.dart';
import 'package:sundr/services/measurement_flow.dart';

void main() {
  group('DateKeys', () {
    test('fmt zero-pads', () {
      expect(DateKeys.fmt(DateTime(2026, 1, 5)), '2026-01-05');
    });
    test('isToday true/false', () {
      expect(DateKeys.isToday(DateTime.now()), true);
      expect(DateKeys.isToday(DateTime(2000, 1, 1)), false);
    });
    test('dayIndexFor today 0', () {
      expect(DateKeys.dayIndexFor(DateTime.now()), 0);
    });
    test('trendXLabels length 7', () {
      expect(DateKeys.trendXLabels().length, 7);
    });
  });

  group('Formatters', () {
    test('sleepDuration', () {
      expect(Formatters.sleepDuration(0), '--');
      expect(Formatters.sleepDuration(3600), '1h');
      expect(Formatters.sleepDuration(3900), '1h 5m');
    });
    test('hourLabel', () {
      expect(Formatters.hourLabel(0), '12am');
      expect(Formatters.hourLabel(12), '12pm');
      expect(Formatters.hourLabel(13), '1pm');
    });
    test('fixed caps fractional digits at 2', () {
      expect(Formatters.fixed(36.6666667), '36.67');
      expect(Formatters.fixed(70), '70');
      expect(Formatters.fixed(1.2), '1.2');
      expect(Formatters.fixed(-0.001), '0');
    });
  });

  group('HourlyAggregator', () {
    test('aggregateInt buckets by hour', () {
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day, 10, 15);
      final readings = [
        {'valueBpm': 70, 'measuredAt': day.millisecondsSinceEpoch},
        {'valueBpm': 80, 'measuredAt': day.millisecondsSinceEpoch + 1000},
      ];
      final hourly = HourlyAggregator.aggregateInt(readings, valueKey: 'valueBpm');
      expect(hourly[10], 75);
      expect(hourly[11], 0);
    });
  });

  group('TrendMath', () {
    test('avg/min/max', () {
      expect(TrendMath.avg([1, 2, 3]), 2);
      expect(TrendMath.minVal([3, 1, 2]), 1);
      expect(TrendMath.maxVal([3, 1, 2]), 3);
    });
  });

  group('ScrubHelper', () {
    test('initialIndex last non-zero', () {
      expect(ScrubHelper.initialIndex([0, 5, 0, 7, 0]), 3);
      expect(ScrubHelper.initialIndex([0, 0]), 0);
    });
    test('indexFromDx', () {
      expect(ScrubHelper.indexFromDx(50, 100, 10), 5);
    });
  });

  group('SleepEngine', () {
    test('parseSegments old proto', () {
      final segs = SleepEngine.parseSegments([
        {'sleepStart': 1000, 'sleepEnd': 2000, 'type': 0},
      ]);
      expect(segs.length, 1);
      expect(segs.first['type'], 0);
    });
    test('efficiency', () {
      expect(SleepEngine.efficiency(3600, 1000, 8200), greaterThan(0));
      expect(SleepEngine.efficiency(0, 0, 0), 0);
    });
  });

  group('ActivityEngine', () {
    test('normalizeCalories', () {
      expect(ActivityEngine.normalizeCalories(2142, 500), 2);
      expect(ActivityEngine.normalizeCalories(0, 0), 0);
    });
  });

  group('CycleEngine', () {
    test('phaseName', () {
      expect(CycleEngine.phaseName(3, 5, 28), 'Menstruation');
      expect(CycleEngine.phaseName(10, 5, 28), 'Follicular');
      expect(CycleEngine.phaseName(15, 5, 28), 'Ovulating');
      expect(CycleEngine.phaseName(25, 5, 28), 'Luteal');
    });
  });

  group('HistoryService', () {
    test('last7IntSeries', () {
      final now = DateTime.now();
      final key =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final rows = [
        {'date': key, 'avg_hr': 72}
      ];
      final series = HistoryService.last7IntSeries(rows, 'avg_hr', now: now);
      expect(series.length, 7);
      expect(series.last, 72);
    });
  });

  group('MeasurementFlow', () {
    test('isValidHr', () {
      expect(MeasurementFlow.isValidHr(70), true);
      expect(MeasurementFlow.isValidHr(10), false);
    });
    test('extractInt tries keys', () {
      expect(MeasurementFlow.extractInt({'a': 0, 'b': 5}, ['a', 'b']), 5);
    });
  });
}
