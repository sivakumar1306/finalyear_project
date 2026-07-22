import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../services/insights_service.dart';
import 'key_change_card.dart';

class InsightsHeader extends StatefulWidget {
  const InsightsHeader({super.key});

  @override
  State<InsightsHeader> createState() => _InsightsHeaderState();
}

class _InsightsHeaderState extends State<InsightsHeader> {
  String _selectedRange = '30D';
  InsightsResult? _result;
  bool _loading = true;

  static const _rangeDays = {'7D': 7, '30D': 30, '90D': 90};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await InsightsService.compute(_rangeDays[_selectedRange]!);
    if (mounted) {
      setState(() {
        _result = result;
        _loading = false;
      });
    }
  }

  void _onRangeSelect(String range) {
    if (range == _selectedRange) return;
    setState(() => _selectedRange = range);
    _load();
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

          if (_loading) _buildLoading() else _buildInsights(_result!),

          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.gold,
          ),
        ),
      ),
    );
  }

  Widget _buildInsights(InsightsResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Eyebrow label
        Text(
          result.eyebrow,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2 * 10, // 0.2em
            color: AppTheme.goldAccent,
          ),
        ),

        const SizedBox(height: 6),

        // Headline (RichText, dynamically built spans)
        RichText(
          text: TextSpan(
            style: GoogleFonts.inter(
              fontSize: 21,
              fontWeight: FontWeight.w400,
              height: 1.30, // line-height 130%
              letterSpacing: -0.025 * 21, // -0.025em
              color: const Color(0xEBFFFFFF), // rgba(255,255,255,0.92)
            ),
            children: result.headline
                .map(
                  (span) => TextSpan(
                    text: span.text,
                    style: span.highlight
                        ? GoogleFonts.inter(
                            color: AppTheme.goldAccent,
                            fontWeight: FontWeight.w400,
                          )
                        : null,
                  ),
                )
                .toList(),
          ),
        ),

        const SizedBox(height: 8),

        // Subtext
        Text(
          result.subtext,
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
              title: result.sleep.title,
              delta: result.sleep.delta,
              subtitle: result.sleep.subtitle,
              onTap: () => Navigator.pushNamed(context, result.sleep.route),
            ),
            const SizedBox(width: 8),
            KeyChangeCard(
              title: result.bloodPressure.title,
              delta: result.bloodPressure.delta,
              subtitle: result.bloodPressure.subtitle,
              onTap: () =>
                  Navigator.pushNamed(context, result.bloodPressure.route),
            ),
          ],
        ),
      ],
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
            color: isSelected
                ? const Color(0x14FFFFFF)
                : Colors.transparent, // rgba(255,255,255,0.08)
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
