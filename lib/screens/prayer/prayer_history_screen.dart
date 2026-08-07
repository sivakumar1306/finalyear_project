import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';

/// Screen displaying Prayer Session History with interactive trend charts and session details
/// fetched from Supabase `workouts` table (workout_type = 'Prayer').
class PrayerHistoryScreen extends StatefulWidget {
  const PrayerHistoryScreen({super.key});

  @override
  State<PrayerHistoryScreen> createState() => _PrayerHistoryScreenState();
}

class _PrayerHistoryScreenState extends State<PrayerHistoryScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _prayerSessions = [];

  @override
  void initState() {
    super.initState();
    _fetchPrayerHistory();
  }

  Future<void> _fetchPrayerHistory() async {
    try {
      final res = await SupabaseService.client
          .from('workouts')
          .select()
          .eq('workout_type', 'Prayer')
          .order('created_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(res as List);
      setState(() {
        _prayerSessions = list;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching prayer history: $e');
      setState(() => _isLoading = false);
    }
  }

  int get _totalSessions => _prayerSessions.length;

  int get _totalDurationMins {
    if (_prayerSessions.isEmpty) return 0;
    final totalSecs = _prayerSessions.fold<int>(0, (sum, s) => sum + ((s['duration_seconds'] as num?)?.toInt() ?? 0));
    return totalSecs ~/ 60;
  }

  int get _avgCalmness {
    if (_prayerSessions.isEmpty) return 0;
    final validScores = _prayerSessions
        .map((s) => (s['avg_hrv'] as num?)?.toInt() ?? 80) // fallback / proxy calmness
        .toList();
    if (validScores.isEmpty) return 85;
    final sum = validScores.fold<int>(0, (a, b) => a + b);
    return (sum / validScores.length).round().clamp(60, 99);
  }

  String _formatDuration(int secs) {
    final mins = secs ~/ 60;
    final remSecs = secs % 60;
    if (mins > 0) return '${mins}m ${remSecs}s';
    return '${remSecs}s';
  }

  String _formatDate(String? isoString) {
    if (isoString == null) return 'Recent';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return 'Recent';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        leading: const GlassBackButton(),
        title: Text(
          'Prayer History & Trends',
          style: AppTypography.inter(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.gold))
          : RefreshIndicator(
              onRefresh: _fetchPrayerHistory,
              color: AppTheme.gold,
              backgroundColor: AppTheme.card,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Summary Cards ───────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryStatCard(
                            title: 'Total Sessions',
                            value: '$_totalSessions',
                            unit: 'sessions',
                            icon: Icons.self_improvement_rounded,
                            color: AppTheme.gold,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SummaryStatCard(
                            title: 'Total Duration',
                            value: '$_totalDurationMins',
                            unit: 'minutes',
                            icon: Icons.timer_rounded,
                            color: Colors.amberAccent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SummaryStatCard(
                            title: 'Avg Calmness',
                            value: '$_avgCalmness%',
                            unit: 'serenity',
                            icon: Icons.spa_rounded,
                            color: Colors.lightGreenAccent,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // ── Calmness & Vitals Trend Chart ────────────────────────
                    Text(
                      'Serenity & Vitals Trend',
                      style: AppTypography.inter(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _ChartLegend(label: 'Calmness %', color: AppTheme.gold),
                              _ChartLegend(label: 'Avg Heart Rate', color: Colors.redAccent),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 140,
                            child: CustomPaint(
                              painter: _PrayerTrendsChartPainter(_prayerSessions),
                              size: Size.infinite,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ── History Session List ────────────────────────────────
                    Text(
                      'Recent Sessions',
                      style: AppTypography.inter(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (_prayerSessions.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: AppTheme.card,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0x1AFFFFFF)),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.self_improvement_rounded, color: AppTheme.gold, size: 48),
                            const SizedBox(height: 12),
                            Text(
                              'No Prayer Sessions Recorded Yet',
                              style: AppTypography.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Start your first prayer session to begin tracking 13 vitals and calmness trends.',
                              textAlign: TextAlign.center,
                              style: AppTypography.inter(color: AppTheme.textSec, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _prayerSessions.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final s = _prayerSessions[index];
                          final durationSecs = (s['duration_seconds'] as num?)?.toInt() ?? 0;
                          final avgHr = (s['avg_hr'] as num?)?.toInt() ?? 0;
                          final avgHrv = (s['avg_hrv'] as num?)?.toInt() ?? 0;
                          final calmness = (avgHrv > 0 ? (avgHrv * 1.3).round() : 85).clamp(65, 98);

                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.card,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0x1AFFFFFF)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.gold.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.self_improvement_rounded, color: AppTheme.gold, size: 24),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _formatDate(s['started_at'] as String?),
                                        style: AppTypography.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(Icons.timer_rounded, color: AppTheme.textSec, size: 13),
                                          const SizedBox(width: 4),
                                          Text(_formatDuration(durationSecs), style: AppTypography.inter(color: AppTheme.textSec, fontSize: 12)),
                                          const SizedBox(width: 12),
                                          Icon(Icons.favorite_rounded, color: Colors.redAccent, size: 13),
                                          const SizedBox(width: 4),
                                          Text(avgHr > 0 ? '$avgHr bpm' : '--', style: AppTypography.inter(color: AppTheme.textSec, fontSize: 12)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.gold.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppTheme.gold.withValues(alpha: 0.5)),
                                  ),
                                  child: Text(
                                    '$calmness% Calm',
                                    style: AppTypography.inter(color: AppTheme.gold, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SummaryStatCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;

  const _SummaryStatCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(
            value,
            style: AppTypography.inter(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: AppTypography.inter(
              color: AppTheme.textSec,
              fontSize: 10,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  final String label;
  final Color color;

  const _ChartLegend({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppTypography.inter(color: AppTheme.textSec, fontSize: 11),
        ),
      ],
    );
  }
}

class _PrayerTrendsChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> sessions;

  _PrayerTrendsChartPainter(this.sessions);

  @override
  void paint(Canvas canvas, Size size) {
    if (sessions.isEmpty) {
      final p = Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), p);
      return;
    }

    final dataCount = sessions.length.clamp(1, 10);
    final dx = size.width / (dataCount > 1 ? dataCount - 1 : 1);

    final calmnessPaint = Paint()
      ..color = AppTheme.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final hrPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final calmnessPath = Path();
    final hrPath = Path();

    for (int i = 0; i < dataCount; i++) {
      final s = sessions[i];
      final x = size.width - (i * dx);
      final avgHrv = (s['avg_hrv'] as num?)?.toDouble() ?? 55;
      final calmness = (avgHrv * 1.3).clamp(50.0, 100.0);
      final avgHr = ((s['avg_hr'] as num?)?.toDouble() ?? 68).clamp(50.0, 120.0);

      final yCalmness = size.height - ((calmness - 50.0) / 50.0 * (size.height - 10));
      final yHr = size.height - ((avgHr - 50.0) / 70.0 * (size.height - 10));

      if (i == 0) {
        calmnessPath.moveTo(x, yCalmness);
        hrPath.moveTo(x, yHr);
      } else {
        calmnessPath.lineTo(x, yCalmness);
        hrPath.lineTo(x, yHr);
      }

      // Draw dots
      canvas.drawCircle(Offset(x, yCalmness), 3.5, Paint()..color = AppTheme.gold);
      canvas.drawCircle(Offset(x, yHr), 3.0, Paint()..color = Colors.redAccent);
    }

    canvas.drawPath(calmnessPath, calmnessPaint);
    canvas.drawPath(hrPath, hrPaint);
  }

  @override
  bool shouldRepaint(covariant _PrayerTrendsChartPainter oldDelegate) => true;
}
