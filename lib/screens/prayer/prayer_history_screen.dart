import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/incident_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';
import 'prayer_session_screen.dart';

/// Screen displaying Prayer Session History with interactive trend charts and session details
/// fetched from local SharedPreferences and Supabase `workouts` table (workout_type = 'Prayer').
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

  static int _getHr(Map<String, dynamic> s) {
    final hr = s['avg_heart_rate'] ?? s['avg_hr'];
    return (hr as num?)?.toInt() ?? 0;
  }

  static int _getCalmness(Map<String, dynamic> s) {
    final c = s['calmness_score'] ?? s['calmness'];
    if (c != null) return (c as num).toInt().clamp(10, 100);
    final hrv = (s['avg_hrv'] as num?)?.toInt() ?? 0;
    if (hrv > 0) return (hrv * 1.3).round().clamp(50, 99);
    return 85;
  }

  static String? _getDateStr(Map<String, dynamic> s) {
    return (s['created_at'] ?? s['started_at'] ?? s['timestamp']) as String?;
  }

  Future<void> _fetchPrayerHistory() async {
    final allSessions = <Map<String, dynamic>>[];

    // 1. Load local sessions from SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final localJsonList = prefs.getStringList('prayer_sessions_history') ?? [];
      for (final jsonStr in localJsonList) {
        try {
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;
          allSessions.add(map);
        } catch (e, st) {
          IncidentService.reportUnhandled(
            source: 'prayer_history_screen',
            error: e,
            stackTrace: st,
            customMessage: 'decode local prayer session failed',
          );
        }
      }
    } catch (e) {
      debugPrint('Error reading local prayer sessions: $e');
    }

    // 2. Fetch remote sessions from Supabase
    try {
      final res = await SupabaseService.client
          .from('workouts')
          .select()
          .eq('workout_type', 'Prayer')
          .order('created_at', ascending: false);

      for (final item in res) {
        final map = Map<String, dynamic>.from(item as Map);
        final createdAt = map['created_at'] as String?;
        if (!allSessions.any((s) => s['created_at'] == createdAt)) {
          allSessions.add(map);
        }
      }
    } catch (e) {
      debugPrint('Error fetching prayer history from Supabase: $e');
    }

    // 3. Sort by date descending
    allSessions.sort((a, b) {
      final tA = DateTime.tryParse(_getDateStr(a) ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tB = DateTime.tryParse(_getDateStr(b) ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tB.compareTo(tA);
    });

    if (mounted) {
      setState(() {
        _prayerSessions = allSessions;
        _isLoading = false;
      });
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
    final validScores = _prayerSessions.map((s) => _getCalmness(s)).toList();
    if (validScores.isEmpty) return 85;
    final sum = validScores.fold<int>(0, (a, b) => a + b);
    return (sum / validScores.length).round().clamp(10, 100);
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

  static String _formatShortDate(String? isoString) {
    if (isoString == null) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
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
                            children: [
                              _ChartLegend(label: 'Calmness %', color: AppTheme.gold),
                              const SizedBox(width: 20),
                              _ChartLegend(label: 'Avg Heart Rate', color: Colors.redAccent),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 200,
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
                          border: Border.all(color: AppTheme.white10),
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
                            const SizedBox(height: 18),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const PrayerSessionScreen()),
                                );
                              },
                              icon: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 20),
                              label: Text(
                                'Start Meditation Session',
                                style: AppTypography.inter(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.gold,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
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
                          final avgHr = _getHr(s);
                          final calmness = _getCalmness(s);
                          final dateStr = _getDateStr(s);

                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.card,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.white10),
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
                                        _formatDate(dateStr),
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
        border: Border.all(color: AppTheme.white10),
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
    const leftPadding = 18.0;
    const rightPadding = 18.0;
    const topPadding = 22.0;
    const bottomPadding = 26.0;

    final chartWidth = size.width - leftPadding - rightPadding;
    final chartHeight = size.height - topPadding - bottomPadding;

    if (chartWidth <= 0 || chartHeight <= 0) return;

    // ── Simple Background Guide Lines ──────────────────────────────────────
    final gridLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 0; i <= 3; i++) {
      final y = topPadding + (chartHeight * i / 3);
      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(size.width - rightPadding, y),
        gridLinePaint,
      );
    }

    if (sessions.isEmpty) {
      final emptyTp = TextPainter(
        text: TextSpan(
          text: 'No sessions recorded yet',
          style: AppTypography.inter(color: Colors.white30, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      emptyTp.paint(
        canvas,
        Offset((size.width - emptyTp.width) / 2, (size.height - emptyTp.height) / 2),
      );
      return;
    }

    // Prepare chronological session list (oldest to newest: left to right)
    final chronological = List<Map<String, dynamic>>.from(sessions).take(7).toList().reversed.toList();
    final count = chronological.length;
    final stepX = count > 1 ? chartWidth / (count - 1) : 0.0;

    // ── Dynamic Auto-Scaling (prevents flat horizontal lines) ─────────────
    final calmnessValues = chronological.map((s) => _PrayerHistoryScreenState._getCalmness(s).toDouble()).toList();
    final hrValues = chronological.map((s) => _PrayerHistoryScreenState._getHr(s).toDouble()).where((v) => v > 0).toList();

    double minCalm = calmnessValues.reduce((a, b) => a < b ? a : b);
    double maxCalm = calmnessValues.reduce((a, b) => a > b ? a : b);
    if (maxCalm - minCalm < 15) {
      minCalm = (minCalm - 10).clamp(0.0, 100.0);
      maxCalm = (maxCalm + 10).clamp(0.0, 100.0);
    }
    final rangeCalm = (maxCalm - minCalm) > 0 ? (maxCalm - minCalm) : 20.0;

    double minHr = hrValues.isNotEmpty ? hrValues.reduce((a, b) => a < b ? a : b) : 60.0;
    double maxHr = hrValues.isNotEmpty ? hrValues.reduce((a, b) => a > b ? a : b) : 80.0;
    if (maxHr - minHr < 15) {
      minHr = (minHr - 10).clamp(30.0, 200.0);
      maxHr = (maxHr + 10).clamp(30.0, 200.0);
    }
    final rangeHr = (maxHr - minHr) > 0 ? (maxHr - minHr) : 20.0;

    final calmPoints = <Offset>[];
    final hrPoints = <Offset>[];

    for (int i = 0; i < count; i++) {
      final s = chronological[i];
      final x = count == 1
          ? leftPadding + chartWidth / 2
          : leftPadding + (i * stepX);

      final calmness = _PrayerHistoryScreenState._getCalmness(s).toDouble();
      final avgHr = _PrayerHistoryScreenState._getHr(s).toDouble();

      // Dynamic Y positioning using auto min/max range
      final normCalm = ((calmness - minCalm) / rangeCalm).clamp(0.0, 1.0);
      final yCalm = topPadding + chartHeight * (1.0 - normCalm);

      calmPoints.add(Offset(x, yCalm));

      if (avgHr > 0) {
        final normHr = ((avgHr - minHr) / rangeHr).clamp(0.0, 1.0);
        final yHr = topPadding + chartHeight * (1.0 - normHr);
        hrPoints.add(Offset(x, yHr));
      }

      // ── X-Axis Timestamp Label ──────────────────────────────────────────
      final dateStr = _PrayerHistoryScreenState._getDateStr(s);
      final dateLabel = _PrayerHistoryScreenState._formatShortDate(dateStr);
      if (dateLabel.isNotEmpty) {
        final dateTp = TextPainter(
          text: TextSpan(
            text: dateLabel,
            style: AppTypography.inter(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.w500),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        dateTp.paint(canvas, Offset(x - dateTp.width / 2, size.height - bottomPadding + 8));
      }

      // ── Point Value Badges ──────────────────────────────────────────────
      // Calmness Value above point
      final calmValTp = TextPainter(
        text: TextSpan(
          text: '${calmness.round()}%',
          style: AppTypography.inter(color: AppTheme.gold, fontSize: 10.5, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      calmValTp.paint(canvas, Offset(x - calmValTp.width / 2, yCalm - calmValTp.height - 4));
    }

    // Paint Heart Rate Value Badges
    for (int i = 0; i < hrPoints.length; i++) {
      final s = chronological[i];
      final avgHr = _PrayerHistoryScreenState._getHr(s).toDouble();
      final pt = hrPoints[i];
      if (avgHr > 0) {
        final hrValTp = TextPainter(
          text: TextSpan(
            text: '${avgHr.round()} bpm',
            style: AppTypography.inter(color: Colors.redAccent, fontSize: 10.0, fontWeight: FontWeight.bold),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        hrValTp.paint(canvas, Offset(pt.dx - hrValTp.width / 2, pt.dy + 4));
      }
    }

    // ── Draw Smooth Calmness Curve & Gradient Area Fill ───────────────────
    if (calmPoints.isNotEmpty) {
      final calmPath = Path();
      calmPath.moveTo(calmPoints.first.dx, calmPoints.first.dy);

      for (int i = 0; i < calmPoints.length - 1; i++) {
        final p0 = calmPoints[i];
        final p1 = calmPoints[i + 1];
        final controlX1 = p0.dx + (p1.dx - p0.dx) / 2;
        final controlY1 = p0.dy;
        final controlX2 = p0.dx + (p1.dx - p0.dx) / 2;
        final controlY2 = p1.dy;
        calmPath.cubicTo(controlX1, controlY1, controlX2, controlY2, p1.dx, p1.dy);
      }

      // Gradient Fill Path
      final fillPath = Path.from(calmPath);
      fillPath.lineTo(calmPoints.last.dx, topPadding + chartHeight);
      fillPath.lineTo(calmPoints.first.dx, topPadding + chartHeight);
      fillPath.close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.gold.withValues(alpha: 0.28),
            AppTheme.gold.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(leftPadding, topPadding, chartWidth, chartHeight));
      canvas.drawPath(fillPath, fillPaint);

      // Line Stroke
      final strokePaint = Paint()
        ..color = AppTheme.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(calmPath, strokePaint);

      // Node Circles
      for (final pt in calmPoints) {
        canvas.drawCircle(pt, 4.5, Paint()..color = AppTheme.card2);
        canvas.drawCircle(pt, 3.5, Paint()..color = AppTheme.gold);
      }
    }

    // ── Draw Smooth Heart Rate Curve ──────────────────────────────────────
    if (hrPoints.isNotEmpty) {
      final hrPath = Path();
      hrPath.moveTo(hrPoints.first.dx, hrPoints.first.dy);

      for (int i = 0; i < hrPoints.length - 1; i++) {
        final p0 = hrPoints[i];
        final p1 = hrPoints[i + 1];
        final controlX1 = p0.dx + (p1.dx - p0.dx) / 2;
        final controlY1 = p0.dy;
        final controlX2 = p0.dx + (p1.dx - p0.dx) / 2;
        final controlY2 = p1.dy;
        hrPath.cubicTo(controlX1, controlY1, controlX2, controlY2, p1.dx, p1.dy);
      }

      final hrStrokePaint = Paint()
        ..color = Colors.redAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(hrPath, hrStrokePaint);

      for (final pt in hrPoints) {
        canvas.drawCircle(pt, 4.0, Paint()..color = AppTheme.card2);
        canvas.drawCircle(pt, 3.0, Paint()..color = Colors.redAccent);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PrayerTrendsChartPainter oldDelegate) => true;
}
