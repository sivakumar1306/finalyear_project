import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../../widgets/app_typography.dart';
import '../../theme/app_theme.dart';

class KeyChangeCard extends StatelessWidget {
  final String title;
  final String delta;
  final String subtitle;
  final bool alarming;
  final VoidCallback onTap;

  const KeyChangeCard({
    super.key,
    required this.title,
    required this.delta,
    required this.subtitle,
    required this.onTap,
    this.alarming = false,
  });

  @override
  Widget build(BuildContext context) {
    // Gold for routine/positive changes, warm red for anything flagged as
    // needing attention — same layout, just a different accent so alarming
    // cards are visually distinct without needing separate iconography.
    final accentColor = alarming
        ? const Color(0xFFE07A5F)
        : AppTheme.gold;

    // RepaintBoundary caches the blurred layer so scrolling the chat list
    // doesn't re-blur the backdrop every frame.
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: alarming
                  ? accentColor.withValues(alpha: 0.05)
                  : AppTheme.white04,
              border: Border.all(
                color: alarming
                    ? accentColor.withValues(alpha: 0.35)
                    : AppTheme.glassButtonBorder,
                width: 0.5,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.06),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.2),
                          width: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Center(
                        child: Icon(
                          alarming
                              ? Icons.warning_amber_rounded
                              : Icons.lightbulb_outline_rounded,
                          size: 12,
                          color: accentColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: AppTypography.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.white92,
                        ),
                      ),
                    ),
                    Text(
                      delta,
                      style: AppTypography.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.005,
                        color: accentColor.withValues(alpha: 0.93),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: AppTypography.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.white50,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}
