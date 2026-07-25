import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
        : const Color(0xFFC9A86E);

    return Expanded(
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
                    ? accentColor.withOpacity(0.05)
                    : const Color(0x0AFFFFFF),
                border: Border.all(
                  color: alarming
                      ? accentColor.withOpacity(0.35)
                      : const Color(0x14FFFFFF),
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
                          color: accentColor.withOpacity(0.06),
                          border: Border.all(
                            color: accentColor.withOpacity(0.2),
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
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xEBFFFFFF),
                          ),
                        ),
                      ),
                      Text(
                        delta,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.005,
                          color: accentColor.withOpacity(0.93),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w400,
                      color: const Color(0x80FFFFFF),
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
