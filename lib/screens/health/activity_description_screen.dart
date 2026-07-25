import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

// ── Design tokens (mirrors steps_screen.dart) ──────────────────────────────
const _kBg = Color(0xFF050505);
const _kStepsColor = Color(0xFF4ADE80);
const _kDistColor = Color(0xFF60A5FA);
const _kCalColor = Color(0xFFFB923C);

TextStyle _t(double s, {FontWeight w = FontWeight.w400, Color? c, double? h}) =>
    GoogleFonts.inter(
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
/// screen's "..." menu.
class ActivityDescriptionScreen extends StatelessWidget {
  const ActivityDescriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        centerTitle: true,
        leading: Center(
          child: _circleIconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 16,
            ),
            onTap: () => Navigator.pop(context),
          ),
        ),
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
                    'A single 0–100 number blending how much you moved today — '
                    'steps, calories burned, and distance covered.',
                    style: _t(
                      13,
                      c: Colors.white.withValues(alpha: 0.6),
                      h: 1.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: const [
                      _WeightChip(label: 'Steps', pct: '60%'),
                      SizedBox(width: 8),
                      _WeightChip(label: 'Calories', pct: '25%'),
                      SizedBox(width: 8),
                      _WeightChip(label: 'Distance', pct: '15%'),
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
              color: _kStepsColor,
              title: 'Steps',
              tip:
                  '8,000–10,000 steps/day supports heart health. '
                  'Under 5,000 is considered sedentary.',
            ),
            const SizedBox(height: 10),
            const _TipCard(
              icon: Icons.local_fire_department_rounded,
              color: _kCalColor,
              title: 'Calories',
              tip:
                  '250+ active kcal/day is a solid baseline — roughly what '
                  'a 30-minute brisk walk burns.',
            ),
            const SizedBox(height: 10),
            const _TipCard(
              icon: Icons.directions_run_rounded,
              color: _kDistColor,
              title: 'Distance',
              tip:
                  '5 km/day ≈ a 45–60 minute walk. Pair with steps to '
                  'gauge pace, not just movement.',
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
                      'Short, frequent walks throughout the day tend to '
                      'raise your score more evenly than one long workout.',
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

Widget _circleIconButton({required Widget icon, required VoidCallback onTap}) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
        child: Center(child: icon),
      ),
    );

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

/// Segmented gauge: Sedentary → Lightly active → Moderately active → Highly
/// active, mirroring the exact thresholds steps_screen.dart's activity
/// score uses (0 / 25 / 50 / 75 / 100).
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
    (label: 'Sedentary', range: '0–24', color: AppTheme.danger),
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
