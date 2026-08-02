import 'dart:ui' show ImageFilter, TileMode;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../providers/alarm_mode_provider.dart';
import '../../providers/home_card_provider.dart';
import '../../services/chat_api_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_icon_button.dart';
import '../../widgets/footer_spacer.dart';
import '../settings/fall_detection_screen.dart';
import 'ring_scan_sheet.dart';
import 'side_panel.dart';
import '../settings/about_screen.dart';
import 'card_settings_screen.dart';
import '../settings/goal_setting_screen.dart';
import 'package:share_plus/share_plus.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────

const _kSec2 = Color(0xFF888888);
const _kCardBg = Color(0x0FFFFFFF); // rgba(255,255,255,0.06)
const _kCardBorder = Color(0x17FFFFFF); // rgba(255,255,255,0.09)
const _kBtnBg = Color(0x08FFFFFF); // rgba(255,255,255,0.03)
const _kBtnBorder = Color(0x14FFFFFF); // rgba(255,255,255,0.08)

// Shared filter instances — recreating ImageFilter every build is pure waste.
final ImageFilter _kOrbBlur = ImageFilter.blur(
  sigmaX: 40,
  sigmaY: 40,
  tileMode: TileMode.decal,
);
final ImageFilter _kCompactOrbBlur = ImageFilter.blur(
  sigmaX: 35,
  sigmaY: 35,
  tileMode: TileMode.decal,
);

/// Ambient metric orb — original ImageFiltered blur quality.
///
/// [RepaintBoundary] caches the blurred result so scrolling reuses the layer
/// instead of re-running the blur every frame.
class _BlurOrb extends StatelessWidget {
  final Color color;
  final double size;
  final double alpha;
  final bool compact;

  const _BlurOrb({
    required this.color,
    required this.size,
    this.alpha = 0.34,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ImageFiltered(
        imageFilter: compact ? _kCompactOrbBlur : _kOrbBlur,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInOut,
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: alpha),
          ),
        ),
      ),
    );
  }
}

// DESIGN.md per-metric orb colors (soft, desaturated)
const _kOrbHr = Color(0xFFC96B6B);
const _kOrbSleep = Color(0xFF6B82D9);
const _kOrbStress = Color(0xFF6BC99B);
const _kOrbSpo2 = Color(0xFF73D4F8);
const _kOrbActivity = Color(0xFFE08A4A);
const _kOrbHrv = Color(0xFFC9A86E);
const _kOrbTemp = Color(0xFFE3B76A);

// ── Status helpers ────────────────────────────────────────────────────────────

String _stressStatus(int v) {
  if (v <= 0) return 'No data';
  if (v < 40) return 'Relaxed';
  if (v < 60) return 'Normal';
  if (v < 80) return 'Elevated';
  return 'High';
}

Color _stressColor(int v) {
  if (v <= 0) return _kSec2;
  if (v < 40) return AppTheme.success;
  if (v < 60) return const Color(0xFFFBBF24);
  if (v < 80) return AppTheme.stressColor;
  return AppTheme.danger;
}

String _tempStatus(double v) {
  if (v <= 0) return 'No data';
  if (v < 36.0) return 'Low';
  if (v <= 37.2) return 'Normal';
  if (v <= 38.0) return 'Elevated';
  return 'Fever';
}

TextStyle _inter(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = Colors.white,
  double? letterSpacing,
  double? height,
}) => GoogleFonts.inter(
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: letterSpacing,
  height: height,
);

// ── Screen ────────────────────────────────────────────────────────────────────

