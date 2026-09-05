import 'package:flutter/material.dart';
import '../../services/goal_prefs.dart';
import '../../services/health_engine/health_engine.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';

// ── Design tokens (mirrors steps_screen.dart) ──────────────────────────────

TextStyle _t(double s, {FontWeight w = FontWeight.w400, Color? c, double? h}) =>
    AppTypography.inter(
      fontSize: s,
      fontWeight: w,
      color: c ?? Colors.white.withValues(alpha: 0.95),
      height: h,
    );

BoxDecoration _glass({double r = 20}) => BoxDecoration(
  color: Colors.white.withValues(alpha: 0.06),
  borderRadius: BorderRadius.circular(r),
  border: Border.all(color: Colors.white.withValues(alpha: 0.09), width: 0.5),
);

/// Read-only reference screen explaining what the Activity screen's numbers
/// mean and what ranges are considered healthy — opened from the Activity
/// screen's "..." menu. Now goal-aware: blends against user's GoalPrefs via HealthEngine.
class ActivityDescriptionScreen extends StatefulWidget {
  const ActivityDescriptionScreen({super.key});
  @override
  State<ActivityDescriptionScreen> createState() => _ActivityDescriptionScreenState();
}

class _ActivityDescriptionScreenState extends State<ActivityDescriptionScreen> {
  GoalTargets? _goals;
  @override
  void initState() {
    super.initState();
    GoalPrefs.load().then((g) { if (mounted) setState(() => _goals = g); });
  }

  @override
  Widget build(BuildContext context) {
    final goals = _goals ?? const GoalTargets(steps: 10000, calories: 1000, distanceKm: 5.0, sleepStartMin: 1260, sleepEndMin: 300);
    final intro = HealthEngine.instance.activityDescription(goals);
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        centerTitle: true,
        leading: const GlassBackButton(),
        title: Text('Activity Description', style: _t(17, w: FontWeight.w600)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── What is the Activity Score ─────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: _glass(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Activity Score',
                    style: _t(15, w: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    intro,
                    style: _t(
                      13,
                      c: Colors.white.withValues(alpha: 0.6),
                      h: 1.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: const [
                      _WeightChip(label: 'Steps', pct: '60 pts'),
                      SizedBox(width: 8),
                      _WeightChip(label: 'Calories', pct: '25 pts'),
                      SizedBox(width: 8),
                      _WeightChip(label: 'Distance', pct: '15 pts'),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Score range gauge ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: _glass(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'What the score means',
                    style: _t(15, w: FontWeight.w600),
                  ),
                  const SizedBox(height: 14),
                  const _ScoreRangeBar(),
                  const SizedBox(height: 10),
                  const _ScoreRangeLegend(),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Metric tip cards ─────────────────────────────────────────
            const _TipCard(
              icon: Icons.directions_walk_rounded,
              color: AppTheme.softGreen,
              title: 'Steps',
              tip:
                  'Full steps credit at 8,000/day. Under 5,000 is typically '
                  'sedentary; 8,000–10,000 supports heart health.',
            ),
            const SizedBox(height: 10),
            const _TipCard(
              icon: Icons.local_fire_department_rounded,
              color: AppTheme.softOrange,
              title: 'Calories',
              tip:
                  'Full calorie credit at 250 active kcal — about a 30-minute '
                  'brisk walk. Only movement-related burn counts toward the score.',
            ),
            const SizedBox(height: 10),
            const _TipCard(
              icon: Icons.directions_run_rounded,
              color: AppTheme.softBlue,
              title: 'Distance',
              tip:
                  'Full distance credit at 5 km (~45–60 min walk). Use with '
                  'steps to see pace, not just total movement.',
            ),

            const SizedBox(height: 14),

            // ── Did you know ─────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: _glass(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    color: AppTheme.gold,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'A score of 0 shows as Lack of exercise. Short walks '
                      'spread through the day usually lift the score more '
                      'evenly than one long workout.',
                      style: _t(
                        13,
                        c: Colors.white.withValues(alpha: 0.6),
                        h: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeightChip extends StatelessWidget {
  final String label;
  final String pct;
  const _WeightChip({required this.label, required this.pct});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      child: Text(
        '$label · $pct',
        style: _t(
          11.5,
          w: FontWeight.w500,
          c: Colors.white.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class _ScoreRangeBar extends StatelessWidget {
  const _ScoreRangeBar();

  static const _segments = [
    (flex: 25, color: AppTheme.danger),
    (flex: 25, color: AppTheme.tempColor),
    (flex: 25, color: AppTheme.spo2Color),
    (flex: 25, color: AppTheme.success),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 8,
        child: Row(
          children: [
            for (final seg in _segments)
              Expanded(
                flex: seg.flex,
                child: Container(color: seg.color.withValues(alpha: 0.85)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScoreRangeLegend extends StatelessWidget {
  const _ScoreRangeLegend();

  static const _rows = [
    (label: 'Lack of exercise', range: '0', color: AppTheme.danger),
    (label: 'Sedentary', range: '1–24', color: AppTheme.danger),
    (label: 'Lightly active', range: '25–49', color: AppTheme.tempColor),
    (label: 'Moderately active', range: '50–74', color: AppTheme.spo2Color),
    (label: 'Highly active', range: '75–100', color: AppTheme.success),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        for (final row in _rows)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: row.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${row.label} ',
                style: _t(11.5, c: Colors.white.withValues(alpha: 0.7)),
              ),
              Text(
                row.range,
                style: _t(
                  11.5,
                  w: FontWeight.w500,
                  c: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _TipCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String tip;

  const _TipCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.tip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _glass(r: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _t(13.5, w: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(
                  tip,
                  style: _t(
                    12.5,
                    c: Colors.white.withValues(alpha: 0.55),
                    h: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
