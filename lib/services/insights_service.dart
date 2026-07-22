import '../services/supabase_service.dart';

/// One segment of the AI-assist headline. [highlight] renders in gold.
class HeadlineSpan {
  final String text;
  final bool highlight;
  const HeadlineSpan(this.text, {this.highlight = false});
}

/// A single "key changes" card's data.
class InsightMetric {
  final String title;
  final String delta; // e.g. "+22 min", "+6", "--"
  final String subtitle;
  final String route;
  final bool hasData;

  const InsightMetric({
    required this.title,
    required this.delta,
    required this.subtitle,
    required this.route,
    required this.hasData,
  });
}

/// Full computed insight for the AI-assist header: headline, subtext and the
/// two key-change cards (Sleep, Blood pressure), all derived from real
/// Supabase history instead of hardcoded strings.
class InsightsResult {
  final String eyebrow; // e.g. "YOUR LAST 30 DAYS"
  final List<HeadlineSpan> headline;
  final String subtext;
  final InsightMetric sleep;
  final InsightMetric bloodPressure;

  const InsightsResult({
    required this.eyebrow,
    required this.headline,
    required this.subtext,
    required this.sleep,
    required this.bloodPressure,
  });

  factory InsightsResult.empty(String rangeLabel) => InsightsResult(
    eyebrow: 'YOUR LAST $rangeLabel'.toUpperCase(),
    headline: const [HeadlineSpan('Not enough data yet')],
    subtext:
        'Wear your ring for a few more days and check back — we\'ll surface what\'s changed.',
    sleep: const InsightMetric(
      title: 'Sleep',
      delta: '--',
      subtitle: 'Not enough data yet',
      route: '/sleep',
      hasData: false,
    ),
    bloodPressure: const InsightMetric(
      title: 'Blood pressure',
      delta: '--',
      subtitle: 'Not enough data yet',
      route: '/blood-pressure',
      hasData: false,
    ),
  );
}

class InsightsService {
  /// range in days: 7, 30, or 90 (matches the segmented control on screen).
  static Future<InsightsResult> compute(int rangeDays) async {
    final rangeLabel = switch (rangeDays) {
      7 => '7 DAYS',
      90 => '90 DAYS',
      _ => '30 DAYS',
    };
    final periodWord = switch (rangeDays) {
      7 => 'this week',
      90 => 'over the last 90 days',
      _ => 'this month',
    };

    final user = SupabaseService.currentUser;
    if (user == null) return InsightsResult.empty(rangeLabel);

    final now = DateTime.now();
    final from = now.subtract(Duration(days: rangeDays));

    List<Map<String, dynamic>> sleepRows = [];
    List<Map<String, dynamic>> bpRows = [];
    try {
      sleepRows = await SupabaseService.getSleepHistory(
        userId: user.id,
        from: from,
        to: now,
      );
    } catch (_) {}
    try {
      bpRows = await SupabaseService.getBpReadings(
        userId: user.id,
        from: from,
        to: now,
      );
    } catch (_) {}

    final sleepTrend = _sleepTrend(sleepRows);
    final bpTrend = _bpTrend(bpRows);

    if (!sleepTrend.hasEnoughData && !bpTrend.hasEnoughData) {
      return InsightsResult.empty(rangeLabel);
    }

    final sleepCard = InsightMetric(
      title: 'Sleep',
      delta: sleepTrend.hasEnoughData ? sleepTrend.deltaLabel : '--',
      subtitle: sleepTrend.hasEnoughData
          ? sleepTrend.subtitle
          : 'Not enough data yet',
      route: '/sleep',
      hasData: sleepTrend.hasEnoughData,
    );
    final bpCard = InsightMetric(
      title: 'Blood pressure',
      delta: bpTrend.hasEnoughData ? bpTrend.deltaLabel : '--',
      subtitle: bpTrend.hasEnoughData
          ? bpTrend.subtitle
          : 'Not enough data yet',
      route: '/blood-pressure',
      hasData: bpTrend.hasEnoughData,
    );

    final headline = _buildHeadline(sleepTrend: sleepTrend, bpTrend: bpTrend);
    final subtext = _buildSubtext(
      sleepTrend: sleepTrend,
      bpTrend: bpTrend,
      periodWord: periodWord,
    );

    return InsightsResult(
      eyebrow: 'YOUR LAST $rangeLabel',
      headline: headline,
      subtext: subtext,
      sleep: sleepCard,
      bloodPressure: bpCard,
    );
  }

  // ── Sleep trend ────────────────────────────────────────────────────────────

  static _SleepTrend _sleepTrend(List<Map<String, dynamic>> rows) {
    final durations = rows
        .map((r) => (r['total_duration'] as num? ?? 0).toInt())
        .where((d) => d > 0)
        .toList();
    if (durations.length < 4) {
      return const _SleepTrend(hasEnoughData: false, deltaMinutes: 0);
    }
    final mid = durations.length ~/ 2;
    final firstHalf = durations.sublist(0, mid);
    final secondHalf = durations.sublist(mid);
    final avgFirst = firstHalf.reduce((a, b) => a + b) / firstHalf.length;
    final avgSecond = secondHalf.reduce((a, b) => a + b) / secondHalf.length;
    final deltaMin = ((avgSecond - avgFirst) / 60).round();
    return _SleepTrend(hasEnoughData: true, deltaMinutes: deltaMin);
  }

