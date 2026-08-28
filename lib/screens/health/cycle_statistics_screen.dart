import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../models/womens_health_models.dart';
import '../../services/chat_api_service.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/glass_back_button.dart';
import 'womens_health_widgets.dart';

const _kGlassBg = AppTheme.glassCard;
const _kGlassBorder = AppTheme.glassBorder;

TextStyle _inter(
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

Widget _glassCard({
  required Widget child,
  EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  Gradient? tint,
}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: _kGlassBg,
          gradient: tint,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kGlassBorder, width: 0.5),
        ),
        child: child,
      ),
    ),
  );
}

class CycleStatisticsScreen extends StatefulWidget {
  final List<CycleData> cycles;
  final PredictionResult? awheResult;

  const CycleStatisticsScreen({
    super.key,
    required this.cycles,
    this.awheResult,
  });

  @override
  State<CycleStatisticsScreen> createState() => _CycleStatisticsScreenState();
}

class _CycleStatisticsScreenState extends State<CycleStatisticsScreen> {
  List<String> _aiBullets = [];
  bool _aiLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAiSummary();
  }

  Future<void> _loadAiSummary() async {
    final phaseText =
        widget.awheResult?.estimatedPhase.displayName.toLowerCase() ??
        'menstrual phase';
    try {
      final result = await ChatApiService.chat(
        "Provide a 3 short bullet point summary of what to expect during the $phaseText for women's health. Format as plain text bullet points starting with dashes.",
        null,
      );
      final reply = result['reply'] as String?;
      if (reply != null) {
        final lines = reply
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.startsWith('-'))
            .map((e) => e.substring(1).trim())
            .take(3)
            .toList();
        if (lines.isNotEmpty) {
          setState(() {
            _aiBullets = lines;
            _aiLoading = false;
          });
          return;
        }
      }
    } catch (e) {
      // Fallback below
    }

    // Fallback if AI fails
    setState(() {
      _aiBullets = [
        'You might feel low on energy',
        'But as estrogen starts to rise, your mood and focus may gradually improve.',
        'Some people experience period cramps due to prostaglandins triggering uterine contractions',
      ];
      _aiLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: const GlassBackButton(),
        title: Text(
          'Cycle Statistics',
          style: _inter(16, weight: FontWeight.w600),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCyclePatternsCard(),
            const SizedBox(height: 14),
            _buildAveragesRow(),
            const SizedBox(height: 14),
            _buildAiSummaryCard(),
            const SizedBox(height: 14),
            if (widget.awheResult != null) _buildAwheCard(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildCyclePatternsCard() {
    final shown = widget.cycles;
    if (shown.isEmpty) {
      return const SizedBox.shrink();
    }
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CYCLE PATTERNS OVER TIME',
            style: _inter(
              10,
              weight: FontWeight.w700,
              color: AppTheme.textSec,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(height: 18),
            CyclePatternRow(index: i + 1, cycle: shown[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildAveragesRow() {
    int avgLen = 28;
    int varLow = 5;
    int varHigh = 7;

    if (widget.cycles.isNotEmpty) {
      int sum = 0;
      for (var c in widget.cycles) {
        sum += c.cycleLength;
      }
      avgLen = (sum / widget.cycles.length).round();
    }

    return Row(
      children: [
        Expanded(
          child: _glassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cycle Length',
                  style: _inter(
                    12,
                    color: AppTheme.textSec,
                    weight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '$avgLen',
                        style: _inter(24, weight: FontWeight.w400),
                      ),
                      TextSpan(
                        text: ' Days',
                        style: _inter(12, color: AppTheme.textSec),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _glassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cycle variation',
                  style: _inter(
                    12,
                    color: AppTheme.textSec,
                    weight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '$varLow-$varHigh',
                        style: _inter(24, weight: FontWeight.w400),
                      ),
                      TextSpan(
                        text: ' Days',
                        style: _inter(12, color: AppTheme.textSec),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAiSummaryCard() {
    String phaseText = widget.awheResult?.estimatedPhase.displayName ??
        'early follicular phase';
    phaseText = phaseText.toLowerCase();
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AI SUMMARY',
            style: _inter(
              10,
              color: AppTheme.gold,
              weight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'It’s your $phaseText',
            style: _inter(18, weight: FontWeight.w500, color: Colors.white),
          ),
          const SizedBox(height: 12),
          if (_aiLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: AppTheme.gold,
                    strokeWidth: 2.5,
                  ),
                ),
              ),
            )
          else
            ..._aiBullets.map((bullet) => _bulletPoint(bullet)),
        ],
      ),
    );
  }

  Widget _bulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6.0, right: 8.0),
            child: Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: AppTheme.textSec,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: _inter(13, color: AppTheme.textSec, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAwheCard() {
    final res = widget.awheResult;
    if (res == null) return const SizedBox.shrink();

    final phaseName = res.estimatedPhase.displayName;
    final summary = res.estimatedPhase.physiologicalSummary;

    final reasons = res.explainableReasons;

    return _glassCard(
      padding: const EdgeInsets.all(18),
      tint: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFA855F7).withValues(alpha: 0.15),
          AppTheme.womenColor.withValues(alpha: 0.08),
          Colors.transparent,
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFA855F7).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFFA855F7), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CYCLE INSIGHTS',
                      style: _inter(11, color: const Color(0xFFA855F7), weight: FontWeight.w700, letterSpacing: 1.2),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your Daily Readiness',
                      style: _inter(12, color: AppTheme.textSec),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),

            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                phaseName,
                style: _inter(18, weight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            summary,
            style: _inter(13, color: AppTheme.textSec, height: 1.3),
          ),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'WHAT YOUR RING IS NOTICING:',
              style: _inter(10, color: AppTheme.textSec, weight: FontWeight.w700, letterSpacing: 1.1),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: reasons.map((reason) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, color: AppTheme.womenColor, size: 13),
                      const SizedBox(width: 6),
                      Text(
                        reason,
                        style: _inter(12, color: Colors.white.withValues(alpha: 0.9), weight: FontWeight.w500),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Estimates from ring vitals plus cycle rules — informational only, not a medical diagnosis.',
            style: _inter(11, color: AppTheme.textSec, height: 1.3),
          ),
        ],
      ),
    );
  }
}
