import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import 'key_change_card.dart';

class InsightsHeader extends StatefulWidget {
  const InsightsHeader({super.key});

  @override
  State<InsightsHeader> createState() => _InsightsHeaderState();
}

class _InsightsHeaderState extends State<InsightsHeader> {
  String _selectedRange = '30D';

  void _onRangeSelect(String range) {
    setState(() {
      _selectedRange = range;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 18),
          
          // Title and Segmented Control Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'AI assist',
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.w300,
                  letterSpacing: -0.04 * 28, // -0.04em
                  color: const Color(0xF2FFFFFF), // rgba(255,255,255,0.95)
                ),
              ),
              _buildSegmentedControl(),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Eyebrow label
          Text(
            'YOUR LAST 30 DAYS',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2 * 10, // 0.2em
              color: AppTheme.goldAccent,
            ),
          ),
          
          const SizedBox(height: 6),
          
          // Headline (RichText split)
          RichText(
            text: TextSpan(
              style: GoogleFonts.inter(
                fontSize: 21,
                fontWeight: FontWeight.w400,
                height: 1.30, // line-height 130%
                letterSpacing: -0.025 * 21, // -0.025em
                color: const Color(0xEBFFFFFF), // rgba(255,255,255,0.92)
              ),
              children: [
                const TextSpan(text: 'Your recovery is steadier, but blood pressure is '),
                TextSpan(
                  text: 'high',
                  style: GoogleFonts.inter(
                    color: AppTheme.goldAccent,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 8),
          
          // Subtext
          Text(
            'Sleep and HRV both improved this month. Two metrics need attention. Tap any change below to dig in.',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w400,
              height: 1.50, // line-height 150%
              letterSpacing: 0.02 * 12.5, // 0.02em
              color: const Color(0x85FFFFFF), // rgba(255,255,255,0.52)
            ),
          ),
          
          const SizedBox(height: 20),
          
          // KEY CHANGES Eyebrow
          Text(
            'KEY CHANGES',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2 * 10, // 0.2em
              color: const Color(0x6BFFFFFF), // rgba(255,255,255,0.42)
            ),
          ),
          
          const SizedBox(height: 10),
          
          // Cards Row (2 cards side by side, flexible sizing)
          Row(
            children: [
              KeyChangeCard(
                title: 'Sleep',
                delta: '+22 min',
                subtitle: '22 minutes more sleep on average',
                onTap: () => Navigator.pushNamed(context, '/sleep'),
              ),
              const SizedBox(width: 8),
              KeyChangeCard(
                title: 'Blood pressure',
                delta: '+6',
                subtitle: 'Systolic trending up across the month',
                onTap: () => Navigator.pushNamed(context, '/blood-pressure'),
              ),
            ],
          ),
          
          // Bottom padding logic to separate divider cleanly
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _buildSegmentedControl() {
    return Container(
      width: 131,
      height: 33,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF), // rgba(255,255,255,0.04)
        border: Border.all(
          color: const Color(0x0FFFFFFF), // rgba(255,255,255,0.06)
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(100),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Row(
            children: [
              _buildSegment('7D'),
              _buildSegment('30D'),
              _buildSegment('90D'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSegment(String range) {
    final bool isSelected = _selectedRange == range;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onRangeSelect(range),
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? const Color(0x14FFFFFF) : Colors.transparent, // rgba(255,255,255,0.08)
            borderRadius: BorderRadius.circular(100),
          ),
          child: Center(
            child: Text(
              range,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                letterSpacing: 0.02 * 11, // 0.02em
                color: const Color(0xF2FFFFFF), // rgba(255,255,255,0.95)
              ),
            ),
          ),
        ),
      ),
    );
  }
}
