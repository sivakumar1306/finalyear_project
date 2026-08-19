import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// Shared widget tokens — all routable values derive from AppTheme so theme
// changes propagate everywhere (DESIGN.md single-source tokens).
const Color kCard = AppTheme.card;
const Color kBorder = AppTheme.div;
const Color kSec = AppTheme.textTertiary;
const Color kSec2 = AppTheme.textSec;
const Color kGrid = AppTheme.grid;

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTheme.kPad),
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(AppTheme.kRadiusCard),
        border: Border.all(color: kBorder),
      ),
      child: child,
    );
  }
}
