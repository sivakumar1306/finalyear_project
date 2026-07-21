import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class KeyChangeCard extends StatelessWidget {
  final String title;
  final String delta;
  final String subtitle;
  final VoidCallback onTap;

  const KeyChangeCard({
    super.key,
    required this.title,
    required this.delta,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
                color: const Color(0x0AFFFFFF), // rgba(255,255,255,0.03)
                border: Border.all(
                  color: const Color(0x14FFFFFF), // rgba(255,255,255,0.08)
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
                          color: const Color(0x0FC9A86E), // rgba(201,168,110,0.06)
                          border: Border.all(
                            color: const Color(0x33C9A86E), // rgba(201,168,110,0.2)
                            width: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.lightbulb_outline_rounded,
                            size: 12,
                            color: Color(0xFFC9A86E),
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
                            color: const Color(0xEBFFFFFF), // rgba(255,255,255,0.93)
                          ),
                        ),
                      ),
                      Text(
                        delta,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.005,
                          color: const Color(0xEDC9A86E), // rgba(201,168,110,0.93)
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
                      color: const Color(0x80FFFFFF), // rgba(255,255,255,0.5)
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
