import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/workout_model.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_typography.dart';

class WorkoutDetailScreen extends StatelessWidget {
  final Map<String, dynamic> row;

  const WorkoutDetailScreen({super.key, required this.row});

  TextStyle _inter(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = Colors.white,
    double? letterSpacing,
    double? height,
  }) =>
      AppTypography.inter(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  static String _fmtDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  static String _fmtDate(String isoString) {
    if (isoString.isEmpty) return 'Recent Workout';
    final dt = DateTime.tryParse(isoString)?.toLocal();
    if (dt == null) return 'Recent Workout';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = h < 12 ? 'AM' : 'PM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '${weekdays[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}, ${dt.year} • $h12:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final type = (row['workout_type'] as String? ?? 'running');
    final startedAt = row['started_at'] as String? ?? '';
    final endedAt = row['ended_at'] as String? ?? '';
    final durationS = (row['duration_s'] as num? ?? 0).toInt();
    final steps = (row['steps'] as num? ?? 0).toInt();
    final calories = (row['calories'] as num? ?? 0).toInt();
    final distanceM = (row['distance_m'] as num? ?? 0.0).toDouble();
    final avgHr = (row['avg_hr'] as num? ?? 0).toInt();

    final category = workoutCategoryFromString(type);
    final icon = category?.icon ?? Icons.fitness_center_rounded;
    final label = type.isNotEmpty
        ? '${type[0].toUpperCase()}${type.substring(1)}'
        : 'Workout';

    // Estimations and calculated insights
    final durationMin = (durationS / 60.0).clamp(0.1, 1440.0);
    final estPaceMinPerKm = (distanceM > 50 && durationS > 0)
        ? (durationS / 60.0) / (distanceM / 1000.0)
        : 0.0;
    final estCadenceSpm = (steps > 0 && durationMin > 0)
        ? (steps / durationMin).round()
        : 0;
    final estCalPerMin = (calories > 0 && durationMin > 0)
        ? (calories / durationMin).toStringAsFixed(1)
        : '0.0';

    // HR Zone analysis
    String hrZoneLabel = 'Balanced';
    Color hrZoneColor = AppTheme.success;
    if (avgHr > 0) {
      if (avgHr < 115) {
        hrZoneLabel = 'Light / Active Recovery';
        hrZoneColor = AppTheme.spo2Color;
      } else if (avgHr < 140) {
        hrZoneLabel = 'Fat Burn / Endurance';
        hrZoneColor = AppTheme.success;
      } else if (avgHr < 165) {
        hrZoneLabel = 'Aerobic / Performance';
        hrZoneColor = AppTheme.gold;
      } else {
        hrZoneLabel = 'Anaerobic / Peak Intensity';
        hrZoneColor = AppTheme.danger;
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF060606),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Navigation Bar ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceDeep,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF262626)),
                      ),
                      child: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: _inter(18, weight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _fmtDate(startedAt),
                          style: _inter(11, color: AppTheme.textSec),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share_rounded,
                        color: AppTheme.gold, size: 20),
                    onPressed: () {
                      final summaryText =
                          '🏋️ $label Workout Summary\n'
                          '⏱ Duration: ${_fmtDuration(durationS)}\n'
                          '🔥 Calories: $calories kcal\n'
                          '❤️ Avg Heart Rate: ${avgHr > 0 ? '$avgHr bpm' : 'N/A'}\n'
                          '👟 Steps: $steps\n'
                          '📍 Distance: ${(distanceM / 1000).toStringAsFixed(2)} km\n'
                          'Tracked with QRing Vital Monitoring App.';
                      Share.share(summaryText, subject: '$label Workout');
                    },
                  ),
                ],
              ),
            ),

            // ── Scrollable Body ───────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Hero Summary Banner Card ─────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFF1C170E),
                            const Color(0xFF101010),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: AppTheme.gold.withValues(alpha: 0.35),
                          width: 0.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.gold.withValues(alpha: 0.08),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppTheme.goldBorder,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  children: [
                                    Icon(icon,
                                        color: AppTheme.gold, size: 14),
                                    const SizedBox(width: 6),
                                    Text(
                                      category?.label ?? 'Workout',
                                      style: _inter(11,
                                          weight: FontWeight.w600,
                                          color: AppTheme.gold),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: hrZoneColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: hrZoneColor.withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  hrZoneLabel,
                                  style: _inter(10,
                                      weight: FontWeight.w600,
                                      color: hrZoneColor),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _fmtDuration(durationS),
                            style: _inter(44,
                                weight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 1.5),
                          ),
                          Text(
                            'TOTAL WORKOUT TIME',
                            style: _inter(10,
                                weight: FontWeight.w600,
                                color: AppTheme.textSec,
                                letterSpacing: 1.8),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Metrics Grid Section Header ────────────────────────
                    Text(
                      'PERFORMANCE METRICS',
                      style: _inter(11,
                          weight: FontWeight.w700,
                          color: AppTheme.textSec,
                          letterSpacing: 1.4),
                    ),
                    const SizedBox(height: 12),

                    // ── 4 Metric Cards Grid ────────────────────────────────
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.25,
                      children: [
                        _MetricTile(
                          title: 'HEART RATE',
                          value: avgHr > 0 ? '$avgHr' : '—',
                          unit: 'bpm avg',
                          icon: Icons.favorite_rounded,
                          color: AppTheme.hrColor,
                          subtitle: avgHr > 0
                              ? 'Max ~${(avgHr * 1.15).round()} bpm'
                              : 'No HR recorded',
                        ),
                        _MetricTile(
                          title: 'CALORIES',
                          value: calories > 0 ? '$calories' : '—',
                          unit: 'kcal burned',
                          icon: Icons.local_fire_department_rounded,
                          color: AppTheme.warmOrange,
                          subtitle: '$estCalPerMin kcal/min',
                        ),
                        _MetricTile(
                          title: 'STEPS',
                          value: steps > 0 ? '$steps' : '—',
                          unit: 'total steps',
                          icon: Icons.directions_walk_rounded,
                          color: AppTheme.stepsColor,
                          subtitle: estCadenceSpm > 0
                              ? '$estCadenceSpm steps/min'
                              : 'Session count',
                        ),
                        _MetricTile(
                          title: 'DISTANCE',
                          value: distanceM > 0
                              ? (distanceM >= 1000
                                  ? (distanceM / 1000).toStringAsFixed(2)
                                  : distanceM.toStringAsFixed(0))
                              : '—',
                          unit: distanceM >= 1000 ? 'km' : 'meters',
                          icon: Icons.straighten_rounded,
                          color: AppTheme.success,
                          subtitle: estPaceMinPerKm > 0
                              ? "${estPaceMinPerKm.floor()}'${((estPaceMinPerKm % 1) * 60).round().toString().padLeft(2, '0')}\" /km"
                              : 'Covered',
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // ── Heart Rate Intensity Zone Gauge ────────────────────
                    if (avgHr > 0) ...[
                      Text(
                        'INTENSITY & HEART RATE ZONES',
                        style: _inter(11,
                            weight: FontWeight.w700,
                            color: AppTheme.textSec,
                            letterSpacing: 1.4),
                      ),
                      const SizedBox(height: 12),
                      _HrZoneBar(avgHr: avgHr, durationS: durationS),
                      const SizedBox(height: 24),
                    ],

                    // ── AI Insights & Recovery Recommendations ─────────────
                    Text(
                      'WORKOUT INSIGHTS & RECOVERY',
                      style: _inter(11,
                          weight: FontWeight.w700,
                          color: AppTheme.textSec,
                          letterSpacing: 1.4),
                    ),
                    const SizedBox(height: 12),
                    _InsightCard(
                      icon: Icons.bolt_rounded,
                      color: AppTheme.gold,
                      title: 'Cardiovascular Load',
                      description: _generateStaminaInsight(avgHr, durationS, calories),
                    ),
                    const SizedBox(height: 10),
                    _InsightCard(
                      icon: Icons.water_drop_rounded,
                      color: AppTheme.spo2Color,
                      title: 'Hydration & Recovery',
                      description: _generateRecoveryInsight(durationS, calories),
                    ),
                    const SizedBox(height: 10),
                    _InsightCard(
                      icon: Icons.insights_rounded,
                      color: AppTheme.success,
                      title: 'Fitness Impact',
                      description: _generateFitnessInsight(category, steps, distanceM),
                    ),

                    const SizedBox(height: 24),

                    // ── Raw Audit Information Card ─────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF101010),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.grid),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SESSION AUDIT LOG',
                            style: _inter(10,
                                weight: FontWeight.w700,
                                color: AppTheme.textSec,
                                letterSpacing: 1.2),
                          ),
                          const SizedBox(height: 12),
                          _AuditRow(
                              label: 'Start Time', value: _fmtDate(startedAt)),
                          _AuditRow(
                              label: 'End Time',
                              value: endedAt.isNotEmpty
                                  ? _fmtDate(endedAt)
                                  : 'Completed'),
                          _AuditRow(
                              label: 'Duration',
                              value: '$durationS seconds (${_fmtDuration(durationS)})'),
                          _AuditRow(
                              label: 'Sensor Source',
                              value: 'QRing BLE Sensor & Local Database'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _generateStaminaInsight(int avgHr, int durationS, int calories) {
    if (avgHr <= 0) {
      return 'Session completed successfully. Wear your QRing securely during workouts for live heart rate tracking.';
    }
    if (avgHr > 155) {
      return 'High-intensity threshold session. You expended significant aerobic power, greatly enhancing peak cardiovascular resilience and VO2 max capacity.';
    } else if (avgHr > 130) {
      return 'Optimal aerobic zone session! Excellent for endurance building, cardiovascular strengthening, and efficient energy expenditure.';
    } else {
      return 'Active recovery intensity. Keeps blood circulating smoothly while facilitating joint mobility and muscle recovery.';
    }
  }

  static String _generateRecoveryInsight(int durationS, int calories) {
    final estWaterMl = (calories * 1.5).clamp(300.0, 1500.0).round();
    final restHours = (durationS / 1800).clamp(12.0, 36.0).round();
    return 'Recommended fluid replenishment: ~$estWaterMl ml of water. Allow at least $restHours hours before your next intense session for full muscle repair.';
  }

  static String _generateFitnessInsight(WorkoutCategory? cat, int steps, double distM) {
    if (steps > 3000 || distM > 2000) {
      return 'Substantial distance achieved! Outstanding contribution towards your daily physical activity and lower-body strength.';
    } else if (steps > 0) {
      return 'Steady cadence maintained throughout the session, supporting steady caloric burn and overall physical agility.';
    } else {
      return 'Targeted muscular engagement session completed. Great consistency for maintaining daily routine!';
    }
  }
}

// ── Metric Tile ───────────────────────────────────────────────────────────────

class _MetricTile extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  final String subtitle;

  const _MetricTile({
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
    required this.subtitle,
  });

  TextStyle _inter(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = Colors.white,
  }) =>
      AppTypography.inter(fontSize: size, fontWeight: weight, color: color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.grid),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: _inter(10,
                      weight: FontWeight.w600, color: AppTheme.textSec),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: value == '—' ? AppTheme.textSec : Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  unit,
                  style: _inter(9.5, color: AppTheme.textSec),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: _inter(10, color: AppTheme.textSec),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── HR Zone Bar ───────────────────────────────────────────────────────────────

class _HrZoneBar extends StatelessWidget {
  final int avgHr;
  final int durationS;

  const _HrZoneBar({required this.avgHr, required this.durationS});

  TextStyle _inter(double size, {FontWeight weight = FontWeight.w400, Color color = Colors.white}) =>
      AppTypography.inter(fontSize: size, fontWeight: weight, color: color);

  @override
  Widget build(BuildContext context) {
    // Distribute estimated time across zones based on avg HR
    double warmupRatio = 0.15;
    double fatBurnRatio = 0.45;
    double cardioRatio = 0.30;
    double peakRatio = 0.10;

    if (avgHr > 165) {
      peakRatio = 0.40;
      cardioRatio = 0.35;
      fatBurnRatio = 0.15;
      warmupRatio = 0.10;
    } else if (avgHr > 140) {
      cardioRatio = 0.50;
      fatBurnRatio = 0.30;
      warmupRatio = 0.10;
      peakRatio = 0.10;
    } else if (avgHr < 115) {
      warmupRatio = 0.60;
      fatBurnRatio = 0.30;
      cardioRatio = 0.10;
      peakRatio = 0.0;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.grid),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ZONE DISTRIBUTION',
                  style: _inter(10, weight: FontWeight.w600, color: AppTheme.textSec)),
              Text('Avg $avgHr bpm',
                  style: _inter(11, weight: FontWeight.w700, color: AppTheme.gold)),
            ],
          ),
          const SizedBox(height: 12),

          // Multi-color segmented bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  Expanded(flex: (warmupRatio * 100).round(), child: Container(color: AppTheme.spo2Color)),
                  const SizedBox(width: 2),
                  Expanded(flex: (fatBurnRatio * 100).round(), child: Container(color: AppTheme.success)),
                  const SizedBox(width: 2),
                  Expanded(flex: (cardioRatio * 100).round(), child: Container(color: AppTheme.gold)),
                  const SizedBox(width: 2),
                  Expanded(flex: (peakRatio * 100).round(), child: Container(color: AppTheme.danger)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _ZoneLegendItem(color: AppTheme.spo2Color, label: 'Warmup', pct: '${(warmupRatio * 100).round()}%'),
              _ZoneLegendItem(color: AppTheme.success, label: 'Fat Burn', pct: '${(fatBurnRatio * 100).round()}%'),
              _ZoneLegendItem(color: AppTheme.gold, label: 'Cardio', pct: '${(cardioRatio * 100).round()}%'),
              _ZoneLegendItem(color: AppTheme.danger, label: 'Peak', pct: '${(peakRatio * 100).round()}%'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ZoneLegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final String pct;

  const _ZoneLegendItem({required this.color, required this.label, required this.pct});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text('$label ($pct)', style: AppTypography.inter(fontSize: 10, color: AppTheme.textSec)),
      ],
    );
  }
}

// ── Insight Card ─────────────────────────────────────────────────────────────

class _InsightCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String description;

  const _InsightCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
  });

  TextStyle _inter(double size, {FontWeight weight = FontWeight.w400, Color color = Colors.white, double? height}) =>
      AppTypography.inter(fontSize: size, fontWeight: weight, color: color, height: height);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.grid),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _inter(14, weight: FontWeight.w600, color: Colors.white)),
                const SizedBox(height: 4),
                Text(description, style: _inter(12, color: AppTheme.textSec, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Audit Row ────────────────────────────────────────────────────────────────

class _AuditRow extends StatelessWidget {
  final String label;
  final String value;

  const _AuditRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.inter(fontSize: 11, color: AppTheme.textSec)),
          Flexible(
            child: Text(
              value,
              style: AppTypography.inter(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
