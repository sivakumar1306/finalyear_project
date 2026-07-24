import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../providers/alarm_mode_provider.dart';
import '../../services/supabase_service.dart';
import '../../services/home_card_prefs.dart';
import '../../theme/app_theme.dart';
import '../settings/fall_detection_screen.dart';
import '../settings/card_settings_screen.dart';
import 'ring_scan_sheet.dart';
import 'side_panel.dart';
import '../settings/about_screen.dart';
import 'package:share_plus/share_plus.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────

const _kSec2 = Color(0xFF888888);
const _kCardBg = Color(0x0FFFFFFF); // rgba(255,255,255,0.06)
const _kCardBorder = Color(0x17FFFFFF); // rgba(255,255,255,0.09)
const _kBtnBg = Color(0x08FFFFFF); // rgba(255,255,255,0.03)
const _kBtnBorder = Color(0x14FFFFFF); // rgba(255,255,255,0.08)

// DESIGN.md per-metric orb colors (soft, desaturated)
const _kOrbHr = Color(0xFFC96B6B);
const _kOrbSleep = Color(0xFF6B82D9);
const _kOrbStress = Color(0xFF6BC99B);
const _kOrbSpo2 = Color(0xFF73D4F8);
const _kOrbBp = Color(0xFFD97A7A);
const _kOrbWomen = Color(0xFFD88CC8);
const _kOrbActivity = Color(0xFFE08A4A);
const _kOrbHrv = Color(0xFFC9A86E);

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
  alarmActivity,
  stress,
  womensHealth,
  sleepHrv,
  bloodOxygenHeartRate,
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
  bool _editMode = false;
  Set<HomeCardId> _hiddenCards = {};
  List<HomeCardId> _cardOrder = [
    HomeCardId.alarmActivity,
    HomeCardId.stress,
    HomeCardId.womensHealth,
    HomeCardId.sleepHrv,
    HomeCardId.bloodOxygenHeartRate,
    HomeCardId.bloodPressure,
    HomeCardId.temperature,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BleProvider>().checkConnection();
      // Cold start via the fall-prediction notification tap — MainActivity sets a flag
      // BlePlugin.consumeFallPredictionFlag reads/clears once.
      context.read<BleProvider>().checkPendingFallPrediction();
    });
    _loadUserProfile();
    _loadCardOrder();
    _loadHiddenCards();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App was already running/backgrounded when the notification action was tapped —
    // onCreate won't fire again, only onNewIntent, so re-check on resume too.
    if (state == AppLifecycleState.resumed) {
      context.read<BleProvider>().checkPendingFallPrediction();
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
            _verifyWomensHealthCardVisibility();
          });
          if (kDebugMode) {
            debugPrint('DEBUG profile: $profile, parsed _gender: $_gender');
          }
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Error loading user profile: $e\n$stackTrace');
    }
  }

  Future<void> _loadCardOrder() async {
    try {
      final order = await HomeCardPrefs.loadOrder();
      setState(() => _cardOrder = order);
    } catch (_) {}
    _verifyWomensHealthCardVisibility();
  }

  Future<void> _saveCardOrder() async {
    await HomeCardPrefs.saveOrder(_cardOrder);
  }

  Future<void> _loadHiddenCards() async {
    try {
      final hidden = await HomeCardPrefs.loadHidden();
      if (mounted) setState(() => _hiddenCards = hidden);
    } catch (_) {}
  }

  void _verifyWomensHealthCardVisibility() {
    if (_isFemale) {
      if (!_cardOrder.contains(HomeCardId.womensHealth)) {
        setState(() {
          if (_cardOrder.length >= 2) {
            _cardOrder.insert(2, HomeCardId.womensHealth);
          } else {
            _cardOrder.add(HomeCardId.womensHealth);
          }
        });
      }
    }
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

  Widget _buildCardBlock(HomeCardId id, BleProvider ble) {
    switch (id) {
      case HomeCardId.alarmActivity:
        return Row(
          children: [
            const Expanded(child: _AlarmCard()),
            const SizedBox(width: 12),
            Expanded(
              child: _ActivityScoreCard(
                score: _computeActivityScore(
                  ble.todaySteps,
                  ble.todayDistanceM,
                  ble.todayCalories,
                ),
                hasData: ble.todaySteps > 0,
                onTap: _editMode
                    ? null
                    : () => Navigator.pushNamed(context, '/steps'),
              ),
            ),
          ],
        );
      case HomeCardId.stress:
        return _StressCard(
          value: ble.latestStressValue,
          avgStress: ble.todayAvgStress,
          minStress: ble.todayMinStress,
          maxStress: ble.todayMaxStress,
          connected: ble.isConnected,
          onTap: _editMode
              ? null
              : () => Navigator.pushNamed(context, '/pressure'),
        );
      case HomeCardId.womensHealth:
        return Row(
          children: [
            Expanded(
              child: _CompactWomensHealthCard(
                onTap: _editMode
                    ? null
                    : () => Navigator.pushNamed(context, '/womens-health'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CompactBloodPressureCard(
                onTap: _editMode
                    ? null
                    : () => Navigator.pushNamed(context, '/blood-pressure'),
              ),
            ),
          ],
        );
      case HomeCardId.sleepHrv:
        return Row(
          children: [
            Expanded(
              child: _HomeCard(
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
                onTap: _editMode
                    ? null
                    : () => Navigator.pushNamed(context, '/sleep'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _HomeCard(
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
                onTap: _editMode
                    ? null
                    : () => Navigator.pushNamed(context, '/hrv'),
              ),
            ),
          ],
        );
      case HomeCardId.bloodOxygenHeartRate:
        return Row(
          children: [
            Expanded(
              child: _HomeCard(
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
                onTap: _editMode
                    ? null
                    : () => Navigator.pushNamed(context, '/blood-oxygen'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _HomeCard(
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
                onTap: _editMode
                    ? null
                    : () => Navigator.pushNamed(context, '/heart-rate'),
              ),
            ),
          ],
        );
      case HomeCardId.bloodPressure:
        return _HomeCard(
          label: 'Blood Pressure',
          value: ble.latestBpSbp > 0
              ? '${ble.latestBpSbp}/${ble.latestBpDbp}'
              : '--/--',
          unit: ble.latestBpSbp > 0 ? 'mmHg' : '',
          status: ble.latestBpSbp > 0 ? 'Normal' : 'No data',
          statusColor: ble.latestBpSbp > 0 ? _kOrbBp : _kSec2,
          orbColor: _kOrbBp,
          sparkData: const [
            0.6,
            0.65,
            0.6,
            0.68,
            0.65,
            0.6,
            0.64,
            0.67,
            0.64,
            0.6,
            0.65,
            0.62,
          ],
          connected: ble.isConnected,
          onTap: _editMode
              ? null
              : () => Navigator.pushNamed(context, '/blood-pressure'),
        );
      case HomeCardId.temperature:
        return Row(
          children: [
            Expanded(
              child: _TemperatureCard(
                tempC: ble.latestTempC,
                connected: ble.isConnected,
                onTap: _editMode
                    ? null
                    : () => Navigator.pushNamed(context, '/temperature'),
              ),
            ),
          ],
        );
    }
  }

  Widget _buildReorderableList(
    BuildContext context,
    BleProvider ble,
    List<HomeCardId> visibleCardIds,
  ) {
    if (_editMode) {
      return SliverReorderableList(
        itemCount: visibleCardIds.length,
        onReorderItem: (int oldIndex, int newIndex) {
          setState(() {
            final HomeCardId item = visibleCardIds.removeAt(oldIndex);
            visibleCardIds.insert(newIndex, item);

            // Align the full preferences list _cardOrder with the new order of visible components
            int visibleIdx = 0;
            for (int i = 0; i < _cardOrder.length; i++) {
              if (visibleCardIds.contains(_cardOrder[i])) {
                _cardOrder[i] = visibleCardIds[visibleIdx++];
              }
            }
          });
        },
        proxyDecorator: (Widget child, int index, Animation<double> animation) {
          return AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final double animValue = Curves.easeInOut.transform(
                animation.value,
              );
              final double scale = lerpDouble(1.0, 1.03, animValue)!;
              return Transform.scale(
                scale: scale,
                child: Material(
                  color: Colors.transparent,
                  elevation: lerpDouble(0, 6, animValue)!,
                  child: child,
                ),
              );
            },
            child: child,
          );
        },
        itemBuilder: (context, index) {
          final id = visibleCardIds[index];
          return Padding(
            key: ValueKey(id),
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(child: IgnorePointer(child: _buildCardBlock(id, ble))),
                const SizedBox(width: 12),
                ReorderableDragStartListener(
                  index: index,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: const Icon(
                      Icons.drag_indicator_rounded,
                      color: Colors.white38,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    } else {
      return SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final id = visibleCardIds[index];
          return Padding(
            key: ValueKey(id),
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildCardBlock(id, ble),
          );
        }, childCount: visibleCardIds.length),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    if (ble.deviceAddress.isEmpty) {
      return _buildUnboundState(context, ble);
    }
    final visibleCardIds = _cardOrder.where((id) {
      if (id == HomeCardId.womensHealth && !_isFemale) return false;
      if (_hiddenCards.contains(id)) return false;
      return true;
    }).toList();

    return RefreshIndicator(
      color: AppTheme.gold,
      backgroundColor: const Color(0xFF111111),
      onRefresh: _editMode
          ? () async {}
          : () async {
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
                if (ble.showFallPredictionBanner) ...[
                  _FallPredictionBanner(
                    hr: ble.fallPredictionHr,
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

          // 2. Reorderable / Sequenced list of metrics
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: _buildReorderableList(context, ble, visibleCardIds),
          ),

          // 3. Edit Button & spacing at bottom
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 8),
                _EditCardsButton(
                  editMode: _editMode,
                  onTap: () {
                    setState(() {
                      _editMode = !_editMode;
                    });
                    if (!_editMode) {
                      _saveCardOrder();
                    }
                  },
                ),
                const SizedBox(height: 100),
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
          IconButton(
            icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 22),
            onPressed: () => showSidePanel(
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
                        label: 'Goal setting',
                        onTap: () async {
                          Navigator.pop(context);
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CardSettingsScreen(),
                            ),
                          );
                          _loadCardOrder();
                          _loadHiddenCards();
                        },
                      ),
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
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text('Home', style: _inter(16, weight: FontWeight.w600)),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.more_vert_rounded,
              color: Colors.white,
              size: 22,
            ),
            onPressed: () => showSidePanel(
              context: context,
              fromRight: true,
              child: SidePanelShell(
                fromRight: true,
                icon: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(
                    Icons.more_vert_rounded,
                    color: Colors.white70,
                    size: 22,
                  ),
                ),
                items: [
                  SidePanelGroup(
                    items: [
                      SidePanelItem(
                        label: 'Share',
                        onTap: () {
                          Navigator.pop(context);
                          Share.share(
                            'Check out SUNDR — the AI health ring app I use to track my sleep, heart rate, and more.',
                          );
                        },
                      ),
                      SidePanelItem(
                        label: 'Pair ring',
                        onTap: () {
                          Navigator.pop(context);
                          showRingScanSheet(context);
                        },
                      ),
                    ],
                  ),
                ],
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

  Widget _buildUnboundState(BuildContext context, BleProvider ble) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [_buildTopBar(context), _buildGreetingRow(ble)],
            ),
          ),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.gold.withValues(alpha: 0.08),
                        blurRadius: 40,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: Image.asset('ring.png', fit: BoxFit.contain),
                ),
                const SizedBox(height: 32),
                Text(
                  "You haven't bound a device yet",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.5),
                        height: 1.5,
                      ),
                      children: [
                        const TextSpan(
                          text:
                              'Welcome to SUNDR rings — bought a ring already? Connect your ring. Haven\'t bought one yet? ',
                        ),
                        TextSpan(
                          text: 'Browse our collection.',
                          style: const TextStyle(
                            color: AppTheme.gold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => showRingScanSheet(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.gold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Pair Ring',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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

// ── Fall prediction banner ────────────────────────────────────────────────────
// Mirrors the hero-card alert styling already established on the Fall Detection
// screen (gradient + accent border, not the ambient-orb metric-card look) so the
// same alert appears consistent whether it's seen here or after drilling in.

class _FallPredictionBanner extends StatelessWidget {
  final int hr;
  final VoidCallback onTakeAction;
  final VoidCallback onIgnore;

  const _FallPredictionBanner({
    required this.hr,
    required this.onTakeAction,
    required this.onIgnore,
  });

  @override
  Widget build(BuildContext context) {
    const accent = AppTheme.tempColor;
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
                  'FALL PREDICTION',
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
            Text(
              'We are concerned ...',
              style: _inter(20, weight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              'Your heart rate rose to $hr BPM while you seemed to be in-active for the last 10 minutes.',
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
                    'ignore',
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
    return GestureDetector(
      onTapDown: (_) {
        if (widget.onTap != null) _ctrl.forward();
      },
      onTapUp: (_) {
        if (widget.onTap != null) {
          _ctrl.reverse();
          widget.onTap!();
        }
      },
      onTapCancel: () {
        if (widget.onTap != null) _ctrl.reverse();
      },
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
  });

  @override
  Widget build(BuildContext context) {
    // Small fixed-height cards get a large orb so the ambient glow covers
    // ~90% of the card; full-width auto-height cards keep a corner glow.
    final double resolvedOrbOffset = orbOffset ?? (height == null ? -78 : -56);

    return _ShrinkButton(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: _kCardBg,
          border: Border.all(color: _kCardBorder, width: 0.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(19.5),
          child: Stack(
            children: [
              // Ambient orb — blurred circle clipped by card
              Positioned(
                top: orbAtTop ? resolvedOrbOffset : null,
                bottom: orbAtTop ? null : resolvedOrbOffset,
                right: orbOnRight ? resolvedOrbOffset : null,
                left: orbOnRight ? null : resolvedOrbOffset,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeInOut,
                    width: orbSize,
                    height: orbSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: orbColor.withValues(alpha: orbAlpha),
                    ),
                  ),
                ),
              ),
              // Fixed height: Positioned.fill gives Column tight constraints so Spacer works.
              // Variable height: plain Padding lets Stack size to the child content.
              if (height != null)
                Positioned.fill(
                  child: Padding(
                    padding: padding ?? const EdgeInsets.all(16),
                    child: child,
                  ),
                )
              else
                Padding(
                  padding: padding ?? const EdgeInsets.all(16),
                  child: child,
                ),
            ],
          ),
        ),
      ),
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
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      orbColor: orbColor,
      height: 160,
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
  final bool connected;
  final VoidCallback? onTap;

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

  const _StressCard({
    required this.value,
    required this.avgStress,
    required this.minStress,
    required this.maxStress,
    required this.connected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final status = _stressStatus(value);
    final color = _stressColor(value);

    return _GlassCard(
      orbColor: _kOrbStress,
      orbOnRight: false,
      orbOffset: -78,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Stress',
                style: _inter(
                  15,
                  weight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              _chevron(),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value > 0 ? '$value' : '--',
                style: GoogleFonts.inter(
                  fontSize: 36,
                  fontWeight: FontWeight.w300,
                  color: Colors.white.withValues(alpha: 0.95),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                status,
                style: _inter(13, color: color, weight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 36,
            width: double.infinity,
            child: connected
                ? CustomPaint(painter: _BarChartPainter(_kOrbStress, _barData))
                : const _ConnectHint(),
          ),
          const SizedBox(height: 16),

          // Horizontal Divider added here
          Container(
            height: 1,
            width: double.infinity,
            color: Colors.white.withValues(alpha: 0.08),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center, // Centered
                  children: [
                    Text(
                      'Daily Average',
                      style: _inter(
                        11,
                        color: Colors.white.withValues(alpha: 0.4),
                        weight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      avgStress > 0 ? '$avgStress' : '--',
                      style: GoogleFonts.inter(
                        fontSize: 22, // Increased size to match design
                        fontWeight: FontWeight.w300, // Thinner font weight
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _stressStatus(avgStress),
                      style: _inter(
                        11,
                        color: Colors.white.withValues(
                          alpha: 0.5,
                        ), // Muted grey instead of active color
                        weight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center, // Centered
                  children: [
                    Text(
                      'Daily Range',
                      style: _inter(
                        11,
                        color: Colors.white.withValues(alpha: 0.4),
                        weight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      maxStress > 0 ? '$minStress-$maxStress' : '--',
                      style: GoogleFonts.inter(
                        fontSize: 22, // Increased size to match design
                        fontWeight: FontWeight.w300, // Thinner font weight
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _stressStatus(maxStress),
                      style: _inter(
                        11,
                        color: Colors.white.withValues(
                          alpha: 0.5,
                        ), // Muted grey instead of active color
                        weight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
// ── Activity score card ────────────────────────────────────────────────────────

class _ActivityScoreCard extends StatelessWidget {
  final int score;
  final bool hasData;
  final VoidCallback? onTap;

  const _ActivityScoreCard({
    required this.score,
    required this.hasData,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      orbColor: _kOrbActivity,
      orbOnRight: true,
      orbAlpha: 0.25,
      height: 165,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Activity',
                style: _inter(
                  15,
                  weight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              _chevron(),
            ],
          ),
          const SizedBox(height: 12),
          Divider(
            color: Colors.white.withValues(alpha: 0.08),
            height: 1,
            thickness: 0.5,
          ),
          const Spacer(),
          Text(
            hasData ? '$score' : '--',
            style: GoogleFonts.inter(
              fontSize: 40,
              fontWeight: FontWeight.w300,
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _HomeScreenState._activityScoreLabel(score),
            style: _inter(13, weight: FontWeight.w500, color: _kOrbActivity),
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
  const _AlarmCard();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AlarmModeProvider>();
    final mode = provider.mode;
    final info = _kAlarmModeInfo[mode]!;
    return _GlassCard(
      orbColor: info.color,
      height: 165, // Updated height to exactly 165px
      orbAtTop: true,
      orbSize: 260,
      orbOffset: -80,
      orbAlpha: 0.4,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tapping this region (everything except the mode buttons below)
          // opens the system Alarms & notifications settings screen.
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  Navigator.pushNamed(context, '/alarms-notifications'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'ALARMS',
                        style: _inter(
                          11,
                          weight: FontWeight.w700,
                          color: info
                              .color, // Matched to screenshot (colors dynamically change per mode)
                          letterSpacing: 1.2,
                        ),
                      ),
                      _chevron(),
                    ],
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
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
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _AlarmModeSelector(
            mode: mode,
            onChanged: (m) => requestPhoneMode(context, provider, m),
          ),
        ],
      ),
    );
  }
}

// Rounded, glass-background container holding all three modes — Focus, Base,
// Prayer — always visible with their icon and label; the active mode is
// highlighted with its accent color.
class _AlarmModeSelector extends StatelessWidget {
  final PhoneMode mode;
  final ValueChanged<PhoneMode> onChanged;
  const _AlarmModeSelector({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity, // Responsive width
      height: 46, // Specified height
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _kBtnBg,
        borderRadius: BorderRadius.circular(
          23,
        ), // Fully rounded ends matching the visual pill shape
        border: Border.all(color: _kBtnBorder, width: 0.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: PhoneMode.values.map((m) {
          return Expanded(
            child: _AlarmSegment(
              mode: m,
              selected: m == mode,
              onTap: () => onChanged(m),
            ),
          );
        }).toList(),
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
    final color = selected ? info.color : Colors.white.withValues(alpha: 0.45);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        height: 40, // Removed fixed width to allow expansion within Expanded
        decoration: BoxDecoration(
          color: info.color.withValues(alpha: selected ? 0.16 : 0),
          borderRadius: BorderRadius.circular(
            20,
          ), // Highly rounded individual selected states
          border: Border.all(
            color: info.color.withValues(alpha: selected ? 0.5 : 0),
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment:
              MainAxisAlignment.center, // Vertically center icon and text
          children: [
            Icon(info.icon, size: 14, color: color), // Specified icon size
            const SizedBox(height: 2), // Small gap between icon and text
            Text(
              info.segmentLabel,
              style: _inter(
                10,
                weight: FontWeight.w500,
                color: color,
              ), // Specified text size
            ),
          ],
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

  const _CompactHealthCard({
    required this.title,
    required this.orbColor,
    required this.child,
    this.orbOnRight = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _ShrinkButton(
      onTap: onTap,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color.fromRGBO(245, 240, 226, 0.06),
          border: Border.all(
            color: const Color.fromRGBO(245, 240, 226, 0.09),
            width: 0.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17.5),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Stack(
              children: [
                // Orb
                Positioned(
                  top: -40,
                  left: orbOnRight ? null : -40,
                  right: orbOnRight ? -40 : null,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 35, sigmaY: 35),
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: orbColor.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Row
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
                      // Divider
                      Container(
                        height: 0.5,
                        width: double.infinity,
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                      const SizedBox(height: 8),
                      // Main content filling remaining space
                      Expanded(child: child),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactWomensHealthCard extends StatefulWidget {
  final VoidCallback? onTap;
  const _CompactWomensHealthCard({this.onTap});

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
    return _CompactHealthCard(
      title: 'Women\'s Health',
      orbColor: const Color.fromRGBO(216, 96, 200, 0.32),
      orbOnRight: true,
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
  const _CompactBloodPressureCard({this.onTap});

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

    return _CompactHealthCard(
      title: 'Blood Pressure',
      orbColor: const Color.fromRGBO(216, 101, 96, 0.32),
      orbOnRight: true,
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
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
                    style: _inter(
                      11,
                      color: Colors.white.withValues(alpha: 0.5),
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
  final bool editMode;
  final VoidCallback onTap;

  const _EditCardsButton({required this.editMode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _ShrinkButton(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: _kBtnBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _kBtnBorder, width: 0.5),
            ),
            child: Center(
              child: Text(
                editMode ? 'Done' : 'Edit Cards',
                style: _inter(
                  14,
                  weight: FontWeight.w500,
                  color: editMode
                      ? AppTheme.gold
                      : Colors.white.withValues(alpha: 0.5),
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
    final barW = (size.width / data.length) - 2;

    for (int i = 0; i < data.length; i++) {
      final x = i * (barW + 2);
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
          const Radius.circular(2),
        ),
        Paint()..color = barColor.withValues(alpha: 0.75),
      );
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.color != color || old.data != data;
}

// ── Cycle bar painter ─────────────────────────────────────────────────────────

class _CycleBarPainter extends CustomPainter {
  final int currentDay;
  final int cycleLength;
  final int periodLength;

  const _CycleBarPainter({
    required this.currentDay,
    required this.cycleLength,
    required this.periodLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const barH = 4.0;
    const radius = Radius.circular(2);
    final barY = size.height - barH - 6;

    canvas.drawRRect(
      RRect.fromLTRBR(0, barY, size.width, barY + barH, radius),
      Paint()..color = Colors.white.withValues(alpha: 0.08),
    );

    final double dayW = size.width / cycleLength;

    canvas.drawRRect(
      RRect.fromLTRBR(0, barY, dayW * periodLength, barY + barH, radius),
      Paint()..color = _kOrbWomen.withValues(alpha: 0.8),
    );

    final double ovStart = dayW * 12;
    final double ovEnd = dayW * 16;
    canvas.drawRect(
      Rect.fromLTRB(ovStart, barY, ovEnd, barY + barH),
      Paint()..color = _kOrbWomen.withValues(alpha: 0.8),
    );

    final double markerX = dayW * (currentDay - 0.5);
    canvas.drawPath(
      Path()
        ..moveTo(markerX - 4, 0)
        ..lineTo(markerX + 4, 0)
        ..lineTo(markerX, 6)
        ..close(),
      Paint()..color = _kOrbWomen,
    );
  }

  @override
  bool shouldRepaint(_CycleBarPainter old) =>
      old.currentDay != currentDay ||
      old.cycleLength != cycleLength ||
      old.periodLength != periodLength;
}

// ── Temperature Card (Task 1 Design Spec) ───────────────────────────────────

class _TemperatureCard extends StatelessWidget {
  final double tempC;
  final bool connected;
  final VoidCallback? onTap;

  const _TemperatureCard({
    required this.tempC,
    required this.connected,
    this.onTap,
  });

  static String _tempStatus(double v) {
    if (v <= 0) return 'No Data';
    if (v < 36.0) return 'Low';
    if (v <= 37.2) return 'Normal';
    if (v <= 38.0) return 'Elevated';
    return 'Fever';
  }

  @override
  Widget build(BuildContext context) {
    final hasData = tempC > 0;
    final statusText = _tempStatus(tempC);

    return _ShrinkButton(
      onTap: onTap,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color.fromRGBO(245, 240, 226, 0.06),
          border: Border.all(
            color: const Color.fromRGBO(245, 240, 226, 0.09),
            width: 0.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17.5),
          child: Stack(
            children: [
              // Circular glow at top-right (180x180, right: -40, top: -40, rgba(201,168,110,0.15), blur: 35px)
              Positioned(
                right: -40,
                top: -40,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 35, sigmaY: 35),
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color.fromRGBO(201, 168, 110, 0.15),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Temperature',
                            style: _inter(
                              14,
                              weight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                          _chevron(),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Divider(
                        color: Colors.white.withValues(alpha: 0.08),
                        height: 1,
                        thickness: 0.5,
                      ),
                      const Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                hasData ? tempC.toStringAsFixed(1) : '--',
                                style: GoogleFonts.inter(
                                  fontSize: 44,
                                  fontWeight: FontWeight.w200,
                                  color: Colors.white.withValues(alpha: 0.95),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '°C',
                            style: _inter(
                              14,
                              weight: FontWeight.w300,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        statusText,
                        style: _inter(
                          12,
                          weight: FontWeight.w500,
                          color: const Color(0xFFC9A86E),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
