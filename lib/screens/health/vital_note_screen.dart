import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';

// ── Design tokens (mirrors the other health detail screens) ───────────────
const _kBg = Color(0xFF050505);

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

/// One band in a [VitalNoteScreen]'s range gauge + legend, e.g.
/// `VitalRange(label: 'Normal', range: '60–100 bpm', color: AppTheme.success)`.
class VitalRange {
  final String label;
  final String range;
  final Color color;
  const VitalRange({required this.label, required this.range, required this.color});
}

/// One short, crisp tip card in a [VitalNoteScreen].
class VitalTip {
  final IconData icon;
  final Color color;
  final String title;
  final String tip;
  const VitalTip({
    required this.icon,
    required this.color,
    required this.title,
    required this.tip,
  });
}

/// Reusable "Note" reference screen — what a vital means, healthy ranges at
/// a glance, and a couple of crisp tips. Opened from a health detail
/// screen's "..." menu. Mirrors activity_description_screen.dart's layout
/// so every vital's Note screen feels like one system.
class VitalNoteScreen extends StatelessWidget {
  final String title;
  final String heading;
  final String intro;
  final List<VitalRange> ranges;
  final List<VitalTip> tips;
  final String? didYouKnow;

  const VitalNoteScreen({
    super.key,
    required this.title,
    required this.heading,
    required this.intro,
    required this.ranges,
    required this.tips,
    this.didYouKnow,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        centerTitle: true,
        leading: const GlassBackButton(),
        title: Text(title, style: _t(17, w: FontWeight.w600)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Definition ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: _glass(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(heading, style: _t(15, w: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(intro,
                      style: _t(13, c: Colors.white.withValues(alpha: 0.6), h: 1.5)),
                ],
              ),
            ),

            if (ranges.isNotEmpty) ...[
              const SizedBox(height: 14),
              // ── Range gauge ───────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: _glass(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Healthy ranges', style: _t(15, w: FontWeight.w600)),
                    const SizedBox(height: 14),
                    _RangeBar(ranges: ranges),
                    const SizedBox(height: 10),
                    _RangeLegend(ranges: ranges),
                  ],
                ),
              ),
            ],

            if (tips.isNotEmpty) ...[
              const SizedBox(height: 14),
              for (var i = 0; i < tips.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _TipCard(tip: tips[i]),
              ],
            ],

            if (didYouKnow != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: _glass(),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lightbulb_outline_rounded,
                        color: AppTheme.gold, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(didYouKnow!,
                          style: _t(13,
                              c: Colors.white.withValues(alpha: 0.6), h: 1.5)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RangeBar extends StatelessWidget {
  final List<VitalRange> ranges;
  const _RangeBar({required this.ranges});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 8,
        child: Row(
          children: [
            for (final r in ranges)
              Expanded(child: Container(color: r.color.withValues(alpha: 0.85))),
          ],
        ),
      ),
    );
  }
}

class _RangeLegend extends StatelessWidget {
  final List<VitalRange> ranges;
  const _RangeLegend({required this.ranges});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        for (final r in ranges)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: r.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text('${r.label} ',
                  style: _t(11.5, c: Colors.white.withValues(alpha: 0.7))),
              Text(r.range,
                  style: _t(11.5,
                      w: FontWeight.w500, c: Colors.white.withValues(alpha: 0.4))),
            ],
          ),
      ],
    );
  }
}

class _TipCard extends StatelessWidget {
  final VitalTip tip;
  const _TipCard({required this.tip});

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
              color: tip.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(tip.icon, color: tip.color, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tip.title, style: _t(13.5, w: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(tip.tip,
                    style: _t(12.5, c: Colors.white.withValues(alpha: 0.55), h: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
