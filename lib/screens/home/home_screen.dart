import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../providers/fall_prediction/fall_prediction_provider.dart';
import '../../models/onboarding_data.dart';
import '../../services/supabase_service.dart';
import '../onboarding/onboarding_name_screen.dart';
import '../../services/health_engine/health_engine.dart';
import '../../theme/app_theme.dart';
import '../../widgets/footer_spacer.dart';
import '../../widgets/glass_card.dart';
import '../../utils/formatters.dart';
import '../../widgets/glass_pill.dart';
import '../fall_prediction/fall_prediction_screen.dart';
import 'home_card_id.dart';
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
  bool _showBatteryCard = false;
  bool? _lastConnected;
  // Battery: debounce the resume storm (5 MethodChannels + Health + config).
  DateTime? _lastResumeRefreshAt;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ble = context.read<BleProvider>();
      ble.checkConnection();
      _syncAfterLocal(ble);
      // Any pending fall prediction (notification tap OR direct app open after a
      // prediction fired) — native side persists until the user dismisses the banner.
      ble.checkPendingFallPrediction();
      HealthEngine.instance.refreshConfig();
      _checkBatteryOpt();
    });
    _loadCachedName();
    _loadUserProfile();
  }

  /// Paint Room first. Ring pull and the Supabase upload start only after that
  /// future returns, and neither is awaited by the frame.
  void _syncAfterLocal(BleProvider ble) {
    ble.refreshVitalsFromLocal().whenComplete(() {
      if (!mounted) return;
      ble.scheduleCloudUpload();
      ble.syncTodayStepsFromRing();
    });
  }

  Future<void> _checkBatteryOpt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final snoozedUntil = prefs.getInt('battery_prompt_dismissed_until') ?? 0;
      if (DateTime.now().millisecondsSinceEpoch < snoozedUntil) return;
      final ignoring = await BleService().isIgnoringBatteryOptimizations();
      if (mounted && !ignoring && SupabaseService.currentUser != null) {
        setState(() => _showBatteryCard = true);
      }
    } catch (_) {}
  }

  Future<void> _dismissBatteryCard() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('battery_prompt_dismissed_until',
        DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch);
    if (mounted) setState(() => _showBatteryCard = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check on resume: prediction may have fired while backgrounded, or the user
    // may have opened via the notification while the engine was still warm.
    if (state == AppLifecycleState.resumed) {
      // Battery: skip the full refresh if one ran <60s ago (e.g. quick
      // app-switch or return from a pushed route).
      final now = DateTime.now();
      if (_lastResumeRefreshAt != null &&
          now.difference(_lastResumeRefreshAt!).inSeconds < 60) {
        return;
      }
      _lastResumeRefreshAt = now;
      final ble = context.read<BleProvider>();
      ble.checkPendingFallPrediction();
      _syncAfterLocal(ble);
      HealthEngine.instance.refreshConfig();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _maybeTriggerConnectCelebration(
    bool connected,
    String address, {
    String deviceName = '',
    int battery = -1,
  }) {
    if (_lastConnected == null) {
      _lastConnected = connected;
      return;
    }
    if (!_lastConnected! && connected && address.isNotEmpty) {
      HapticFeedback.lightImpact();
      final name = deviceName.isNotEmpty ? deviceName : 'Ring';
      final message = battery >= 0
          ? 'Connected to $name • $battery%'
          : 'Connected to $name';
      showGlassPill(context, message, type: GlassPillType.success);
    }
    _lastConnected = connected;
  }

  bool get _isFemale {
    final g = _gender.trim().toLowerCase();
    if (g.isEmpty) return false;
    return g != 'male' && g != 'm';
  }

  Future<void> _loadCachedName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fullName = prefs.getString('cached_full_name') ?? '';
      if (!mounted || fullName.trim().isEmpty) return;
      setState(() => _firstName = fullName.trim().split(' ').first);
    } catch (_) {}
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return;
      final profile = await SupabaseService.getProfile(user.id);
      if (!mounted) return;
      final fullName = (profile?['full_name'] as String? ?? '').trim();
      // A successful lookup with no profile, or a profile with no name, means
      // onboarding was never finished. A thrown lookup stays on Home.
      if (profile == null || fullName.isEmpty) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => OnboardingNameScreen(data: OnboardingData()),
          ),
        );
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_full_name', fullName);
      if (!mounted) return;
      setState(() {
        _firstName = fullName.split(' ').first;
        _gender = profile['gender'] as String? ?? '';
      });
      if (kDebugMode) {
        debugPrint('DEBUG profile loaded: gender=$_gender');
      }
    } catch (e, stackTrace) {
      // Offline or a failed lookup stays on Home. The cached name remains.
      debugPrint('Error loading user profile: $e\n$stackTrace');
    }
  }

  Future<void> _navigateTo(String route) async {
    await Navigator.pushNamed(context, route);
    if (!mounted) return;
    try {
      context.read<BleProvider>().refreshVitalsFromLocal();
    } catch (_) {}
    await _loadUserProfile();
    if (!mounted) return;
    setState(() {});
  }

  String get _greeting => Formatters.greetingForHour(DateTime.now().hour);

  String get _dateLabel => Formatters.dateLabel(DateTime.now());

  static String _sleepDurationLabel(int seconds) => Formatters.sleepDuration(seconds);

  /// Renders a single metric card.  [expanded] spans the full grid width at
  /// 1.5× the standard card height.
  Widget _buildCard(HomeCardId id, BleProvider ble, {bool expanded = false}) {
    switch (id) {
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
            status: dur > 0 ? HealthEngine.instance.assessSleep(ble.todaySleepScore).label : 'No data',
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
              ? HealthEngine.instance.assessSleep(ble.todaySleepScore).label
              : 'No data',
          statusColor: HealthEngine.instance.assessSleep(ble.todaySleepScore).color,
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
          status: HealthEngine.instance.assessHrv(latestHrvHome).label,
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
                    : HealthEngine.instance.assessSpo2(latestSpo2Home).label)
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
            status: hr > 0 ? HealthEngine.instance.assessHeartRate(hr).label : 'No data',
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
                ? ' · ${HealthEngine.instance.assessHeartRate(hr).label} zones today.'
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
                    : HealthEngine.instance.assessHeartRate(latestForHome > 0 ? latestForHome : ble.todayAvgHr).label)
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

  /// Packs the cards into full-width rows, two per row. A trailing card
  /// without a partner stretches full width.
  List<Widget> _packCardRows(
    BleProvider ble,
    List<HomeCardId> ids,
  ) {
    Widget build(HomeCardId id) => _buildCard(id, ble);

    // IntrinsicHeight keeps paired cards equal height so they grow together
    // with content / text scale.
    Widget row(List<Widget> children) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );

    final rows = <Widget>[];
    for (int i = 0; i < ids.length;) {
      final id = ids[i];
      final next = i + 1 < ids.length ? ids[i + 1] : null;
      if (next != null) {
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
    List<HomeCardId> visibleCardIds,
  ) {
    final rows = _packCardRows(ble, visibleCardIds);
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
    final visibleCardIds = [
      HomeCardId.heartRate,
      HomeCardId.bloodOxygen,
      HomeCardId.hrv,
      HomeCardId.stress,
      HomeCardId.bloodPressure,
      HomeCardId.temperature,
      HomeCardId.sleep,
      if (_isFemale) HomeCardId.womensHealth,
    ];

    // Device-connect feedback: false → true fires the glass pill toast
    // (all connects: manual + auto-reconnect).
    final connectedNow = ble.isConnected;
    final addressNow = ble.deviceAddress;
    final nameNow = ble.deviceName;
    final batteryNow = ble.battery;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _maybeTriggerConnectCelebration(
          connectedNow,
          addressNow,
          deviceName: nameNow,
          battery: batteryNow,
        );
      }
    });

    return RefreshIndicator(
      color: AppTheme.gold,
      backgroundColor: AppTheme.card,
      onRefresh: () async {
        await ble.checkConnection();
        await ble.refreshVitalsFromLocal();
        ble.scheduleCloudUpload();
        unawaited(ble.syncTodayStepsFromRing());
        unawaited(_loadUserProfile());
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
                if (ble.showFallPredictionBanner) ...[
                  FallPredictionBanner(
                    tier: ble.fallPredictionTier,
                    message: ble.fallPredictionMessage.isNotEmpty
                        ? ble.fallPredictionMessage
                        : 'A fall-related alert is active.',
                    onCardTap: _openFallPrediction,
                    onPrimaryAction: _openFallPrediction,
                    onIgnore: () async {
                      final response = await showDialog<String>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: AppTheme.card,
                          title: Text('Are you okay?', style: inter(18, weight: FontWeight.w600)),
                          content: Text(
                            'Please confirm that you feel steady and do not need help.',
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
                if (_showBatteryCard) ...[
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.03),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.08), width: 0.5),
                              ),
                              child: const Icon(Icons.battery_alert_rounded,
                                  color: AppTheme.tempColor, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Background tracking may be restricted',
                                      style: inter(14, weight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text(
                                      'Your phone is optimizing battery. Allow Vital Monitoring to run uninterrupted for continuous ring sync.',
                                      style: inter(12, color: AppTheme.textSec, height: 1.4)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () async {
                                  try {
                                    await BleService().requestIgnoreBatteryOptimizations();
                                  } catch (_) {}
                                  await _dismissBatteryCard();
                                },
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: Colors.white.withValues(alpha: 0.03),
                                  side: BorderSide(
                                      color: Colors.white.withValues(alpha: 0.08), width: 0.5),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(999)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  foregroundColor: AppTheme.gold,
                                ),
                                child: Text('Allow',
                                    style: inter(13,
                                        weight: FontWeight.w600, color: AppTheme.gold)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: _dismissBatteryCard,
                              child: Text('Not now',
                                  style: inter(13, color: Colors.white54)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ]),
            ),
          ),

          // 2. Card rows (paired two-per-row)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: _buildCardList(ble, visibleCardIds),
          ),

          // 3. Spacing above the floating bottom nav
          const SliverToBoxAdapter(child: FooterSpacer()),
        ],
      ),
    );
  }

  // ── Header widgets ────────────────────────────────────────────────────────

  Widget _buildTopBar(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Center(
        child: Text('Home', style: inter(16, weight: FontWeight.w600)),
      ),
    );
  }

  void _openFallPrediction() {
    final isHigh = context.read<BleProvider>().fallPredictionTier == 'high';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FallPredictionScreen(initialHighAlert: isHigh),
      ),
    );
  }

  Widget _buildGreetingRow(BleProvider ble) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
            ],
          ),
          const SizedBox(height: 16),
          RingStatusCard(ble: ble),
        ],
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