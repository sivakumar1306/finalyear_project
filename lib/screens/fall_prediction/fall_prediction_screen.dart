import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../providers/fall_prediction/fall_prediction_provider.dart';
import '../../services/fall_prediction/demo_patients.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/fall_prediction/fall_risk_score_card.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/footer_spacer.dart';
import 'fall_prediction_widgets.dart';
import 'fall_score_details_screen.dart';

class FallPredictionScreen extends StatefulWidget {
  // Set when navigating here from the Home fall-prediction banner so the
  // high-tier hero card shows immediately, without needing the debug ⋮ menu.
  final bool initialHighAlert;
  // False when shown as a bottom-nav tab (no route to pop back to).
  final bool showBackButton;
  const FallPredictionScreen({
    super.key,
    this.initialHighAlert = false,
    this.showBackButton = true,
  });

  @override
  State<FallPredictionScreen> createState() => _FallPredictionScreenState();
}

class _FallPredictionScreenState extends State<FallPredictionScreen> {
  // Set when opened from the Home fall banner, so the high-tier card shows
  // immediately.
  FallTier? _debugTier;
  FallTier? _ignoredForTier;

  bool _simulateConnection = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialHighAlert) _debugTier = FallTier.high;
    _loadRealRisk();
  }

  Future<void> _loadRealRisk() async {
    // Recompute the score with the latest ring readings whenever the tab opens.
    unawaited(context.read<FallPredictionProvider>().refresh());
    await context.read<BleProvider>().getFallRiskScore();
  }

  FallTier _tierFromScore(int score) {
    if (score >= 55) return FallTier.high;
    if (score >= 25) return FallTier.medium;
    return FallTier.low;
  }

  Future<void> _openFallHistory() async {
    final events = await context.read<BleProvider>().getFallEvents(limit: 30);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.card2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => FallHistorySheet(events: events),
    );
  }

  Future<void> _ignoreWarning(FallTier tier) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.card2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Why are you ignoring this?',
                style: AppTypography.inter(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              ActionRow(
                icon: Icons.check_circle_outline,
                label: 'I\'m okay (False Alarm)',
                onTap: () => Navigator.pop(context, 'false_alarm'),
              ),
              const SizedBox(height: 8),
              ActionRow(
                icon: Icons.sports_martial_arts,
                label: 'I was just exercising',
                onTap: () => Navigator.pop(context, 'exercising'),
              ),
              const SizedBox(height: 8),
              ActionRow(
                icon: Icons.cancel_outlined,
                label: 'Cancel',
                onTap: () => Navigator.pop(context, null),
              ),
            ],
          ),
        ),
      ),
    );

    if (reason == null || !mounted) return;

    setState(() => _ignoredForTier = tier);
    await context.read<BleProvider>().dismissFallPredictionBanner();
    if (!mounted) return;
    context.read<FallPredictionProvider>().refresh();
  }

  void _openRiskDetails() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FallScoreDetailsScreen()),
    );
  }

  // ⋮ menu: the five demo patients of the report, or back to the live data.
  void _onDemoAction(String value) {
    final provider = context.read<FallPredictionProvider>();
    if (value == 'my_data') {
      provider.showMyData();
    } else {
      final patient = demoPatients.where((p) => p.id == value).firstOrNull;
      if (patient != null) provider.showDemoPatient(patient);
    }
    setState(() {
      _debugTier = null;
      _ignoredForTier = null;
    });
  }

  List<PopupMenuEntry<String>> _demoMenu(DemoPatient? active) => [
        PopupMenuItem<String>(
          enabled: false,
          height: 32,
          child: Text(
            'DEMO PATIENTS · SYNTHETIC DATA',
            style: AppTypography.inter(
              color: AppTheme.gold,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
        ),
        for (final p in demoPatients)
          PopupMenuItem<String>(
            value: p.id,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  p.name,
                  style: AppTypography.inter(
                    color: identical(p, active) ? AppTheme.gold : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  p.summary,
                  style: AppTypography.inter(color: AppTheme.textSec, fontSize: 12),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'my_data',
          enabled: active != null,
          child: Text(
            'My data',
            style: AppTypography.inter(
              color: active != null ? Colors.white : AppTheme.textSec,
              fontSize: 14,
            ),
          ),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final fallProvider = context.watch<FallPredictionProvider>();
    final realScore = fallProvider.currentResult?.frs24.value.round() ?? 0;
    final tier = _debugTier ?? _tierFromScore(realScore);

    final String message = ble.fallPredictionMessage.isNotEmpty
        ? ble.fallPredictionMessage
        : 'Your heart rate rose to 122 BPM while you seemed to be in-active for the last 10 minutes.'; // Fallback

    final demo = fallProvider.demoPatient;
    final showAlert = demo == null && tier != FallTier.low && _ignoredForTier != tier;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        automaticallyImplyLeading: false,
        leading: widget.showBackButton ? const GlassBackButton() : null,
        title: Text(
          'Fall Prediction',
          style: AppTypography.inter(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            color: AppTheme.card2,
            onSelected: _onDemoAction,
            itemBuilder: (_) => _demoMenu(demo),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        children: [
          if (demo != null) ...[
            DemoPatientCard(
              patient: demo,
              ownScore: fallProvider.ownScore,
              demoScore: fallProvider.currentResult?.frs24.value,
              onAddFall: fallProvider.addDemoFall,
              onBack: fallProvider.showMyData,
            ),
            const SizedBox(height: 20),
          ],
          if (showAlert) ...[
            HeroCard(
              tier: tier,
              message: message,
              onIgnore: () => _ignoreWarning(tier),
            ),
            const SizedBox(height: 20),
          ],
          if (ble.isConnected || _simulateConnection || demo != null) ...[
            if (_simulateConnection)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.gold.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.gold.withAlpha(100)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.science, color: AppTheme.gold, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Simulation Mode: UI is shown as if ring is connected.',
                        style: AppTypography.inter(color: AppTheme.gold, fontSize: 13),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _simulateConnection = false),
                      child: const Icon(Icons.close, color: AppTheme.gold, size: 20),
                    )
                  ],
                ),
              ),
            FallRiskScoreCard(
              onTapRiskDetails: _openRiskDetails,
              onTapHeartRate: () => Navigator.pushNamed(context, '/heart-rate'),
              onTapTemperature: () => Navigator.pushNamed(context, '/temperature'),
            ),
            const SizedBox(height: 16),
            ActionRow(
              icon: Icons.calculate_outlined,
              label: 'How this score is calculated',
              onTap: _openRiskDetails,
            ),
            const SizedBox(height: 20),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: Colors.amber,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Connect ring to enable fall prediction',
                      style: AppTypography.inter(
                        color: Colors.amber,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ActionRow(
              icon: Icons.visibility_outlined,
              label: 'Simulate Connected UI',
              onTap: () => setState(() => _simulateConnection = true),
            ),
            const SizedBox(height: 20),
          ],
          ActionRow(
            icon: Icons.directions_run_rounded,
            label: 'View Fall history',
            onTap: _openFallHistory,
          ),
          if (!widget.showBackButton) const FooterSpacer() else const SizedBox(height: 32),
        ],
      ),
    );
  }
}
