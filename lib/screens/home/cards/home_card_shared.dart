import 'dart:ui' show ImageFilter, TileMode;
import 'package:flutter/material.dart';
import '../../../services/health_engine/health_engine.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_typography.dart';
// ── Design tokens ─────────────────────────────────────────────────────────────

const kCardBg = AppTheme.glassCard; // rgba(255,255,255,0.06)
const kCardBorder = AppTheme.glassBorder; // rgba(255,255,255,0.09)
const kBtnBg = AppTheme.glassButton; // rgba(255,255,255,0.03)
const kBtnBorder = AppTheme.glassButtonBorder; // rgba(255,255,255,0.08)

// Shared filter instances — recreating ImageFilter every build is pure waste.
final ImageFilter kOrbBlur = ImageFilter.blur(
  sigmaX: 70,
  sigmaY: 70,
  tileMode: TileMode.decal,
);
final ImageFilter kCompactOrbBlur = ImageFilter.blur(
  sigmaX: 60,
  sigmaY: 60,
  tileMode: TileMode.decal,
);

const kFigmaStressLow = Color(0xFF8FE5B5);
const kFigmaStressHigh = Color(0xFFE88FA0);

/// Ambient metric orb — original ImageFiltered blur quality.
///
/// [RepaintBoundary] caches the blurred result so scrolling reuses the layer
/// instead of re-running the blur every frame.
class BlurOrb extends StatelessWidget {
  final Color color;
  final double size;
  final double alpha;
  final bool compact;

  const BlurOrb({
    super.key,
    required this.color,
    required this.size,
    this.alpha = 0.45,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ImageFiltered(
        imageFilter: compact ? kCompactOrbBlur : kOrbBlur,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInOut,
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: alpha),
          ),
        ),
      ),
    );
  }
}

// DESIGN.md per-metric orb colors (soft, desaturated)

// ── Status helpers — delegated to HealthEngine single source ─────────────

String stressStatus(int v) {
  final a = HealthEngine.instance.assessStress(v);
  if (a.label == '--') return 'No data';
  return a.label;
}

Color stressColor(int v) => HealthEngine.instance.assessStress(v).color;

String tempStatus(double v) {
  final a = HealthEngine.instance.assessTemperature(v);
  if (a.label == '--') return 'No data';
  return a.label;
}

String activityScoreLabel(int score) => HealthEngine.instance.activityLabel(score);

TextStyle inter(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = Colors.white,
  double? letterSpacing,
  double? height,
}) => AppTypography.inter(
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: letterSpacing,
  height: height,
);

/// Resamples [src] into [count] points via linear interpolation.
List<double> interpolate(List<double> src, int count) {
  if (src.length == count) return List.of(src);
  final out = <double>[];
  for (int i = 0; i < count; i++) {
    final t = i / (count - 1) * (src.length - 1);
    final lo = t.floor();
    final hi = (lo + 1).clamp(0, src.length - 1);
    final f = t - lo;
    out.add(src[lo] * (1 - f) + src[hi] * f);
  }
  return out;
}

String formatInt(int v) => v.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]},',
);