  // ── Blood pressure trend ───────────────────────────────────────────────────

  static _BpTrend _bpTrend(List<Map<String, dynamic>> rows) {
    final systolics = rows
        .map((r) => (r['systolic'] as num? ?? 0).toInt())
        .where((s) => s > 0)
        .toList();
    if (systolics.length < 4) {
      return const _BpTrend(
        hasEnoughData: false,
        deltaSystolic: 0,
        recentAvgSystolic: 0,
      );
    }
    final mid = systolics.length ~/ 2;
    final firstHalf = systolics.sublist(0, mid);
    final secondHalf = systolics.sublist(mid);
    final avgFirst = firstHalf.reduce((a, b) => a + b) / firstHalf.length;
    final avgSecond = secondHalf.reduce((a, b) => a + b) / secondHalf.length;
    final delta = (avgSecond - avgFirst).round();
    return _BpTrend(
      hasEnoughData: true,
      deltaSystolic: delta,
      recentAvgSystolic: avgSecond.round(),
    );
  }

  // ── Headline / subtext composition ─────────────────────────────────────────

  static List<HeadlineSpan> _buildHeadline({
    required _SleepTrend sleepTrend,
    required _BpTrend bpTrend,
  }) {
    final sleepImproving =
        sleepTrend.hasEnoughData && sleepTrend.deltaMinutes >= 5;
    final sleepWorsening =
        sleepTrend.hasEnoughData && sleepTrend.deltaMinutes <= -5;
    final bpConcern =
        bpTrend.hasEnoughData && bpTrend.status != _BpStatus.normal;
    final bpStatusWord = bpTrend.status == _BpStatus.high ? 'high' : 'low';

    if (sleepImproving && bpConcern) {
      return [
        const HeadlineSpan('Your sleep is improving, but blood pressure is '),
        HeadlineSpan(bpStatusWord, highlight: true),
      ];
    }
    if (sleepWorsening && bpConcern) {
      return [
        const HeadlineSpan(
          'Your sleep needs attention, and blood pressure is ',
        ),
        HeadlineSpan(bpStatusWord, highlight: true),
      ];
    }
    if (bpConcern) {
      return [
        const HeadlineSpan('Your blood pressure is '),
        HeadlineSpan(bpStatusWord, highlight: true),
        const HeadlineSpan(' this period'),
      ];
    }
    if (sleepImproving) {
      return [
        const HeadlineSpan('Your sleep is '),
        const HeadlineSpan('improving', highlight: true),
        const HeadlineSpan(', keep it up'),
      ];
    }
    if (sleepWorsening) {
      return [
        const HeadlineSpan('Your sleep '),
        const HeadlineSpan('needs attention', highlight: true),
      ];
    }
    return [
      const HeadlineSpan('Your vitals look '),
      const HeadlineSpan('stable', highlight: true),
    ];
  }

  static String _buildSubtext({
    required _SleepTrend sleepTrend,
    required _BpTrend bpTrend,
    required String periodWord,
  }) {
    final parts = <String>[];
    if (sleepTrend.hasEnoughData) {
      final m = sleepTrend.deltaMinutes;
      if (m.abs() >= 5) {
        parts.add(
          m > 0
              ? 'Sleep is up ${m.abs()} min on average'
              : 'Sleep is down ${m.abs()} min on average',
        );
      } else {
        parts.add('Sleep has held steady');
      }
    }
    if (bpTrend.hasEnoughData) {
      switch (bpTrend.status) {
        case _BpStatus.high:
          parts.add('systolic is trending high $periodWord');
          break;
        case _BpStatus.low:
          parts.add('systolic is trending low $periodWord');
          break;
        case _BpStatus.normal:
          parts.add('blood pressure is within a normal range');
          break;
      }
    }
    final joined = parts.isEmpty
        ? 'Keep wearing your ring to build a clearer picture.'
        : '${parts.join(' and ')}. Tap any change below to dig in.';
    // Capitalise first letter.
    return joined[0].toUpperCase() + joined.substring(1);
  }
}

enum _BpStatus { high, low, normal }

class _SleepTrend {
  final bool hasEnoughData;
  final int deltaMinutes;
  const _SleepTrend({required this.hasEnoughData, required this.deltaMinutes});

  String get deltaLabel =>
      deltaMinutes >= 0 ? '+$deltaMinutes min' : '$deltaMinutes min';

  String get subtitle => deltaMinutes >= 0
      ? '${deltaMinutes.abs()} minutes more sleep on average'
      : '${deltaMinutes.abs()} minutes less sleep on average';
}

class _BpTrend {
  final bool hasEnoughData;
  final int deltaSystolic;
  final int recentAvgSystolic;
  const _BpTrend({
    required this.hasEnoughData,
    required this.deltaSystolic,
    required this.recentAvgSystolic,
  });

  _BpStatus get status {
    if (recentAvgSystolic >= 130) return _BpStatus.high;
    if (recentAvgSystolic > 0 && recentAvgSystolic < 90) return _BpStatus.low;
    return _BpStatus.normal;
  }

  String get deltaLabel =>
      deltaSystolic >= 0 ? '+$deltaSystolic' : '$deltaSystolic';

  String get subtitle => deltaSystolic >= 0
      ? 'Systolic trending up across the period'
      : 'Systolic trending down across the period';
}
