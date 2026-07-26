import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../services/chat_api_service.dart';
import 'key_change_card.dart';

class InsightsHeader extends StatefulWidget {
  const InsightsHeader({super.key});

  @override
  State<InsightsHeader> createState() => _InsightsHeaderState();
}

class _InsightsHeaderState extends State<InsightsHeader>
    with AutomaticKeepAliveClientMixin {
  // Static so it survives this widget being disposed and recreated — e.g.
  // navigating away from the AI assist tab and back, or a fresh app open —
  // not just scroll-offscreen (that's handled by AutomaticKeepAliveClientMixin
  // below). Keyed by range so each tab (7D/30D/90D) caches independently.
  static final Map<String, Map<String, dynamic>> _cache = {};
  static final Map<String, DateTime> _cacheTime = {};
  static const _cacheTtl = Duration(minutes: 5);

  String _selectedRange = '30D';
  Future<Map<String, dynamic>>? _insightsFuture;
  Map<String, dynamic>? _cachedData;
  bool _refreshing = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load({bool forceRefresh = false}) {
    final cached = _cache[_selectedRange];
    final cachedAt = _cacheTime[_selectedRange];
    final isFresh =
        cachedAt != null && DateTime.now().difference(cachedAt) < _cacheTtl;

    if (!forceRefresh && cached != null && isFresh) {
      // Fresh cache hit — show it immediately, no network call, no spinner.
      _cachedData = cached;
      _insightsFuture = null;
      return;
    }

    // Show stale cache (if any) while a fresh fetch runs in the background,
    // instead of blanking out to a spinner on every re-fetch.
    _cachedData = cached;
    _insightsFuture = ChatApiService.getInsights(_selectedRange).then((data) {
      _cache[_selectedRange] = data;
      _cacheTime[_selectedRange] = DateTime.now();
      return data;
    });
  }

  Future<void> _onRefreshTap() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _load(forceRefresh: true);
    });
    try {
      await _insightsFuture;
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _onRangeSelect(String range) {
    if (range == _selectedRange) return;
    setState(() {
      _selectedRange = range;
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 18),

          // Title, refresh icon, and segmented control row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'AI assist',
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.w300,
                  letterSpacing: -0.04 * 28,
                  color: const Color(0xF2FFFFFF),
                ),
              ),
              Row(
                children: [
                  GestureDetector(
                    onTap: _onRefreshTap,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _refreshing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0x66FFFFFF),
                              ),
                            )
                          : const Icon(
                              Icons.refresh_rounded,
                              size: 18,
                              color: Color(0x66FFFFFF),
                            ),
                    ),
                  ),
                  _buildSegmentedControl(),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Show cached content immediately if we have it, even while a
          // background refresh (from _load) is in flight.
          _cachedData != null
              ? _buildContent(_cachedData!)
              : FutureBuilder<Map<String, dynamic>>(
                  future: _insightsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return _buildLoading();
                    }
                    final data = snapshot.data;
                    if (data == null || data['error'] != null) {
                      return _buildFallback();
                    }
                    return _buildContent(data);
                  },
                ),

          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _buildContent(Map<String, dynamic> data) {
    final headlineParts = (data['headline_parts'] as List?) ?? [];
    final subtext = data['subtext'] as String? ?? '';
    final updates = (data['updates'] as List?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Eyebrow label
        Text(
          'YOUR LAST ${_rangeLabel(_selectedRange)}',
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2 * 10,
            color: AppTheme.goldAccent,
          ),
        ),

        const SizedBox(height: 6),

        // Headline (dynamic, built from headline_parts)
        RichText(
          text: TextSpan(
            style: GoogleFonts.inter(
              fontSize: 21,
              fontWeight: FontWeight.w400,
              height: 1.30,
              letterSpacing: -0.025 * 21,
              color: const Color(0xEBFFFFFF),
            ),
            children: [
              for (final part in headlineParts)
                TextSpan(
                  text: part['text'] as String? ?? '',
                  style: (part['highlight'] == true)
                      ? GoogleFonts.inter(
                          color: AppTheme.goldAccent,
                          fontWeight: FontWeight.w400,
                        )
                      : null,
                ),
            ],
          ),
        ),

        if (subtext.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            subtext,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w400,
              height: 1.50,
              letterSpacing: 0.02 * 12.5,
              color: const Color(0x85FFFFFF),
            ),
          ),
        ],

        if (updates.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            updates.any((u) => u['alarming'] == true)
                ? 'NEEDS ATTENTION'
                : 'KEY CHANGES',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2 * 10,
              color: const Color(0x6BFFFFFF),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (int i = 0; i < updates.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: KeyChangeCard(
                    title: updates[i]['title'] as String? ?? '',
                    delta: updates[i]['delta_label'] as String? ?? '',
                    subtitle: updates[i]['subtitle'] as String? ?? '',
                    alarming: updates[i]['alarming'] == true,
                    onTap: () => _navigateFor(updates[i]['key'] as String?),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildLoading() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: SizedBox(
        height: 16,
        width: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Color(0x66FFFFFF),
        ),
      ),
    );
  }

  Widget _buildFallback() {
    return Text(
      'Your trends will appear here once we have enough recent readings.',
      style: GoogleFonts.inter(
        fontSize: 12.5,
        fontWeight: FontWeight.w400,
        height: 1.50,
        color: const Color(0x85FFFFFF),
      ),
    );
  }

  String _rangeLabel(String range) {
    switch (range) {
      case '7D':
        return '7 DAYS';
      case '90D':
        return '90 DAYS';
      default:
        return '30 DAYS';
    }
  }

  void _navigateFor(String? key) {
    switch (key) {
      case 'sleep':
        Navigator.pushNamed(context, '/sleep');
        break;
      case 'blood_pressure':
        Navigator.pushNamed(context, '/blood-pressure');
        break;
      case 'heart_rate':
        Navigator.pushNamed(context, '/heart-rate');
        break;
      case 'hrv':
        Navigator.pushNamed(context, '/hrv');
        break;
      case 'spo2':
        Navigator.pushNamed(context, '/blood-oxygen');
        break;
      case 'steps':
        Navigator.pushNamed(context, '/steps');
        break;
    }
  }

  Widget _buildSegmentedControl() {
    return Container(
      width: 131,
      height: 33,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
        border: Border.all(color: const Color(0x0FFFFFFF), width: 0.5),
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
            color: isSelected ? const Color(0x14FFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Center(
            child: Text(
              range,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                letterSpacing: 0.02 * 11,
                color: const Color(0xF2FFFFFF),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