enum HomeCardId {
  alarms,
  activity,
  stress,
  womensHealth,
  sleep,
  hrv,
  bloodOxygen,
  heartRate,
  bloodPressure,
  temperature,
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
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
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool get _isFemale {
    final g = _gender.trim().toLowerCase();
    return g == 'female' || g == 'f';
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
            debugPrint('DEBUG profile: $profile, parsed _gender: $_gender');
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

  static String _activityScoreLabel(int score) {
    if (score == 0) return 'Lack of exercise';
    if (score < 25) return 'Sedentary';
    if (score < 50) return 'Lightly active';
    if (score < 75) return 'Moderately active';
    return 'Highly active';
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
    if (score <= 0) return _kSec2;
    if (score >= 80) return AppTheme.success;
    if (score >= 60) return _kOrbSleep;
    if (score >= 40) return const Color(0xFFFBBF24);
    return AppTheme.danger;
  }

  /// Renders a single metric card.  [expanded] spans the full grid width at
  /// 1.5× the standard card height.
  Widget _buildCard(HomeCardId id, BleProvider ble, {bool expanded = false}) {
    switch (id) {
      case HomeCardId.alarms:
        return _AlarmCard(expanded: expanded);
      case HomeCardId.activity:
        return _ActivityScoreCard(
          score: _computeActivityScore(
            ble.todaySteps,
            ble.todayDistanceM,
            ble.todayCalories,
          ),
          hasData: ble.todaySteps > 0,
          steps: ble.todaySteps,
          calories: ble.todayCalories,
          expanded: expanded,
          onTap: () => _navigateTo('/steps'),
        );
      case HomeCardId.stress:
        return _StressCard(
          value: ble.latestStressValue,
          avgStress: ble.todayAvgStress,
          minStress: ble.todayMinStress,
          maxStress: ble.todayMaxStress,
          hrv: ble.todayAvgHrv,
          connected: ble.isConnected,
          expanded: expanded,
          onTap: () => _navigateTo('/pressure'),
        );
      case HomeCardId.womensHealth:
        return _CompactWomensHealthCard(
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
          return _FigmaExpandedCard(
            orbColor: _kOrbSleep,
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
                      _figmaValue('$h'),
                      const SizedBox(width: 3),
                      _figmaUnit('h'),
                      const SizedBox(width: 3),
                      _figmaValue('$m'),
                      const SizedBox(width: 3),
                      _figmaUnit('m'),
                    ],
                  )
                : _figmaValue('--'),
            chart: _SleepStageBar(
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
        return _HomeCard(
          label: 'Sleep',
          value: _sleepDurationLabel(ble.todaySleepDuration),
          unit: '',
          status: ble.todaySleepDuration > 0
              ? _sleepStatus(ble.todaySleepScore)
              : 'No data',
          statusColor: _sleepStatusColor(ble.todaySleepScore),
          orbColor: _kOrbSleep,
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
          connected: ble.isConnected,
          expanded: expanded,
          onTap: () => _navigateTo('/sleep'),
        );
      case HomeCardId.hrv:
        return _HomeCard(
          label: 'HRV',
          value: ble.todayAvgHrv > 0 ? '${ble.todayAvgHrv}' : '--',
          unit: ble.todayAvgHrv > 0 ? 'ms' : '',
          status: _hrvStatus(ble.todayAvgHrv),
          statusColor: ble.todayAvgHrv > 0 ? _kOrbHrv : _kSec2,
          orbColor: _kOrbHrv,
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
          connected: ble.isConnected,
          expanded: expanded,
          onTap: () => _navigateTo('/hrv'),
        );
      case HomeCardId.bloodOxygen:
        return _HomeCard(
          label: 'Blood Oxygen',
          value: ble.todayAvgSpo2 > 0 ? '${ble.todayAvgSpo2}' : '--',
          unit: ble.todayAvgSpo2 > 0 ? '%' : '',
          status: ble.todayAvgSpo2 > 0
              ? (ble.todayMinSpo2 > 0 && ble.todayMaxSpo2 > 0
                    ? 'Range: ${ble.todayMinSpo2}-${ble.todayMaxSpo2}%'
                    : _spo2Status(ble.todayAvgSpo2))
              : 'No data',
          statusColor: ble.todayAvgSpo2 > 0 ? _kOrbSpo2 : _kSec2,
          orbColor: _kOrbSpo2,
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
          connected: ble.isConnected,
          expanded: expanded,
          onTap: () => _navigateTo('/blood-oxygen'),
        );
      case HomeCardId.heartRate:
        if (expanded) {
          final hr = ble.todayAvgHr;
          final hrv = ble.todayAvgHrv;
          return _FigmaExpandedCard(
            orbColor: _kOrbHr,
            height: 152,
            icon: Icons.favorite,
            title: 'HEART RATE',
            status: hr > 0 ? _hrStatus(hr) : 'No data',
            value: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                _figmaValue(hr > 0 ? '$hr' : '--'),
                const SizedBox(width: 3),
                _figmaUnit('BPM'),
              ],
            ),
            chart: CustomPaint(
              painter: const _AreaChartPainter([
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
        return _HomeCard(
          label: 'Heart Rate',
          value: ble.todayAvgHr > 0 ? '${ble.todayAvgHr}' : '--',
          unit: ble.todayAvgHr > 0 ? 'bpm' : '',
          status: ble.todayAvgHr > 0
              ? (ble.todayMinHr > 0 && ble.todayMaxHr > 0
                    ? 'Range: ${ble.todayMinHr}-${ble.todayMaxHr}bpm'
                    : _hrStatus(ble.todayAvgHr))
              : 'No data',
          statusColor: ble.todayAvgHr > 0 ? _kOrbHr : _kSec2,
          orbColor: _kOrbHr,
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
          connected: ble.isConnected,
          expanded: expanded,
          onTap: () => _navigateTo('/heart-rate'),
        );
      case HomeCardId.bloodPressure:
        return _CompactBloodPressureCard(
          expanded: expanded,
          onTap: () => _navigateTo('/blood-pressure'),
        );
      case HomeCardId.temperature:
        return _TemperatureCard(
          tempC: ble.latestTempC,
          connected: ble.isConnected,
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
        return _MiniCard(
          label: 'Alarms',
          color: _kOrbSleep,
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
        return _MiniCard(
          label: 'Activity',
          value: ble.todaySteps > 0 ? '$score' : '--',
          sub: ble.todaySteps > 0 ? _activityScoreLabel(score) : '',
          color: _kOrbActivity,
          icon: Icons.directions_walk,
          expanded: expanded,
          onTap: () => _navigateTo('/steps'),
        );
      case HomeCardId.stress:
        return _MiniCard(
          label: 'Stress',
          value: ble.latestStressValue > 0 ? '${ble.latestStressValue}' : '--',
          sub: _stressStatus(ble.latestStressValue),
          color: _kOrbStress,
          icon: Icons.water_drop,
          expanded: expanded,
          onTap: () => _navigateTo('/pressure'),
        );
      case HomeCardId.womensHealth:
        return _MiniCard(
          label: "Women's Health",
          color: const Color(0xFFD860C8),
          icon: Icons.woman,
          expanded: expanded,
          onTap: () => _navigateTo('/womens-health'),
        );
      case HomeCardId.sleep:
        return _MiniCard(
          label: 'Sleep',
          value: _sleepDurationLabel(ble.todaySleepDuration),
          sub: ble.todaySleepDuration > 0
              ? _sleepStatus(ble.todaySleepScore)
              : '',
          color: _kOrbSleep,
          icon: Icons.bedtime,
          expanded: expanded,
          onTap: () => _navigateTo('/sleep'),
        );
      case HomeCardId.hrv:
        return _MiniCard(
          label: 'HRV',
          value: ble.todayAvgHrv > 0 ? '${ble.todayAvgHrv}' : '--',
          sub: ble.todayAvgHrv > 0 ? 'ms' : '',
          color: _kOrbHrv,
          icon: Icons.favorite_border,
          expanded: expanded,
          onTap: () => _navigateTo('/hrv'),
        );
      case HomeCardId.bloodOxygen:
        return _MiniCard(
          label: 'SpO₂',
          value: ble.todayAvgSpo2 > 0 ? '${ble.todayAvgSpo2}' : '--',
          sub: ble.todayAvgSpo2 > 0 ? '%' : '',
          color: _kOrbSpo2,
          icon: Icons.air,
          expanded: expanded,
          onTap: () => _navigateTo('/blood-oxygen'),
        );
      case HomeCardId.heartRate:
        return _MiniCard(
          label: 'Heart Rate',
          value: ble.todayAvgHr > 0 ? '${ble.todayAvgHr}' : '--',
          sub: ble.todayAvgHr > 0 ? 'bpm' : '',
          color: _kOrbHr,
          icon: Icons.favorite,
          expanded: expanded,
          onTap: () => _navigateTo('/heart-rate'),
        );
      case HomeCardId.bloodPressure:
        final hasBp = ble.latestBpSbp > 0 && ble.latestBpDbp > 0;
        return _MiniCard(
          label: 'Blood Pressure',
          value: hasBp ? '${ble.latestBpSbp}/${ble.latestBpDbp}' : '--',
          color: const Color(0xFFD86560),
          icon: Icons.speed,
          expanded: expanded,
          onTap: () => _navigateTo('/blood-pressure'),
        );
      case HomeCardId.temperature:
        return _MiniCard(
          label: 'Temp',
          value: ble.latestTempC > 0
              ? '${ble.latestTempC.toStringAsFixed(1)}°'
              : '--',
          color: _kOrbTemp,
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

    // IntrinsicHeight bounds the auto-height cards (_AlarmCard,
    // _ActivityScoreCard) which use Spacer in their columns — without it the
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
      delegate: SliverChildBuilderDelegate((context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          // Isolate each card's layer so scrolling doesn't re-rasterize the
          // whole list when a single card (or BLE update) invalidates paint.
          child: RepaintBoundary(child: rows[index]),
        );
      }, childCount: rows.length),
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
      backgroundColor: const Color(0xFF111111),
      onRefresh: () async {
        await ble.checkConnection();
        await _loadUserProfile();
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopBar(context),
                  _buildGreetingRow(ble),
                  const _HomeAiInsightSnippet(),
                  _buildSectionLabel(),
                ],
              ),
            ),
          ),

          // 1. Banner Section (Always first, static)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (ble.showFallPredictionBanner || ble.emergencySmsActive) ...[
                  _FallPredictionBanner(
                    hr: ble.fallPredictionHr > 0
                        ? ble.fallPredictionHr
                        : ble.todayMaxHr,
                    smsSecondsRemaining: ble.emergencySmsActive
                        ? ble.emergencySmsSecondsRemaining
                        : null,
                    smsHasPermission: ble.emergencySmsHasPermission,
                    onTakeAction: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const FallDetectionScreen(initialHighAlert: true),
                        ),
                      );
                    },
                    onIgnore: () => ble.dismissFallPredictionBanner(),
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
                _EditCardsButton(onTap: _openCardSettings),
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
                              Share.share(
                                'Check out SUNDR — the AI health ring app I use to track my sleep, heart rate, and more.',
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
              child: Text('Home', style: _inter(16, weight: FontWeight.w600)),
            ),
          ),
          // Balances the leading menu IconButton's tap target so 'Home' stays centered.
          const SizedBox(width: 48),
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
                  style: _inter(16, weight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(_dateLabel, style: _inter(12, color: _kSec2)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (ble.deviceAddress.isEmpty)
            _buildPairRingPill(context)
          else
            _DevicePill(ble: ble),
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
              style: _inter(12, weight: FontWeight.w600, color: AppTheme.gold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(
        'ALL METRICS  ·  TODAY',
        style: _inter(
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
class _HomeAiInsightSnippet extends StatefulWidget {
  const _HomeAiInsightSnippet();

  @override
  State<_HomeAiInsightSnippet> createState() => _HomeAiInsightSnippetState();
}

class _HomeAiInsightSnippetState extends State<_HomeAiInsightSnippet> {
  static Map<String, dynamic>? _cache;
  static DateTime? _cacheTime;
  static const _cacheTtl = Duration(minutes: 5);

  Map<String, dynamic>? _data;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final isFresh =
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheTtl;
    if (_cache != null && isFresh) {
      setState(() => _data = _cache);
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await ChatApiService.getInsights('7D');
      _cache = result;
      _cacheTime = DateTime.now();
      if (mounted) setState(() => _data = result);
    } catch (_) {
      // Silent — this is a supplementary snippet, not worth an error banner
      // on the home screen if the fetch fails.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final headlineParts = _data?['headline_parts'] as List?;
    final subtext = _data?['subtext'] as String?;
    final hasHeadline = headlineParts != null && headlineParts.isNotEmpty;

    if (_loading && !hasHeadline) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SizedBox(
          height: 14,
          width: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Color(0x4DFFFFFF),
          ),
        ),
      );
    }
    if (!hasHeadline || _data?['error'] != null) {
      return const SizedBox.shrink();
    }

    final headline = headlineParts
        .map((p) => (p as Map)['text'] as String? ?? '')
        .join();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0x0DC9A86E), // rgba(201,168,110,0.05)
              border: Border.all(
                color: const Color(0x26C9A86E), // rgba(201,168,110,0.15)
                width: 0.5,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI SUMMARY',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.18 * 10,
                    color: AppTheme.goldAccent,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  headline,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 19,
                    fontWeight: FontWeight.w400,
                    height: 1.30,
                    letterSpacing: -0.02 * 19,
                    color: Colors.white,
                  ),
                ),
                if (subtext != null && subtext.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtext,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w400,
                      height: 1.50,
                      letterSpacing: 0.02 * 12.5,
                      color: Colors.white.withValues(alpha: 0.52),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Fall prediction banner ────────────────────────────────────────────────────
// Mirrors the hero-card alert styling already established on the Fall Detection
// screen (gradient + accent border, not the ambient-orb metric-card look) so the
// same alert appears consistent whether it's seen here or after drilling in.

class _FallPredictionBanner extends StatelessWidget {
  final int hr;
  final int? smsSecondsRemaining;
  final bool smsHasPermission;
  final VoidCallback onTakeAction;
  final VoidCallback onIgnore;

  const _FallPredictionBanner({
    required this.hr,
    this.smsSecondsRemaining,
    this.smsHasPermission = true,
    required this.onTakeAction,
    required this.onIgnore,
  });

  @override
  Widget build(BuildContext context) {
    final countdown = smsSecondsRemaining;
    final accent = countdown != null ? AppTheme.hrColor : AppTheme.tempColor;
    final title = countdown != null
        ? 'Emergency SMS in ${countdown}s'
        : 'We are concerned ...';
    final body = countdown != null
        ? (!smsHasPermission
              ? 'SMS permission is missing — grant it so contacts can be alerted automatically. Open the app settings if needed.'
              : 'SMS will be sent to all emergency contacts in $countdown seconds. Tap Cancel if you are okay.')
        : (hr > 0
              ? 'Your heart rate rose to $hr BPM while you seemed to be in-active for the last 10 minutes.'
              : 'A fall-related alert is active. Take action or ignore if you are okay.');

    return _ShrinkButton(
      onTap: onTakeAction,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.25), width: 0.5),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accent.withValues(alpha: 0.30), AppTheme.card],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  countdown != null ? 'EMERGENCY SMS' : 'FALL PREDICTION',
                  style: _inter(
                    11,
                    weight: FontWeight.w700,
                    color: accent,
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(title, style: _inter(20, weight: FontWeight.w600)),
            const SizedBox(height: 10),
            Text(
              body,
              style: _inter(
                13,
                color: Colors.white.withValues(alpha: 0.85),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: onTakeAction,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.14),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: Text(
                        'Take action',
                        style: _inter(14, weight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onIgnore,
                  child: Text(
                    countdown != null ? 'Cancel SMS' : 'ignore',
                    style: _inter(
                      14,
                      weight: FontWeight.w600,
                      color: AppTheme.danger,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shrink press animation ────────────────────────────────────────────────────

class _ShrinkButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _ShrinkButton({required this.child, this.onTap});

  @override
  State<_ShrinkButton> createState() => _ShrinkButtonState();
}

class _ShrinkButtonState extends State<_ShrinkButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 1.0,
    end: 0.96,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Skip the scale layer when the card is not tappable — avoids an extra
    // composited layer over every non-interactive / edit-mode card.
    if (widget.onTap == null) {
      return widget.child;
    }
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap!();
      },
      onTapCancel: () => _ctrl.reverse(),
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

// ── Glass card foundation ─────────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  final Color orbColor;
  final Widget child;
  final double? height;
  final VoidCallback? onTap;
  final bool orbOnRight;
  final bool orbAtTop;
  final double? orbOffset;
  final double orbAlpha;
  final double orbSize;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;

  const _GlassCard({
    required this.orbColor,
    required this.child,
    this.height,
    this.onTap,
    this.orbOnRight = true,
    this.orbAtTop = false,
    this.orbOffset,
    this.orbAlpha = 0.34,
    this.orbSize = 240,
    this.padding,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    // Small fixed-height cards get a large orb so the ambient glow covers
    // ~90% of the card; full-width auto-height cards keep a corner glow.
    final double resolvedOrbOffset = orbOffset ?? (height == null ? -78 : -56);
    final content = Padding(
      padding: padding ?? const EdgeInsets.all(16),
      child: child,
    );

    // ImageFiltered blur restored for visual quality. Clip + RepaintBoundary
    // (inside _blurOrb) keep corners clean and limit re-rasterization on scroll.
    return _ShrinkButton(
      onTap: onTap,
      child: Container(
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: _kCardBg,
          border: Border.all(color: borderColor ?? _kCardBorder, width: 0.5),
        ),
        child: Stack(
          fit: height != null ? StackFit.expand : StackFit.loose,
          children: [
            Positioned(
              top: orbAtTop ? resolvedOrbOffset : null,
              bottom: orbAtTop ? null : resolvedOrbOffset,
              right: orbOnRight ? resolvedOrbOffset : null,
              left: orbOnRight ? null : resolvedOrbOffset,
              child: _BlurOrb(color: orbColor, size: orbSize, alpha: orbAlpha),
            ),
            // Fixed height: Positioned.fill gives Column tight constraints so Spacer works.
            // Auto height: plain Padding lets Stack size to content (and still
            // expands when the parent imposes a tight height via stretch).
            if (height != null) Positioned.fill(child: content) else content,
          ],
        ),
      ),
    );
  }
}

// ── Figma-style expanded card (new app page frames 478–484) ───────────────────
// Expanded cards follow the new app page anatomy: icon + mono title + chevron,
// status/value row, 36px chart area, divider, footnote.

const _kFigmaBorder = Color(0x1FFFFFFF); // rgba(255,255,255,0.12)
const _kFigmaLabel = Color(0x73FFFFFF); // rgba(255,255,255,0.45)
const _kFigmaLabelStrong = Color(0x99FFFFFF); // rgba(255,255,255,0.6)
const _kFigmaStageDeep = Color(0xFF5B7BB3);
const _kFigmaStageRem = Color(0xFFA088E0);
const _kFigmaLightBar = Color(0x59FFFFFF); // rgba(255,255,255,0.35)
const _kFigmaStressLow = Color(0xFF8FE5B5);
const _kFigmaStressHigh = Color(0xFFE88FA0);

TextStyle _figmaMono(
  double size, {
  Color color = _kFigmaLabel,
  FontWeight weight = FontWeight.w500,
  double tracking = 1.32,
}) => GoogleFonts.inter(
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: tracking,
  height: 1,
);

TextStyle _figmaFraunces(double size) => GoogleFonts.inter(
  fontSize: size,
  fontWeight: FontWeight.w300,
  color: Colors.white.withValues(alpha: 0.95),
  letterSpacing: 1.44,
  height: 1,
);

TextStyle _figmaStatusStyle() => GoogleFonts.inter(
  fontSize: 14,
  fontWeight: FontWeight.w500,
  color: Colors.white.withValues(alpha: 0.95),
  height: 1,
);

Text _figmaValue(String s) => Text(s, style: _figmaFraunces(24));

Text _figmaUnit(String s) => Text(s, style: _figmaMono(11, tracking: 0.66));

/// Shared expanded-card layout from the new app page: header row (13px icon,
/// uppercase mono title, 16px chevron), 24px status/value row, 36px chart,
/// 1px divider and a two-tone mono footnote.
class _FigmaExpandedCard extends StatelessWidget {
  final Color orbColor;
  final double height;
  final IconData icon;
  final String title;
  final String status;
  final Widget value;
  final Widget chart;
  final String footnoteLead;
  final String footnoteRest;
  final VoidCallback? onTap;

  const _FigmaExpandedCard({
    required this.orbColor,
    required this.height,
    required this.icon,
    required this.title,
    required this.status,
    required this.value,
    required this.chart,
    required this.footnoteLead,
    required this.footnoteRest,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      orbColor: orbColor,
      height: height,
      orbAlpha: 0.25,
      orbSize: 220,
      borderColor: _kFigmaBorder,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: Colors.white.withValues(alpha: 0.6)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: _figmaMono(11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 16, color: _kFigmaLabel),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  status,
                  style: _figmaStatusStyle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              value,
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(height: 36, width: double.infinity, child: chart),
          const SizedBox(height: 10),
          Container(height: 1, width: double.infinity, color: _kFigmaBorder),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              style: _figmaMono(11, tracking: 0.44),
              children: [
                TextSpan(
                  text: footnoteLead,
                  style: const TextStyle(
                    color: _kFigmaLabelStrong,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(text: footnoteRest),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Sleep stage bar — deep / REM / light segments with the design's 4px gap
/// and rounded leading/trailing corners.  Falls back to equal thirds when no
/// stage data has arrived yet.
class _SleepStageBar extends StatelessWidget {
  final int deepSecs;
  final int lightSecs;
  final int remSecs;

  const _SleepStageBar({
    required this.deepSecs,
    required this.lightSecs,
    required this.remSecs,
  });

  @override
  Widget build(BuildContext context) {
    final total = deepSecs + lightSecs + remSecs;
    int flex(int v) =>
        total <= 0 ? 1 : (v / total * 1000).round().clamp(1, 1000).toInt();
    return Row(
      children: [
        Expanded(
          flex: flex(deepSecs),
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: _kFigmaStageDeep,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(4),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          flex: flex(remSecs),
          child: Container(height: 8, color: _kFigmaStageRem),
        ),
        const SizedBox(width: 4),
        Expanded(
          flex: flex(lightSecs),
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: _kFigmaLightBar,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Activity progress bar — 8px track with a rounded 35%-white fill.
class _ActivityProgressBar extends StatelessWidget {
  final double fraction;
  const _ActivityProgressBar({required this.fraction});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 8,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: fraction.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: _kFigmaLightBar,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

/// Cycle phase bar — menstrual / follicular / ovulating / luteal segments
/// with a day marker above the bar.
class _CyclePhaseBar extends StatelessWidget {
  final int cycleDay;
  final int cycleLength;
  final int periodLen;

  const _CyclePhaseBar({
    required this.cycleDay,
    required this.cycleLength,
    required this.periodLen,
  });

  @override
  Widget build(BuildContext context) {
    final len = cycleLength > 0 ? cycleLength : 28;
    final pLen = periodLen > 0 ? periodLen : 5;
    final day = cycleDay.clamp(1, len).toInt();
    int flex(int v) => v.clamp(1, len).toInt();

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Row(
              children: [
                Expanded(
                  flex: flex(pLen),
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: _kFigmaStressHigh,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  flex: flex(13 - pLen),
                  child: Container(height: 8, color: _kFigmaLightBar),
                ),
                const SizedBox(width: 4),
                Expanded(
                  flex: flex(3),
                  child: Container(height: 8, color: _kFigmaStressLow),
                ),
                const SizedBox(width: 4),
                Expanded(
                  flex: flex(len - 16),
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: _kFigmaStageDeep,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: (constraints.maxWidth * ((day - 0.5) / len)) - 5,
              top: -4,
              child: Icon(
                Icons.arrow_drop_down,
                size: 12,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Chevron button (glass) ────────────────────────────────────────────────────

Widget _chevron() => Container(
  width: 26,
  height: 26,
  decoration: BoxDecoration(
    shape: BoxShape.circle,
    color: Colors.white.withValues(alpha: 0.08),
    border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
  ),
  child: const Icon(
    Icons.chevron_right_rounded,
    color: Colors.white54,
    size: 16,
  ),
);

// ── Mini card (compact mode) ───────────────────────────────────────────────────

class _MiniCard extends StatelessWidget {
  final String label;
  final String? value;
  final String? sub;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;
  final bool expanded;

  const _MiniCard({
    required this.label,
    this.value,
    this.sub,
    required this.color,
    required this.icon,
    this.onTap,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      orbColor: color,
      height: expanded ? 195 : 130,
      orbAlpha: 0.25,
      orbSize: 180,
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 14, color: color),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white54,
                  size: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: _inter(
              10,
              weight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          if (value != null) ...[
            Text(value!, style: _inter(20, weight: FontWeight.w600)),
            if (sub != null) Text(sub!, style: _inter(10, color: _kSec2)),
          ],
          if (expanded) const Spacer(),
        ],
      ),
    );
  }
}

// ── Generic half-width metric card ────────────────────────────────────────────

class _HomeCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final String status;
  final Color statusColor;
  final Color orbColor;
  final List<double> sparkData;
  final bool connected;
  final VoidCallback? onTap;
  final bool expanded;

  const _HomeCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.status,
    required this.statusColor,
    required this.orbColor,
    required this.sparkData,
    required this.connected,
    this.onTap,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      orbColor: orbColor,
      height: expanded ? 240 : 160,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: _inter(
                    13,
                    weight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _chevron(),
            ],
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value,
                          style: GoogleFonts.inter(
                            fontSize: 30,
                            fontWeight: FontWeight.w200,
                            color: Colors.white.withValues(alpha: 0.95),
                          ),
                        ),
                      ),
                    ),
                    if (unit.isNotEmpty) ...[
                      const SizedBox(width: 3),
                      Text(
                        unit,
                        style: _inter(
                          11,
                          weight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 28,
                  child: connected
                      ? CustomPaint(painter: _SparkPainter(orbColor, sparkData))
                      : const _ConnectHint(compact: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            status,
            style: _inter(11, color: statusColor, weight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Full-width Stress card ────────────────────────────────────────────────────

class _StressCard extends StatelessWidget {
  final int value;
  final int avgStress;
  final int minStress;
  final int maxStress;
  final int hrv;
  final bool connected;
  final VoidCallback? onTap;
  final bool expanded;

  static const _barData = [
    0.30,
    0.45,
    0.38,
    0.52,
    0.48,
    0.42,
    0.55,
    0.38,
    0.47,
    0.35,
    0.60,
    0.55,
    0.48,
    0.40,
    0.35,
    0.42,
    0.50,
    0.45,
    0.38,
    0.30,
    0.40,
    0.35,
    0.28,
    0.32,
  ];

  static final _bars40 = _interpolate(_barData, 40);

  const _StressCard({
    required this.value,
    required this.avgStress,
    required this.minStress,
    required this.maxStress,
    required this.connected,
    this.hrv = 0,
    this.onTap,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final status = _stressStatus(value);
    final color = _stressColor(value);

    if (expanded) {
      return _FigmaExpandedCard(
        orbColor: _kOrbStress,
        height: 158,
        icon: Icons.monitor_heart,
        title: 'STRESS',
        status: value > 0 ? status : 'No data',
        value: _figmaValue(hrv > 0 ? 'HRV $hrv' : '--'),
        chart: CustomPaint(
          painter: _StressMiniBarsPainter(_bars40),
          child: const SizedBox.expand(),
        ),
        footnoteLead: avgStress > 0 ? 'Avg $avgStress' : 'No data',
        footnoteRest: maxStress > 0 ? ' · Range $minStress-$maxStress' : '',
        onTap: onTap,
      );
    }

    // Auto-height: fixed pixel heights clip on denser fonts / text scale /
    // narrow phones. Content defines the card height instead.  Expanded cards
    // switch to the fixed 1.5× height (240 = 1.5 × the standard 160 card).
    return _GlassCard(
      orbColor: _kOrbStress,
      orbOnRight: false,
      orbOffset: -78,
      height: expanded ? 240 : null,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Stress',
                  style: _inter(
                    15,
                    weight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _chevron(),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value > 0 ? '$value' : '--',
                style: GoogleFonts.inter(
                  fontSize: 36,
                  fontWeight: FontWeight.w300,
                  height: 1.1,
                  color: Colors.white.withValues(alpha: 0.95),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  status,
                  style: _inter(
                    13,
                    color: color,
                    weight: FontWeight.w500,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 24,
            width: double.infinity,
            child: connected
                ? CustomPaint(painter: _BarChartPainter(_kOrbStress, _barData))
                : const _ConnectHint(),
          ),
          const SizedBox(height: 8),
          Container(
            height: 1,
            width: double.infinity,
            color: Colors.white.withValues(alpha: 0.08),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _StressStatColumn(
                  label: 'Daily Average',
                  value: avgStress > 0 ? '$avgStress' : '--',
                  status: _stressStatus(avgStress),
                ),
              ),
              Container(
                width: 1,
                height: 48,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              Expanded(
                child: _StressStatColumn(
                  label: 'Daily Range',
                  value: maxStress > 0 ? '$minStress-$maxStress' : '--',
                  status: _stressStatus(maxStress),
                ),
              ),
            ],
          ),
          if (expanded) const Spacer(),
        ],
      ),
    );
  }
}

/// Bottom stat cell for the Stress card — keeps label/value/status from
/// overflowing by using explicit line heights and ellipsis.
class _StressStatColumn extends StatelessWidget {
  final String label;
  final String value;
  final String status;

  const _StressStatColumn({
    required this.label,
    required this.value,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: _inter(
            11,
            color: Colors.white.withValues(alpha: 0.4),
            weight: FontWeight.w500,
            height: 1.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 22,
            fontWeight: FontWeight.w300,
            height: 1.15,
            color: Colors.white.withValues(alpha: 0.95),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          status,
          style: _inter(
            11,
            color: Colors.white.withValues(alpha: 0.5),
            weight: FontWeight.w400,
            height: 1.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
// ── Activity score card ────────────────────────────────────────────────────────

class _ActivityScoreCard extends StatelessWidget {
  final int score;
  final bool hasData;
  final int steps;
  final int calories;
  final VoidCallback? onTap;
  final bool expanded;

  const _ActivityScoreCard({
    required this.score,
    required this.hasData,
    this.steps = 0,
    this.calories = 0,
    this.onTap,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    if (expanded) {
      final activeMin = steps ~/ 100;
      final remaining = (10000 - steps).clamp(0, 10000).toInt();
      return _FigmaExpandedCard(
        orbColor: _kOrbActivity,
        height: 158,
        icon: Icons.directions_walk,
        title: 'ACTIVITY',
        status: steps > 0
            ? (steps >= 10000 ? 'On Target' : 'Below Target')
            : 'No data',
        value: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            _figmaValue(steps > 0 ? _formatInt(steps) : '--'),
            const SizedBox(width: 3),
            _figmaUnit('/ 10K'),
          ],
        ),
        chart: _ActivityProgressBar(fraction: steps / 10000.0),
        footnoteLead: calories > 0 ? '${_formatInt(calories)} cal' : 'No data',
        footnoteRest: steps > 0
            ? ' · $activeMin min active · ${_formatInt(remaining)} to go'
            : '',
        onTap: onTap,
      );
    }
    // No fixed height — pairs with _AlarmCard via IntrinsicHeight so both
    // grow together when text scale / font metrics need more room.  Expanded
    // cards switch to the fixed 1.5× height (240 = 1.5 × the standard 160).
    return _GlassCard(
      orbColor: _kOrbActivity,
      orbOnRight: true,
      orbAlpha: 0.25,
      height: expanded ? 240 : null,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Activity',
                  style: _inter(
                    15,
                    weight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _chevron(),
            ],
          ),
          const SizedBox(height: 10),
          Divider(
            color: Colors.white.withValues(alpha: 0.08),
            height: 1,
            thickness: 0.5,
          ),
          // Spacer only expands after IntrinsicHeight assigns a shared height
          // (contributes 0 to intrinsic measurement).
          const Spacer(),
          Text(
            hasData ? '$score' : '--',
            style: GoogleFonts.inter(
              fontSize: 40,
              fontWeight: FontWeight.w300,
              height: 1.1,
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _HomeScreenState._activityScoreLabel(score),
            style: _inter(
              13,
              weight: FontWeight.w500,
              color: _kOrbActivity,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Alarms card ────────────────────────────────────────────────────────────────

class _AlarmModeInfo {
  final String title;
  final String subtitle;
  final String segmentLabel;
  final Color color;
  final IconData icon;
  const _AlarmModeInfo(
    this.title,
    this.subtitle,
    this.segmentLabel,
    this.color,
    this.icon,
  );
}

const Map<PhoneMode, _AlarmModeInfo> _kAlarmModeInfo = {
  PhoneMode.focus: _AlarmModeInfo(
    'Focus',
    'Until 13:00',
    'Focus',
    AppTheme.focus,
    Icons.adjust_rounded,
  ),
  PhoneMode.base: _AlarmModeInfo(
    'Normal',
    'All alerts on',
    'Base',
    AppTheme.base,
    Icons.circle_outlined,
  ),
  PhoneMode.prayer: _AlarmModeInfo(
    'Prayer mode',
    'Dhuhr 13:14',
    'Prayer',
    AppTheme.success,
    Icons.self_improvement_rounded,
  ),
};

class _AlarmCard extends StatelessWidget {
  final bool expanded;

  const _AlarmCard({this.expanded = false});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AlarmModeProvider>();
    final mode = provider.mode;
    final info = _kAlarmModeInfo[mode]!;
    // No fixed height — content + text scale dictate size; IntrinsicHeight in
    // the parent row keeps this paired with the Activity card.  Expanded
    // cards switch to the fixed 1.5× height (240 = 1.5 × the standard 160).
    return _GlassCard(
      orbColor: info.color,
      orbAtTop: true,
      orbSize: 260,
      orbOffset: -80,
      orbAlpha: 0.4,
      height: expanded ? 240 : null,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + mode title (not wrapped in Expanded so intrinsic height
          // measurement includes this content — critical for IntrinsicHeight).
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pushNamed(context, '/alarms-notifications'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'ALARMS',
                        style: _inter(
                          11,
                          weight: FontWeight.w700,
                          color: info.color,
                          letterSpacing: 1.2,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _chevron(),
                  ],
                ),
                const SizedBox(height: 10),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 420),
                  switchInCurve: const Cubic(0.34, 1.2, 0.64, 1.0),
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (currentChild, previousChildren) {
                    return Stack(
                      alignment: Alignment.centerLeft,
                      children: <Widget>[...previousChildren, ?currentChild],
                    );
                  },
                  transitionBuilder: (child, anim) {
                    final offset = Tween<Offset>(
                      begin: const Offset(0, 0.18),
                      end: Offset.zero,
                    ).animate(anim);
                    return FadeTransition(
                      opacity: anim,
                      child: SlideTransition(position: offset, child: child),
                    );
                  },
                  child: Column(
                    key: ValueKey(mode),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        info.title,
                        style: GoogleFonts.inter(
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                          height: 1.15,
                          color: info.color,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        info.subtitle,
                        style: _inter(
                          13,
                          color: Colors.white.withValues(alpha: 0.6),
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Fills leftover space once the row shares a height with Activity.
          const Spacer(),
          const SizedBox(height: 10),
          _AlarmModeSelector(
            mode: mode,
            onChanged: (m) => requestPhoneMode(context, provider, m),
          ),
        ],
      ),
    );
  }
}

// Apple-style liquid-glass segmented control for Focus / Normal / Prayer.
// A single frosted pill slides under the active mode with springy motion and
// soft color morph — not per-segment solid fills that pop.
class _AlarmModeSelector extends StatelessWidget {
  final PhoneMode mode;
  final ValueChanged<PhoneMode> onChanged;
  const _AlarmModeSelector({required this.mode, required this.onChanged});

  static const _kSlideDuration = Duration(milliseconds: 480);
  // Slight overshoot — feels like liquid glass settling into place.
  static const _kSlideCurve = Cubic(0.34, 1.25, 0.64, 1.0);

  @override
  Widget build(BuildContext context) {
    final modes = PhoneMode.values;
    final selectedIndex = modes.indexOf(mode);
    final selectedInfo = _kAlarmModeInfo[mode]!;
    // Alignment.x for equal-width segments: -1, 0, +1 for 3 items.
    final alignX = modes.length <= 1
        ? 0.0
        : -1.0 + (2.0 * selectedIndex / (modes.length - 1));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _kBtnBg,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: _kBtnBorder, width: 0.5),
      ),
      // Row defines height; thumb fills that height and slides across segments.
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              duration: _kSlideDuration,
              curve: _kSlideCurve,
              alignment: Alignment(alignX, 0),
              child: FractionallySizedBox(
                widthFactor: 1 / modes.length,
                heightFactor: 1,
                child: Padding(
                  padding: const EdgeInsets.all(1),
                  child: _LiquidGlassThumb(color: selectedInfo.color),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final m in modes)
                Expanded(
                  child: _AlarmSegment(
                    mode: m,
                    selected: m == mode,
                    onTap: () {
                      if (m == mode) return;
                      HapticFeedback.selectionClick();
                      onChanged(m);
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Frosted pill that morphs color as the active mode changes.
class _LiquidGlassThumb extends StatelessWidget {
  final Color color;
  const _LiquidGlassThumb({required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: _AlarmModeSelector._kSlideDuration,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(Colors.white, color, 0.55)!.withValues(alpha: 0.28),
            color.withValues(alpha: 0.18),
            color.withValues(alpha: 0.10),
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
        border: Border.all(
          color: Color.lerp(
            Colors.white.withValues(alpha: 0.35),
            color.withValues(alpha: 0.55),
            0.5,
          )!,
          width: 0.8,
        ),
        boxShadow: [
          // Soft colored bloom — liquid glass glow
          BoxShadow(
            color: color.withValues(alpha: 0.32),
            blurRadius: 14,
            spreadRadius: -2,
            offset: const Offset(0, 2),
          ),
          // Specular top edge
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.10),
            blurRadius: 0.5,
            offset: const Offset(0, -0.5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: const DecoratedBox(
          decoration: BoxDecoration(
            // Subtle top sheen
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.center,
              colors: [Color(0x28FFFFFF), Color(0x00FFFFFF)],
            ),
          ),
        ),
      ),
    );
  }
}

class _AlarmSegment extends StatelessWidget {
  final PhoneMode mode;
  final bool selected;
  final VoidCallback onTap;

  const _AlarmSegment({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final info = _kAlarmModeInfo[mode]!;
    final idle = Colors.white.withValues(alpha: 0.42);
    final active = info.color;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: AnimatedScale(
          scale: selected ? 1.06 : 1.0,
          duration: _AlarmModeSelector._kSlideDuration,
          curve: _AlarmModeSelector._kSlideCurve,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) {
                  return FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.85, end: 1.0).animate(anim),
                      child: child,
                    ),
                  );
                },
                child: Icon(
                  info.icon,
                  key: ValueKey<bool>(selected),
                  size: selected ? 15 : 14,
                  color: selected ? active : idle,
                ),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                style: _inter(
                  10,
                  weight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? active : idle,
                  height: 1.1,
                ),
                child: Text(
                  info.segmentLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// ── Women's Health card ───────────────────────────────────────────────────────

// ── Compact health card widgets ──────────────────────────────────────────────

class _CompactHealthCard extends StatelessWidget {
  final String title;
  final Color orbColor;
  final bool orbOnRight;
  final VoidCallback? onTap;
  final Widget child;
  final bool expanded;
  // When set, replaces the default radial orb glow with this gradient — used
  // by cards (e.g. Temperature) that need a directional fade instead.
  final Gradient? overlayGradient;

  const _CompactHealthCard({
    required this.title,
    required this.orbColor,
    required this.child,
    this.orbOnRight = true,
    this.onTap,
    this.expanded = false,
    this.overlayGradient,
  });

  @override
  Widget build(BuildContext context) {
    // ImageFiltered blur restored for orb quality. No BackdropFilter — solid
    // dark scaffold makes backdrop blur nearly free of benefit but costly.
    return _ShrinkButton(
      onTap: onTap,
      child: Container(
        height: expanded ? 240 : 160,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color.fromRGBO(245, 240, 226, 0.06),
          border: Border.all(
            color: const Color.fromRGBO(245, 240, 226, 0.09),
            width: 0.5,
          ),
        ),
        child: Stack(
          children: [
            if (overlayGradient != null)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: overlayGradient),
                ),
              )
            else
              Positioned(
                top: -40,
                left: orbOnRight ? null : -40,
                right: orbOnRight ? -40 : null,
                child: _BlurOrb(
                  color: orbColor,
                  size: 220,
                  alpha: 0.35,
                  compact: true,
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: _inter(
                            14,
                            weight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.95),
                            letterSpacing: -0.01,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.06),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                            width: 0.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white70,
                          size: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 0.5,
                    width: double.infinity,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactWomensHealthCard extends StatefulWidget {
  final VoidCallback? onTap;
  final bool expanded;
  const _CompactWomensHealthCard({this.onTap, this.expanded = false});

  @override
  State<_CompactWomensHealthCard> createState() =>
      _CompactWomensHealthCardState();
}

class _CompactWomensHealthCardState extends State<_CompactWomensHealthCard> {
  int _cycleDay = 0;
  int _cycleLength = 28;
  int _periodLen = 5;

  @override
  void initState() {
    super.initState();
    _loadCycle();
  }

  Future<void> _loadCycle() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return;
      final rows = await SupabaseService.getCycles(user.id);
      if (rows.isEmpty || !mounted) return;
      final row = rows.first;
      final periodStart = DateTime.parse(row['period_start'] as String);
      final cycleLength = (row['cycle_length'] as num? ?? 28).toInt();
      final periodLength = (row['period_length'] as num? ?? 5).toInt();
      final day = DateTime.now().difference(periodStart).inDays + 1;
      setState(() {
        _cycleDay = day.clamp(1, cycleLength);
        _cycleLength = cycleLength;
        _periodLen = periodLength;
      });
      if (kDebugMode) {
        debugPrint(
          'DEBUG: Loaded cycle day: $_cycleDay, cycleLength: $_cycleLength, periodLength: $_periodLen',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Error loading cycle data in compact card: $e\n$stackTrace');
    }
  }

  String get _phaseName {
    if (_cycleDay <= 0) return '---';
    if (_cycleDay <= _periodLen) return 'Menstruation';
    if (_cycleDay <= 13) return 'Follicular';
    if (_cycleDay <= 16) return 'Ovulating';
    return 'Luteal';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.expanded) {
      final daysLeft = (_cycleLength - _cycleDay + 1).clamp(1, _cycleLength);
      return _FigmaExpandedCard(
        orbColor: const Color(0xFFD860C8),
        height: 158,
        icon: Icons.woman,
        title: 'CYCLE',
        status: _cycleDay > 0 ? _phaseName : 'No data',
        value: _figmaValue(_cycleDay > 0 ? 'Day $_cycleDay' : 'Day --'),
        chart: _CyclePhaseBar(
          cycleDay: _cycleDay,
          cycleLength: _cycleLength,
          periodLen: _periodLen,
        ),
        footnoteLead: _cycleDay > 0
            ? 'Next period in $daysLeft days'
            : 'No data',
        footnoteRest: _cycleDay > 0
            ? ' · ${_phaseName.toLowerCase()} phase'
            : '',
        onTap: widget.onTap,
      );
    }
    return _CompactHealthCard(
      title: 'Women\'s Health',
      orbColor: const Color.fromRGBO(216, 96, 200, 0.32),
      orbOnRight: true,
      expanded: widget.expanded,
      onTap: widget.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _cycleDay > 0 ? 'Day $_cycleDay' : 'Day --',
            style: GoogleFonts.inter(
              fontSize: 34,
              fontWeight: FontWeight.w200,
              color: Colors.white.withValues(alpha: 0.98),
              letterSpacing: -0.005,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _phaseName,
            style: _inter(
              12,
              weight: FontWeight.w500,
              color: const Color(0xFFE8867F),
              letterSpacing: -0.005,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactBloodPressureCard extends StatelessWidget {
  final VoidCallback? onTap;
  final bool expanded;
  const _CompactBloodPressureCard({this.onTap, this.expanded = false});

  String _bpCompactStatus(int sbp, int dbp) {
    if (sbp <= 0 || dbp <= 0) return 'No data';
    if (sbp < 120 && dbp < 80) return 'Normal';
    if (sbp < 130 && dbp < 80) return 'Elevated';
    if (sbp < 140 || dbp < 90) return 'Stage 1';
    return 'Stage 2';
  }

  Color _bpCompactStatusColor(int sbp, int dbp) {
    if (sbp <= 0 || dbp <= 0) return _kSec2;
    if (sbp < 120 && dbp < 80) return AppTheme.success;
    if (sbp < 130 && dbp < 80) return const Color(0xFFFBBF24);
    if (sbp < 140 || dbp < 90) return AppTheme.stressColor;
    return AppTheme.danger;
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final sbp = ble.latestBpSbp;
    final dbp = ble.latestBpDbp;
    final hasData = sbp > 0 && dbp > 0;

    if (expanded) {
      return _FigmaExpandedCard(
        orbColor: const Color(0xFFD86560),
        height: 161,
        icon: Icons.water_drop,
        title: 'BLOOD PRESSURE',
        status: hasData ? _bpCompactStatus(sbp, dbp) : 'No data',
        value: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            _figmaValue(hasData ? '$sbp' : '--'),
            const SizedBox(width: 3),
            _figmaUnit(hasData ? '/$dbp' : '/--'),
          ],
        ),
        chart: CustomPaint(
          painter: _BpChartPainter(sbp: sbp, dbp: dbp),
          child: const SizedBox.expand(),
        ),
        footnoteLead: hasData ? '$sbp/$dbp mmHg' : 'No data',
        footnoteRest: hasData ? ' · latest reading' : '',
        onTap: onTap,
      );
    }

    return _CompactHealthCard(
      title: 'Blood Pressure',
      orbColor: const Color.fromRGBO(216, 101, 96, 0.32),
      expanded: expanded,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                hasData ? '$sbp' : '--',
                style: GoogleFonts.inter(
                  fontSize: 34,
                  fontWeight: FontWeight.w200,
                  color: Colors.white.withValues(alpha: 0.98),
                  letterSpacing: -0.005,
                ),
              ),
              Text(
                hasData ? '/$dbp' : '/--',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w300,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _bpCompactStatus(sbp, dbp),
            style: _inter(
              12,
              weight: FontWeight.w500,
              color: _bpCompactStatusColor(sbp, dbp),
              letterSpacing: -0.005,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Temperature card ──────────────────────────────────────────────────────────
// Diagonal glass fade — warm #F5F0E2 highlight top-right easing through the
// spec's 6% base tone, down to a black-tinted bottom-left corner.

class _TemperatureCard extends StatelessWidget {
  final double tempC;
  final bool connected;
  final VoidCallback? onTap;
  final bool expanded;

  const _TemperatureCard({
    required this.tempC,
    required this.connected,
    this.onTap,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasData = tempC > 0;

    return _CompactHealthCard(
      title: 'Temperature',
      orbColor: _kOrbTemp,
      expanded: expanded,
      onTap: onTap,
      overlayGradient: const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        stops: [0.0, 0.5, 1.0],
        colors: [
          Color(0x26F5F0E2), // brighter warm highlight at the top-right corner
          Color(0x0FF5F0E2), // spec: #F5F0E2 @ 6%
          Color(0x59000000), // black touch fading in at the bottom-left
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                hasData ? tempC.toStringAsFixed(1) : '--',
                style: GoogleFonts.inter(
                  fontSize: 34,
                  fontWeight: FontWeight.w200,
                  color: Colors.white.withValues(alpha: 0.98),
                  letterSpacing: -0.005,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                '°C',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w300,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _tempStatus(tempC),
            style: _inter(
              12,
              weight: FontWeight.w500,
              color: hasData ? _kOrbTemp : _kSec2,
              letterSpacing: -0.005,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Device pill ───────────────────────────────────────────────────────────────

class _DevicePill extends StatelessWidget {
  final BleProvider ble;
  const _DevicePill({required this.ble});

  @override
  Widget build(BuildContext context) {
    final connected = ble.isConnected;
    final reconnecting = ble.isReconnecting;
    final battery = ble.battery;

    return GestureDetector(
      onTap: () => showRingScanSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: _kCardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kCardBorder, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reconnecting)
              const SizedBox(
                width: 7,
                height: 7,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppTheme.gold,
                ),
              )
            else
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: connected
                      ? AppTheme.success
                      : Colors.white.withValues(alpha: 0.2),
                ),
              ),
            const SizedBox(width: 6),
            Text(
              ble.deviceName.isNotEmpty ? ble.deviceName : 'Ring',
              style: _inter(12, weight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (battery >= 0) ...[
              const SizedBox(width: 5),
              Icon(
                battery > 60
                    ? Icons.battery_full_rounded
                    : battery > 30
                    ? Icons.battery_3_bar_rounded
                    : Icons.battery_1_bar_rounded,
                color: battery > 20
                    ? Colors.white.withValues(alpha: 0.5)
                    : AppTheme.danger,
                size: 14,
              ),
              Text(
                '$battery%',
                style: _inter(11, color: Colors.white.withValues(alpha: 0.5)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Connect hint ──────────────────────────────────────────────────────────────

class _ConnectHint extends StatelessWidget {
  final bool compact;
  const _ConnectHint({this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Align(
        alignment: Alignment.centerRight,
        child: Icon(
          Icons.bluetooth_disabled_rounded,
          size: 16,
          color: Colors.white.withValues(alpha: 0.2),
        ),
      );
    }
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          Icon(
            Icons.bluetooth_disabled_rounded,
            size: 11,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(width: 5),
          Text(
            'Connect Ring to Track',
            style: _inter(10, color: Colors.white.withValues(alpha: 0.3)),
          ),
        ],
      ),
    );
  }
}

// ── Edit Cards button ─────────────────────────────────────────────────────────

class _EditCardsButton extends StatelessWidget {
  final VoidCallback onTap;

  const _EditCardsButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _ShrinkButton(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              width: 85,
              height: 29,
              decoration: BoxDecoration(
                color: _kBtnBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  'Edit Cards',
                  style: _inter(
                    11,
                    weight: FontWeight.w500,
                    color: AppTheme.gold,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Painters ──────────────────────────────────────────────────────────────────

/// Resamples [src] into [count] points via linear interpolation.
List<double> _interpolate(List<double> src, int count) {
  if (src.length == count) return List.of(src);
  final out = <double>[];
  for (int i = 0; i < count; i++) {
    final t = i / (count - 1) * (src.length - 1);
    final lo = t.floor();
    final hi = (lo + 1).clamp(0, src.length - 1);
    final f = t - lo;
    out.add(src[lo] * (1 - f) + src[hi] * f);
  }
  return out;
}

String _formatInt(int v) => v.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]},',
);

/// Heart Rate area chart — faint 7% fill under a 0.7-white curve with an
/// end-point dot (Frame 478: Rectangle 1 + Line 15 + Ellipse 6).
class _AreaChartPainter extends CustomPainter {
  final List<double> data;
  const _AreaChartPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2 || size.width <= 0 || size.height <= 0) return;
    const pad = 6.0;
    final step = size.width / (data.length - 1);
    final ys = <double>[];
    final path = Path();
    for (int i = 0; i < data.length; i++) {
      final x = i * step;
      final y = pad + (1 - data[i]) * (size.height - pad * 2);
      ys.add(y);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        final px = (i - 1) * step;
        final py = ys[i - 1];
        final cpx = (px + x) / 2;
        path.cubicTo(cpx, py, cpx, y, x, y);
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()..color = Colors.white.withValues(alpha: 0.07),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(size.width, ys.last),
      2,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_AreaChartPainter old) => old.data != data;
}

/// Blood Pressure chart — systolic (0.7-white) and diastolic (0.35-white)
/// lines over a common 70–140 mmHg scale, with an end-point dot.
class _BpChartPainter extends CustomPainter {
  final int sbp;
  final int dbp;
  const _BpChartPainter({required this.sbp, required this.dbp});

  static const _sysPattern = [
    114.0,
    119.0,
    122.0,
    118.0,
    125.0,
    129.0,
    126.0,
    121.0,
    128.0,
    132.0,
    128.0,
    125.0,
    124.0,
  ];
  static const _diaPattern = [
    76.0,
    78.0,
    79.0,
    77.0,
    81.0,
    83.0,
    80.0,
    78.0,
    82.0,
    85.0,
    82.0,
    80.0,
    79.0,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final sysScale = sbp > 0 ? sbp / 128.0 : 1.0;
    final diaScale = dbp > 0 ? dbp / 82.0 : 1.0;
    Path line(List<double> pattern, double scale) {
      final p = Path();
      final step = size.width / (pattern.length - 1);
      for (int i = 0; i < pattern.length; i++) {
        final x = i * step;
        final v = pattern[i] * scale;
        final y = size.height * (1 - (v - 70) / 70);
        if (i == 0) {
          p.moveTo(x, y);
        } else {
          final px = (i - 1) * step;
          final py = size.height * (1 - (pattern[i - 1] * scale - 70) / 70);
          final cpx = (px + x) / 2;
          p.cubicTo(cpx, py, cpx, y, x, y);
        }
      }
      return p;
    }

    final sys = line(_sysPattern, sysScale);
    final dia = line(_diaPattern, diaScale);
    canvas.drawPath(
      dia,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      sys,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    final last = size.height * (1 - (_sysPattern.last * sysScale - 70) / 70);
    canvas.drawCircle(
      Offset(size.width, last),
      2,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_BpChartPainter old) => old.sbp != sbp || old.dbp != dbp;
}

/// Stress mini-bar chart — 6px bars, 2px gap, rounded 2px: low = soft green,
/// mid = 80% white, high = soft rose (Frame 481 colours).
class _StressMiniBarsPainter extends CustomPainter {
  final List<double> data;
  const _StressMiniBarsPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || size.width <= 0 || size.height <= 0) return;
    const barW = 6.0;
    final maxH = size.height * 0.67;
    final pitch = size.width / data.length;
    for (int i = 0; i < data.length; i++) {
      final x = i * pitch + (pitch - barW) / 2;
      final h = (data[i] * maxH).clamp(2.0, maxH);
      final y = size.height - h;
      final Color barColor;
      if (data[i] < 0.4) {
        barColor = _kFigmaStressLow;
      } else if (data[i] < 0.65) {
        barColor = Colors.white.withValues(alpha: 0.8);
      } else {
        barColor = _kFigmaStressHigh;
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barW, h),
          const Radius.circular(2),
        ),
        Paint()..color = barColor,
      );
    }
  }

  @override
  bool shouldRepaint(_StressMiniBarsPainter old) => old.data != data;
}

class _SparkPainter extends CustomPainter {
  final Color color;
  final List<double> data;
  const _SparkPainter(this.color, this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final step = size.width / (data.length - 1);
    final path = Path();

    for (int i = 0; i < data.length; i++) {
      final x = i * step;
      final y = size.height - data[i] * size.height * 0.9;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        final px = (i - 1) * step;
        final py = size.height - data[i - 1] * size.height * 0.9;
        final cpx = (px + x) / 2;
        path.cubicTo(cpx, py, cpx, y, x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.7)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.color != color || old.data != data;
}

class _BarChartPainter extends CustomPainter {
  final Color color;
  final List<double> data;
  const _BarChartPainter(this.color, this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final slotW = size.width / data.length;
    final barW = slotW * 0.55; // thinner bars, more breathing room between them
    final xOffset = (slotW - barW) / 2;

    for (int i = 0; i < data.length; i++) {
      final x = i * slotW + xOffset;
      final h = data[i] * size.height;
      final y = size.height - h;

      // Color ramp: low = green orb, mid = yellow, high = red
      final Color barColor;
      if (data[i] < 0.4) {
        barColor = _kOrbStress;
      } else if (data[i] < 0.65) {
        barColor = const Color(0xFFFBBF24);
      } else {
        barColor = _kOrbHr;
      }

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barW, h),
          Radius.circular((barW / 2).clamp(0, 4)),
        ),
        Paint()..color = barColor.withValues(alpha: 0.75),
      );
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.color != color || old.data != data;
}
