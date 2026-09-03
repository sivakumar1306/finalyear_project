import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/ble_provider.dart';
import '../settings/fall_detection_widgets.dart';
import '../../providers/home_card_provider.dart';
import '../../providers/fall_prediction/fall_prediction_provider.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/footer_spacer.dart';
import '../../widgets/glass_icon_button.dart';
import '../settings/about_screen.dart';
import '../settings/fall_detection_screen.dart';
import '../settings/goal_setting_screen.dart';
import '../settings/settings_screen.dart';
import 'card_settings_screen.dart';
import 'home_card_id.dart';
import 'ring_scan_sheet.dart';
import 'side_panel.dart';
import 'cards/home_alarm_card.dart';
import 'cards/home_card_shared.dart';
import 'cards/home_compact_cards.dart';
import 'cards/home_insight_cards.dart';
import 'cards/home_painters.dart';
import 'cards/home_vitals_cards.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final GlobalKey<HomeAiInsightSnippetState> _snippetKey =
      GlobalKey<HomeAiInsightSnippetState>();
  String _firstName = '';
  String _gender = '';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ble = context.read<BleProvider>();
      ble.checkConnection();
      // Any pending fall prediction (notification tap OR direct app open after a
      // prediction fired) — native side persists until the user dismisses the banner.
      ble.checkPendingFallPrediction();
      // Auto-SMS countdown may already be running (fall while app was backgrounded).
      ble.refreshEmergencySmsStatus();
      ble.syncTodayStepsFromRing();
      ble.refreshVitalsFromLocal();
    });
    _loadUserProfile();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check on resume: prediction may have fired while backgrounded, or the user
    // may have opened via the notification while the engine was still warm.
    if (state == AppLifecycleState.resumed) {
      final ble = context.read<BleProvider>();
      ble.checkPendingFallPrediction();
      ble.refreshEmergencySmsStatus();
      ble.syncTodayStepsFromRing();
      ble.refreshVitalsFromLocal();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool get _isFemale {
    final g = _gender.trim().toLowerCase();
    if (g.isEmpty) return false;
    return g != 'male' && g != 'm';
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = SupabaseService.currentUser;
      if (user != null) {
        final profile = await SupabaseService.getProfile(user.id);
        if (mounted && profile != null) {
          final fullName = profile['full_name'] as String? ?? '';
          setState(() {
            _firstName = fullName.split(' ').first;
            _gender = profile['gender'] as String? ?? '';
          });
          if (mounted) {
            context.read<HomeCardProvider>().ensureWomensHealthVisible(
              _isFemale,
            );
          }
          if (kDebugMode) {
            debugPrint('DEBUG profile loaded: gender=$_gender');
          }
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Error loading user profile: $e\n$stackTrace');
    }
  }

  Future<void> _navigateTo(String route) async {
    await Navigator.pushNamed(context, route);
    if (!mounted) return;
    await _loadUserProfile();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openCardSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CardSettingsScreen()),
    );
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning,';
    if (h < 17) return 'Good Afternoon,';
    if (h < 21) return 'Good Evening,';
    return 'Good Night,';
  }

  String get _dateLabel {
    final now = DateTime.now();
    const d = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const m = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return '${d[now.weekday - 1]} · ${now.day.toString().padLeft(2, '0')} ${m[now.month - 1]}';
  }

  static String _spo2Status(int v) {
    if (v <= 0) return 'No data';
    if (v >= 95) return 'Normal';
    if (v >= 90) return 'Borderline';
    return 'Low';
  }

  static String _hrStatus(int v) {
    if (v <= 0) return 'No data';
    if (v < 60) return 'Below normal';
    if (v < 100) return 'Normal';
    return 'Above normal';
  }

  static String _hrvStatus(int v) {
    if (v <= 0) return 'No data';
    if (v < 20) return 'Very Low';
    if (v < 40) return 'Low';
    if (v < 60) return 'Moderate';
    if (v < 80) return 'Good';
    return 'Excellent';
  }

  // Same formula as steps_screen.dart's _activityScore — kept in sync so the
  // home dashboard and the Steps detail screen always show the same number.
  static int _computeActivityScore(int steps, double distanceM, int calories) {
    final s = (steps / 8000 * 60).clamp(0.0, 60.0);
    final c = (calories / 250 * 25).clamp(0.0, 25.0);
    final d = (distanceM / 5000 * 15).clamp(0.0, 15.0);
    return (s + c + d).round().clamp(0, 100);
  }

  static String _sleepDurationLabel(int seconds) {
    if (seconds <= 0) return '--';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  static String _sleepStatus(int score) {
    if (score <= 0) return 'No data';
    if (score >= 80) return 'Excellent';
    if (score >= 60) return 'Good';
    if (score >= 40) return 'Fair';
    return 'Poor';
  }

  static Color _sleepStatusColor(int score) {
    if (score <= 0) return AppTheme.textSec;
    if (score >= 80) return AppTheme.success;
    if (score >= 60) return AppTheme.sleepColor;
    if (score >= 40) return AppTheme.amber;
    return AppTheme.danger;
  }

  /// Renders a single metric card.  [expanded] spans the full grid width at
  /// 1.5× the standard card height.
  Widget _buildCard(HomeCardId id, BleProvider ble, {bool expanded = false}) {
    switch (id) {
      case HomeCardId.alarms:
        return AlarmCard(expanded: expanded);
      case HomeCardId.activity:
        final hasActivityData =
            ble.isConnected ||
            ble.todaySteps > 0 ||
            ble.todayCalories > 0 ||
            ble.todayDistanceM > 0;
        return ActivityScoreCard(
          score: _computeActivityScore(
            ble.todaySteps,
            ble.todayDistanceM,
            ble.todayCalories,
          ),
          hasData: hasActivityData,
          steps: ble.todaySteps,
          calories: ble.todayCalories,
          distanceM: ble.todayDistanceM,
          expanded: expanded,
          onTap: () => _navigateTo('/steps'),
        );
      case HomeCardId.stress:
        return StressCard(
          value: ble.latestStressValue,
          avgStress: ble.todayAvgStress,
          minStress: ble.todayMinStress,
          maxStress: ble.todayMaxStress,
          hrv: ble.todayAvgHrv,
          connected: ble.isConnected || ble.latestStressValue > 0,
          expanded: expanded,
          onTap: () => _navigateTo('/stress'),
        );
      case HomeCardId.womensHealth:
        return CompactWomensHealthCard(
          expanded: expanded,
          onTap: () => _navigateTo('/womens-health'),
        );
      case HomeCardId.sleep:
        if (expanded) {
          final dur = ble.todaySleepDuration;
          final h = dur ~/ 3600;
          final m = (dur % 3600) ~/ 60;
          final stageTotal =
              ble.todaySleepDeepSecs +
              ble.todaySleepLightSecs +
              ble.todaySleepRemSecs;
          int pct(int s) => stageTotal > 0 ? (s * 100 / stageTotal).round() : 0;
          return FigmaExpandedCard(
            orbColor: AppTheme.sleepColor,
            height: 175,
            icon: Icons.bedtime_outlined,
            title: 'SLEEP',
            status: dur > 0 ? _sleepStatus(ble.todaySleepScore) : 'No data',
            value: dur > 0
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      figmaValue('$h'),
                      const SizedBox(width: 3),
                      figmaUnit('h'),
                      const SizedBox(width: 3),
                      figmaValue('$m'),
                      const SizedBox(width: 3),
                      figmaUnit('m'),
                    ],
                  )
                : figmaValue('--'),
            chart: SleepStageBar(
              deepSecs: ble.todaySleepDeepSecs,
              lightSecs: ble.todaySleepLightSecs,
              remSecs: ble.todaySleepRemSecs,
            ),
            footnoteLead: dur > 0
                ? 'Deep ${pct(ble.todaySleepDeepSecs)}%'
                : 'No data',
            footnoteRest: dur > 0
                ? ' · REM ${pct(ble.todaySleepRemSecs)}% · Light ${pct(ble.todaySleepLightSecs)}% · ${ble.todaySleepScore} score'
                : '',
            onTap: () => _navigateTo('/sleep'),
          );
        }
        return HomeCard(
          label: 'Sleep',
          value: _sleepDurationLabel(ble.todaySleepDuration),
          unit: '',
          status: ble.todaySleepDuration > 0
              ? _sleepStatus(ble.todaySleepScore)
              : 'No data',
          statusColor: _sleepStatusColor(ble.todaySleepScore),
          orbColor: AppTheme.sleepColor,
          sparkData: const [
            0.5,
            0.7,
            0.9,
            0.8,
            0.6,
            0.4,
            0.3,
            0.5,
            0.7,
            0.8,
            0.6,
            0.4,
          ],
          connected: ble.isConnected || ble.todaySleepDuration > 0,
          expanded: expanded,
          onTap: () => _navigateTo('/sleep'),
        );
      case HomeCardId.hrv:
        final latestHrvHome = ble.latestHrv > 0 ? ble.latestHrv : ble.todayAvgHrv;
        return HomeCard(
          label: 'HRV',
          value: latestHrvHome > 0 ? '$latestHrvHome' : '--',
          unit: latestHrvHome > 0 ? 'ms' : '',
          status: _hrvStatus(latestHrvHome),
          statusColor: latestHrvHome > 0 ? AppTheme.hrvColor : AppTheme.textSec,
          orbColor: AppTheme.hrvColor,
          sparkData: const [
            0.5,
            0.55,
            0.6,
            0.58,
            0.62,
            0.65,
            0.6,
            0.58,
            0.55,
            0.6,
            0.63,
            0.6,
          ],
          connected: ble.isConnected || latestHrvHome > 0,
          expanded: expanded,
          onTap: () => _navigateTo('/hrv'),
        );
      case HomeCardId.bloodOxygen:
        final latestSpo2Home = ble.latestSpo2 > 0 ? ble.latestSpo2 : ble.todayAvgSpo2;
        return HomeCard(
          label: 'Blood Oxygen',
          value: latestSpo2Home > 0 ? '$latestSpo2Home' : '--',
          unit: latestSpo2Home > 0 ? '%' : '',
          status: ble.todayAvgSpo2 > 0
              ? (ble.todayMinSpo2 > 0 && ble.todayMaxSpo2 > 0
                    ? 'Range: ${ble.todayMinSpo2}-${ble.todayMaxSpo2}%'
                    : _spo2Status(latestSpo2Home))
              : 'No data',
          statusColor: latestSpo2Home > 0 ? AppTheme.spo2Color : AppTheme.textSec,
          orbColor: AppTheme.spo2Color,
          sparkData: const [
            0.96,
            0.97,
            0.96,
            0.98,
            0.97,
            0.99,
            0.98,
            0.97,
            0.96,
            0.98,
            0.97,
            0.99,
          ],
          connected: ble.isConnected || latestSpo2Home > 0,
          expanded: expanded,
          onTap: () => _navigateTo('/blood-oxygen'),
        );
      case HomeCardId.heartRate:
        if (expanded) {
          final latest = ble.latestHr;
          final avgHr = ble.todayAvgHr;
          final hr = latest > 0 ? latest : avgHr;
          final hrv = ble.todayAvgHrv;
          return FigmaExpandedCard(
            orbColor: AppTheme.hrColor,
            height: 158,
            icon: Icons.favorite,
            title: 'HEART RATE',
            status: hr > 0 ? _hrStatus(hr) : 'No data',
            value: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                figmaValue(hr > 0 ? '$hr' : '--'),
                const SizedBox(width: 3),
                figmaUnit('BPM'),
              ],
            ),
            chart: CustomPaint(
              painter: const AreaChartPainter([
                0.45,
                0.5,
                0.55,
                0.5,
                0.6,
                0.55,
                0.5,
                0.48,
                0.52,
                0.58,
                0.54,
                0.5,
              ]),
              child: const SizedBox.expand(),
            ),
            footnoteLead: hrv > 0 ? 'HRV $hrv' : 'No data',
            footnoteRest: hr > 0
                ? ' · ${_hrStatus(hr)} zones today.'
                : ' · connect ring to track',
            onTap: () => _navigateTo('/heart-rate'),
          );
        }
        final latestForHome = ble.latestHr > 0 ? ble.latestHr : ble.todayAvgHr;
        return HomeCard(
          label: 'Heart Rate',
          value: latestForHome > 0 ? '$latestForHome' : '--',
          unit: latestForHome > 0 ? 'bpm' : '',
          status: ble.todayAvgHr > 0
              ? (ble.todayMinHr > 0 && ble.todayMaxHr > 0
                    ? 'Range: ${ble.todayMinHr}-${ble.todayMaxHr}bpm'
                    : _hrStatus(latestForHome > 0 ? latestForHome : ble.todayAvgHr))
              : 'No data',
          statusColor: latestForHome > 0 ? AppTheme.hrColor : AppTheme.textSec,
          orbColor: AppTheme.hrColor,
          sparkData: const [
            0.45,
            0.5,
            0.55,
            0.5,
            0.6,
            0.55,
            0.5,
            0.48,
            0.52,
            0.58,
            0.54,
            0.5,
          ],
          connected: ble.isConnected || ble.todayAvgHr > 0,
          expanded: expanded,
          onTap: () => _navigateTo('/heart-rate'),
        );
      case HomeCardId.bloodPressure:
        return CompactBloodPressureCard(
          expanded: expanded,
          onTap: () => _navigateTo('/blood-pressure'),
        );
      case HomeCardId.temperature:
        return TemperatureCard(
          tempC: ble.latestTempC,
          connected: ble.isConnected || ble.latestTempC > 0,
          expanded: expanded,
          onTap: () => _navigateTo('/temperature'),
        );
    }
  }

  /// Compact-mode variant of [_buildCard].
  Widget _buildCompactCard(
    HomeCardId id,
    BleProvider ble, {
    bool expanded = false,
  }) {
    switch (id) {
      case HomeCardId.alarms:
        return MiniCard(
          label: 'Alarms',
          color: AppTheme.sleepColor,
          icon: Icons.notifications_outlined,
          expanded: expanded,
          onTap: () => _navigateTo('/alarms-notifications'),
        );
      case HomeCardId.activity:
        final score = _computeActivityScore(
          ble.todaySteps,
          ble.todayDistanceM,
          ble.todayCalories,
        );
        final dist = ble.todayDistanceM;
        final distLabel = dist <= 0
            ? activityScoreLabel(score)
            : dist >= 1000
            ? '${(dist / 1000).toStringAsFixed(1)} km'
            : '${dist.round()} m';
        return MiniCard(
          label: 'Activity',
          value: '$score',
          sub: distLabel,
          color: AppTheme.focus,
          icon: Icons.directions_walk,
          expanded: expanded,
          onTap: () => _navigateTo('/steps'),
        );
      case HomeCardId.stress:
        return MiniCard(
          label: 'Stress',
          value: ble.latestStressValue > 0 ? '${ble.latestStressValue}' : '--',
          sub: stressStatus(ble.latestStressValue),
          color: AppTheme.stressColor,
          icon: Icons.water_drop,
          expanded: expanded,
          onTap: () => _navigateTo('/stress'),
        );
      case HomeCardId.womensHealth:
        return WomensHealthMiniCard(
          ble: ble,
          expanded: expanded,
          onTap: () => _navigateTo('/womens-health'),
        );
      case HomeCardId.sleep:
        return MiniCard(
          label: 'Sleep',
          value: _sleepDurationLabel(ble.todaySleepDuration),
          sub: ble.todaySleepDuration > 0
              ? _sleepStatus(ble.todaySleepScore)
              : '',
          color: AppTheme.sleepColor,
          icon: Icons.bedtime,
          expanded: expanded,
          onTap: () => _navigateTo('/sleep'),
        );
      case HomeCardId.hrv:
        final latestHrvMini = ble.latestHrv > 0 ? ble.latestHrv : ble.todayAvgHrv;
        return MiniCard(
          label: 'HRV',
          value: latestHrvMini > 0 ? '$latestHrvMini' : '--',
          sub: latestHrvMini > 0 ? 'ms' : '',
          color: AppTheme.gold,
          icon: Icons.favorite_border,
          expanded: expanded,
          onTap: () => _navigateTo('/hrv'),
        );
      case HomeCardId.bloodOxygen:
        final latestSpo2Mini = ble.latestSpo2 > 0 ? ble.latestSpo2 : ble.todayAvgSpo2;
        return MiniCard(
          label: 'SpO₂',
          value: latestSpo2Mini > 0 ? '$latestSpo2Mini' : '--',
          sub: latestSpo2Mini > 0 ? '%' : '',
          color: AppTheme.spo2Color,
          icon: Icons.air,
          expanded: expanded,
          onTap: () => _navigateTo('/blood-oxygen'),
        );
      case HomeCardId.heartRate:
        final latestMini = ble.latestHr > 0 ? ble.latestHr : ble.todayAvgHr;
        return MiniCard(
          label: 'Heart Rate',
          value: latestMini > 0 ? '$latestMini' : '--',
          sub: latestMini > 0 ? 'bpm' : '',
          color: AppTheme.hrColor,
          icon: Icons.favorite,
          expanded: expanded,
          onTap: () => _navigateTo('/heart-rate'),
        );
      case HomeCardId.bloodPressure:
        final hasBp = ble.latestBpSbp > 0 && ble.latestBpDbp > 0;
        return MiniCard(
          label: 'Blood Pressure',
          value: hasBp ? '${ble.latestBpSbp}/${ble.latestBpDbp}' : '--',
          color: AppTheme.bpColor,
          icon: Icons.speed,
          expanded: expanded,
          onTap: () => _navigateTo('/blood-pressure'),
        );
      case HomeCardId.temperature:
        return MiniCard(
          label: 'Temp',
          value: ble.latestTempC > 0
              ? '${ble.latestTempC.toStringAsFixed(1)}°'
              : '--',
          color: AppTheme.tempColor,
          icon: Icons.device_thermostat,
          expanded: expanded,
          onTap: () => _navigateTo('/temperature'),
        );
    }
  }

  /// Packs the visible cards into full-width rows: expanded cards take a row
  /// on their own; normal cards pair up two per row.  A normal card whose
  /// partner is expanded (or missing) stretches full width — matching the
  /// single-card blocks of the original layout.
  List<Widget> _packCardRows(
    BleProvider ble,
    List<HomeCardId> ids, {
    required bool compact,
    required Set<HomeCardId> expandedCards,
  }) {
    Widget build(HomeCardId id, {bool expanded = false}) => compact
        ? _buildCompactCard(id, ble, expanded: expanded)
        : _buildCard(id, ble, expanded: expanded);

    // IntrinsicHeight bounds the auto-height cards (AlarmCard,
    // ActivityScoreCard) which use Spacer in their columns — without it the
    // Row's unbounded height from the sliver makes those flex children throw
    // a RenderFlex layout error and abort every frame. It also keeps paired
    // cards equal height so they grow together with content / text scale.
    Widget row(List<Widget> children) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );

    final rows = <Widget>[];
    for (int i = 0; i < ids.length;) {
      final id = ids[i];
      if (expandedCards.contains(id)) {
        rows.add(row([Expanded(child: build(id, expanded: true))]));
        i += 1;
        continue;
      }
      final next = i + 1 < ids.length ? ids[i + 1] : null;
      if (next != null && !expandedCards.contains(next)) {
        rows.add(
          row([
            Expanded(child: build(id)),
            const SizedBox(width: 12),
            Expanded(child: build(next)),
          ]),
        );
        i += 2;
      } else {
        rows.add(row([Expanded(child: build(id))]));
        i += 1;
      }
    }
    return rows;
  }

  Widget _buildCardList(
    BleProvider ble,
    List<HomeCardId> visibleCardIds, {
    required bool compact,
    required Set<HomeCardId> expandedCards,
  }) {
    final rows = _packCardRows(
      ble,
      visibleCardIds,
      compact: compact,
      expandedCards: expandedCards,
    );
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: RepaintBoundary(child: rows[index]),
          );
        },
        childCount: rows.length,
        addRepaintBoundaries: false,
        addAutomaticKeepAlives: false,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final homeCards = context.watch<HomeCardProvider>();
    final cardOrder = homeCards.order;
    final hiddenCards = homeCards.hiddenCards;
    final expandedCards = homeCards.expandedCards;
    final compactMode = homeCards.compactMode;

    // Cards eligible to appear at all (independent of the user's show/hide
    // choice) — the Edit Cards page lists all of them, so a hidden card can
    // still be found and switched back on.
    final editableCardIds = cardOrder.where((id) {
      if (id == HomeCardId.womensHealth && !_isFemale) return false;
      return true;
    }).toList();

    // What's actually rendered day-to-day — editable cards minus anything
    // the user hid.
    final visibleCardIds = editableCardIds
        .where((id) => !hiddenCards.contains(id))
        .toList();

    return RefreshIndicator(
      color: AppTheme.gold,
      backgroundColor: AppTheme.card,
      onRefresh: () async {
        await ble.checkConnection();
        await ble.refreshVitalsFromLocal();
        await ble.syncTodayStepsFromRing();
        await _loadUserProfile();
        await _snippetKey.currentState?.reload(force: true);
      },
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        scrollCacheExtent: const ScrollCacheExtent.pixels(480),
        slivers: [
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: RepaintBoundary(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTopBar(context),
                    _buildGreetingRow(ble),
                    HomeAiInsightSnippet(key: _snippetKey),
                    _buildSectionLabel(),
                  ],
                ),
              ),
            ),
          ),

          // 1. Banner Section (Always first, static)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (ble.showFallPredictionBanner || ble.emergencySmsActive) ...[
                  if (ble.emergencySmsActive && ble.emergencySmsReason == 'fall')
                    FallEventBanner(
                      countdown: ble.emergencySmsSecondsRemaining,
                      onCardTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const FallDetectionScreen(initialHighAlert: true),
                          ),
                        );
                      },
                      onCancel: () async {
                        final response = await showDialog<String>(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: AppTheme.card,
                            title: Text('Are you okay?', style: inter(18, weight: FontWeight.w600)),
                            content: Text(
                              'Please confirm that you have not fallen and do not need emergency assistance.',
                              style: inter(14, color: Colors.white.withValues(alpha: 0.8)),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, 'cancel'),
                                child: Text('Cancel', style: inter(14, color: Colors.white54)),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, 'confirm'),
                                child: Text('I am okay', style: inter(14, color: AppTheme.hrColor, weight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        );
                        if (response == 'confirm') {
                          ble.dismissFallPredictionBanner();
                          if (context.mounted) {
                            context.read<FallPredictionProvider>().simulateTier('clear');
                          }
                        }
                      },
                    )
                  else
                    FallPredictionBanner(
                      tier: ble.fallPredictionTier,
                      message: ble.fallPredictionMessage.isNotEmpty 
                          ? ble.fallPredictionMessage 
                          : 'A fall-related alert is active.',
                      smsSecondsRemaining: ble.emergencySmsActive
                          ? ble.emergencySmsSecondsRemaining
                          : null,
                      smsHasPermission: ble.emergencySmsHasPermission,
                      onCardTap: () {
                        final isHigh = ble.fallPredictionTier == 'high' || ble.emergencySmsActive;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                FallDetectionScreen(initialHighAlert: isHigh),
                          ),
                        );
                      },
                      onPrimaryAction: () {
                        final isHigh = ble.fallPredictionTier == 'high' || ble.emergencySmsActive;
                        final countdown = ble.emergencySmsActive ? ble.emergencySmsSecondsRemaining : null;
                        if (isHigh && countdown == null) {
                          _alertContactDirectly();
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  FallDetectionScreen(initialHighAlert: isHigh),
                            ),
                          );
                        }
                      },
                      onIgnore: () async {
                        final response = await showDialog<String>(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: AppTheme.card,
                            title: Text('Are you okay?', style: inter(18, weight: FontWeight.w600)),
                            content: Text(
                              'Please confirm that you have not fallen and do not need emergency assistance.',
                              style: inter(14, color: Colors.white.withValues(alpha: 0.8)),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, 'cancel'),
                                child: Text('Cancel', style: inter(14, color: Colors.white54)),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, 'confirm'),
                                child: Text('I am okay', style: inter(14, color: AppTheme.hrColor, weight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        );
                        if (response == 'confirm') {
                          ble.dismissFallPredictionBanner();
                          if (context.mounted) {
                            context.read<FallPredictionProvider>().simulateTier('clear');
                          }
                        }
                      },
                    ),
                  const SizedBox(height: 12),
                ],
              ]),
            ),
          ),

          // 2. Card rows (paired two-per-row, or full-width when expanded)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: _buildCardList(
              ble,
              visibleCardIds,
              compact: compactMode,
              expandedCards: expandedCards,
            ),
          ),

          // 3. Edit Cards button & spacing at bottom
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 8),
                EditCardsButton(onTap: _openCardSettings),
                const FooterSpacer(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header widgets ────────────────────────────────────────────────────────

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          // Keep the same 48px tap target as before, but render the menu
          // button with the frosted-glass look used across the app.
          SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: GlassIconButton(
                icon: Icons.menu_rounded,
                iconSize: 20,
                onTap: () => showSidePanel(
                  context: context,
                  fromRight: false,
                  child: SidePanelShell(
                    fromRight: false,
                    icon: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(
                        Icons.menu_rounded,
                        color: Colors.white70,
                        size: 22,
                      ),
                    ),
                    items: [
                      SidePanelGroup(
                        items: [
                          SidePanelItem(
                            label: 'About',
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AboutScreen(),
                                ),
                              );
                            },
                          ),
                          SidePanelItem(
                            label: 'Goal Setting',
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const GoalSettingScreen(),
                                ),
                              );
                            },
                          ),
                          SidePanelItem(
                            label: 'Share',
                            onTap: () {
                              Navigator.pop(context);
                              SharePlus.instance.share(
                                ShareParams(
                                  text: 'Check out SUNDR — the AI health ring app I use to track my sleep, heart rate, and more.',
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text('Home', style: inter(16, weight: FontWeight.w600)),
            ),
          ),
          // Settings button matching the layout size of the menu button
          SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: GlassIconButton(
                icon: Icons.settings_rounded,
                iconSize: 20,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const SettingsScreen(showBackButton: true),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGreetingRow(BleProvider ble) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_greeting ${_firstName.isNotEmpty ? _firstName : 'User'}',
                  style: inter(16, weight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(_dateLabel, style: inter(12, color: AppTheme.textSec)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (ble.deviceAddress.isEmpty)
            _buildPairRingPill(context)
          else
            DevicePill(ble: ble),
        ],
      ),
    );
  }

  Widget _buildPairRingPill(BuildContext context) {
    return GestureDetector(
      onTap: () => showRingScanSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.gold.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppTheme.gold.withValues(alpha: 0.4),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, color: AppTheme.gold, size: 14),
            const SizedBox(width: 4),
            Text(
              'Pair Ring',
              style: inter(12, weight: FontWeight.w600, color: AppTheme.gold),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _alertContactDirectly() async {
    final ble = context.read<BleProvider>();
    final rows = await ble.getEmergencyContacts();
    if (rows.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No emergency contact saved yet')),
      );
      return;
    }
    final firstRow = rows.first;
    final contact = EmergencyContact(
      id: (firstRow['id'] as num?)?.toInt(),
      name: firstRow['name'] as String? ?? '',
      phone: firstRow['phone'] as String? ?? '',
    );
    final phone = contact.phone.trim();
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.card2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          AlertContactSheet(contact: contact, contactCount: rows.length),
    );
    if (action == null || !mounted) return;

    if (action == 'call') {
      final uri = Uri(scheme: 'tel', path: phone);
      final ok = await launchUrl(uri);
      if (!ok && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not reach $phone')));
      }
      return;
    }

    final isHigh = ble.fallPredictionTier == 'high' || ble.emergencySmsActive;
    final message = isHigh 
        ? "You might fall soon... We have detected multiple signs that you might fall down in the next 2-3 minutes. Take a seat and contact your caretaker. — Sent by SUNDR Fall Detection"
        : (ble.fallPredictionMessage.isNotEmpty
            ? "We are concerned ... ${ble.fallPredictionMessage} — Sent by SUNDR Fall Detection"
            : "We are concerned ... A fall-related alert is active. Please check on me as soon as possible. — Sent by SUNDR Fall Detection");

    final result = await ble.sendEmergencySms(message: message);
    if (!mounted) return;
    final ok = result['ok'] == true;
    final queued = (result['queuedCount'] as num?)?.toInt() ?? 0;
    final err = result['error'] as String?;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Sending emergency SMS to $queued contact${queued == 1 ? '' : 's'}… '
                  'delivery is confirmed as it arrives'
              : (err ?? 'Failed to send emergency SMS'),
        ),
      ),
    );
  }

  Widget _buildSectionLabel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(
        'ALL METRICS  ·  TODAY',
        style: inter(
          11,
          weight: FontWeight.w700,
          color: Colors.white.withValues(alpha: 0.38),
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

// ── AI insight snippet (under greeting, above ALL METRICS) ──────────────────
// Reuses the same insights payload the AI assist tab shows, but only surfaces
// the one-line subtext here — a quick "what matters today" without needing
// to open the AI assist screen. Cached separately from InsightsHeader's own
// cache (small duplicate network call at most once per 5 min) to avoid
// coupling the two screens' widget lifecycles together.