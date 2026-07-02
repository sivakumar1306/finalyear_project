import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../providers/workout_provider.dart';
import '../../providers/alarm_mode_provider.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import 'ring_scan_sheet.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────

const _kSec2       = Color(0xFF888888);
const _kCardBg     = Color(0x0FFFFFFF);   // rgba(255,255,255,0.06)
const _kCardBorder = Color(0x17FFFFFF);   // rgba(255,255,255,0.09)
const _kBtnBg      = Color(0x08FFFFFF);   // rgba(255,255,255,0.03)
const _kBtnBorder  = Color(0x14FFFFFF);   // rgba(255,255,255,0.08)

// DESIGN.md per-metric orb colors (soft, desaturated)
const _kOrbHr       = Color(0xFFC96B6B);
const _kOrbSleep    = Color(0xFF6B82D9);
const _kOrbStress   = Color(0xFF6BC99B);
const _kOrbHrv      = Color(0xFFC9A86E);
const _kOrbSpo2     = Color(0xFF73D4F8);
const _kOrbBp       = Color(0xFFD97A7A);
const _kOrbTemp     = Color(0xFFE3B76A);
const _kOrbWomen    = Color(0xFFD88CC8);
const _kOrbActivity = Color(0xFFC9A86E);
const _kOrbSport    = Color(0xFFD97706);

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
  if (v < 36.0) return 'Low';
  if (v <= 37.2) return 'Normal';
  if (v <= 38.0) return 'Elevated';
  return 'Fever';
}

Color _tempStatusColor(double v) {
  if (v < 36.0) return AppTheme.spo2Color;
  if (v <= 37.2) return AppTheme.success;
  if (v <= 38.0) return const Color(0xFFFBBF24);
  return AppTheme.danger;
}

TextStyle _inter(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = Colors.white,
  double? letterSpacing,
  double? height,
}) =>
    GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );

// ── Screen ────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _firstName = '';
  String _gender    = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BleProvider>().checkConnection();
    });
    _loadUserProfile();
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
            _gender    = profile['gender'] as String? ?? '';
          });
        }
      }
    } catch (_) {}
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
    const d = ['MON','TUE','WED','THU','FRI','SAT','SUN'];
    const m = ['JAN','FEB','MAR','APR','MAY','JUN',
                'JUL','AUG','SEP','OCT','NOV','DEC'];
    return '${d[now.weekday - 1]} · ${now.day.toString().padLeft(2,'0')} ${m[now.month - 1]}';
  }

  static String _hrvStatus(int v) {
    if (v <= 0) return 'No data';
    if (v < 20) return 'Very Low';
    if (v < 40) return 'Low';
    if (v < 60) return 'Normal';
    if (v < 80) return 'Good';
    return 'Excellent';
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

  static String _sleepDurationLabel(int seconds) {
    if (seconds <= 0) return '--';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  static String _workoutDurationLabel(int seconds) {
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ble     = context.watch<BleProvider>();
    final workout = context.watch<WorkoutProvider>();

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
                  _buildSectionLabel(),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([

                // ── Alarms + Heart Rate ────────────────────────────────────
                Row(children: [
                  const Expanded(child: _AlarmCard()),
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
                      sparkData: const [0.45, 0.5, 0.55, 0.5, 0.6, 0.55, 0.5, 0.48, 0.52, 0.58, 0.54, 0.5],
                      connected: ble.isConnected,
                      onTap: () => Navigator.pushNamed(context, '/heart-rate'),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),

                // ── Activity ─────────────────────────────────────────────
                _ActivityCard(
                  steps: ble.todaySteps,
                  distanceM: ble.todayDistanceM,
                  calories: ble.todayCalories,
                  connected: ble.isConnected,
                  onTap: () => Navigator.pushNamed(context, '/steps'),
                ),
                const SizedBox(height: 12),

                // ── Stress (full-width) ───────────────────────────────────
                _StressCard(
                  value: ble.latestStressValue,
                  connected: ble.isConnected,
                  onTap: () => Navigator.pushNamed(context, '/pressure'),
                ),
                const SizedBox(height: 12),

                // ── Women's Health (full-width, female only) ──────────────
                if (_gender.toLowerCase() == 'female') ...[
                  _WomensHealthCard(
                    onTap: () => Navigator.pushNamed(context, '/womens-health'),
                  ),
                  const SizedBox(height: 12),
                ],

                // ── Sleep + HRV ───────────────────────────────────────────
                Row(children: [
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
                      sparkData: const [0.5, 0.7, 0.9, 0.8, 0.6, 0.4, 0.3, 0.5, 0.7, 0.8, 0.6, 0.4],
                      connected: ble.isConnected,
                      onTap: () => Navigator.pushNamed(context, '/sleep'),
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
                      sparkData: const [0.5, 0.6, 0.45, 0.7, 0.55, 0.8, 0.6, 0.5, 0.45, 0.65, 0.7, 0.55],
                      connected: ble.isConnected,
                      onTap: () => Navigator.pushNamed(context, '/hrv'),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),

                // ── Blood Oxygen + Sport ───────────────────────────────────
                Row(children: [
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
                      sparkData: const [0.96, 0.97, 0.96, 0.98, 0.97, 0.99, 0.98, 0.97, 0.96, 0.98, 0.97, 0.99],
                      connected: ble.isConnected,
                      onTap: () => Navigator.pushNamed(context, '/blood-oxygen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _HomeCard(
                      label: 'Sport',
                      value: _workoutDurationLabel(workout.todayWorkoutDurationS),
                      unit: workout.todayWorkoutDurationS > 0 ? 'today' : '',
                      status: workout.todayWorkoutDurationS > 0 ? 'Active today' : 'No activity',
                      statusColor: workout.todayWorkoutDurationS > 0 ? _kOrbSport : _kSec2,
                      orbColor: _kOrbSport,
                      sparkData: const [0.2, 0.3, 0.5, 0.4, 0.6, 0.7, 0.5, 0.3, 0.2, 0.4, 0.5, 0.3],
                      connected: ble.isConnected,
                      onTap: () => Navigator.pushNamed(context, '/workouts'),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),

                // ── Temperature + Blood Pressure ──────────────────────────
                Row(children: [
                  Expanded(
                    child: _HomeCard(
                      label: 'Temperature',
                      value: ble.latestTempC > 0
                          ? ble.latestTempC.toStringAsFixed(1)
                          : '--',
                      unit: ble.latestTempC > 0 ? '°C' : '',
                      status: ble.latestTempC > 0
                          ? _tempStatus(ble.latestTempC)
                          : 'No data',
                      statusColor: ble.latestTempC > 0
                          ? _tempStatusColor(ble.latestTempC)
                          : _kSec2,
                      orbColor: _kOrbTemp,
                      sparkData: const [0.5, 0.52, 0.51, 0.53, 0.52, 0.51, 0.5, 0.52, 0.53, 0.51, 0.5, 0.52],
                      connected: ble.isConnected,
                      onTap: () => Navigator.pushNamed(context, '/temperature'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _HomeCard(
                      label: 'Blood Pressure',
                      value: ble.latestBpSbp > 0
                          ? '${ble.latestBpSbp}/${ble.latestBpDbp}'
                          : '--/--',
                      unit: ble.latestBpSbp > 0 ? 'mmHg' : '',
                      status: ble.latestBpSbp > 0 ? 'Normal' : 'No data',
                      statusColor: ble.latestBpSbp > 0 ? _kOrbBp : _kSec2,
                      orbColor: _kOrbBp,
                      sparkData: const [0.6, 0.65, 0.6, 0.68, 0.65, 0.6, 0.64, 0.67, 0.64, 0.6, 0.65, 0.62],
                      connected: ble.isConnected,
                      onTap: () => Navigator.pushNamed(context, '/blood-pressure'),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),

                const _EditCardsButton(),
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
            onPressed: () {},
          ),
          Expanded(
            child: Center(
              child: Text('Home', style: _inter(16, weight: FontWeight.w600)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 22),
            onPressed: () {},
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
          _DevicePill(ble: ble),
        ],
      ),
    );
  }

  Widget _buildSectionLabel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(
        'ALL METRICS  ·  TODAY',
        style: _inter(11,
            weight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.38),
            letterSpacing: 1.5),
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
  late final Animation<double> _scale =
      Tween<double>(begin: 1.0, end: 0.96).animate(
          CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:   (_) { if (widget.onTap != null) _ctrl.forward(); },
      onTapUp:     (_) { if (widget.onTap != null) { _ctrl.reverse(); widget.onTap!(); } },
      onTapCancel: ()  { if (widget.onTap != null) _ctrl.reverse(); },
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
  final double? orbOffset;

  const _GlassCard({
    required this.orbColor,
    required this.child,
    this.height,
    this.onTap,
    this.orbOnRight = true,
    this.orbOffset,
  });

  @override
  Widget build(BuildContext context) {
    // Small fixed-height cards get a large orb so the ambient glow covers
    // ~90% of the card; full-width auto-height cards keep a corner glow.
    const double resolvedOrbSize   = 240;
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
                bottom: resolvedOrbOffset,
                right: orbOnRight ? resolvedOrbOffset : null,
                left:  orbOnRight ? null : resolvedOrbOffset,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeInOut,
                    width: resolvedOrbSize,
                    height: resolvedOrbSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: orbColor.withValues(alpha: 0.34),
                    ),
                  ),
                ),
              ),
              // Fixed height: Positioned.fill gives Column tight constraints so Spacer works.
              // Variable height: plain Padding lets Stack size to the child content.
              if (height != null)
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: child,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(16),
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
  width: 26, height: 26,
  decoration: BoxDecoration(
    shape: BoxShape.circle,
    color: Colors.white.withValues(alpha: 0.08),
    border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
  ),
  child: const Icon(Icons.chevron_right_rounded, color: Colors.white54, size: 16),
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
                  style: _inter(13,
                      weight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.85)),
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
                        style: _inter(11,
                            weight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.5)),
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
                      ? CustomPaint(
                          painter: _SparkPainter(orbColor, sparkData),
                        )
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
  final bool connected;
  final VoidCallback? onTap;

  static const _barData = [
    0.30, 0.45, 0.38, 0.52, 0.48, 0.42, 0.55, 0.38, 0.47, 0.35,
    0.60, 0.55, 0.48, 0.40, 0.35, 0.42, 0.50, 0.45, 0.38, 0.30,
    0.40, 0.35, 0.28, 0.32,
  ];

  const _StressCard({required this.value, required this.connected, this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = _stressStatus(value);
    final color  = _stressColor(value);

    return _GlassCard(
      orbColor: _kOrbStress,
      orbOnRight: false,
      height: 205,
      orbOffset: -78,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Stress',
                  style: _inter(13, weight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.85))),
              _chevron(),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value > 0 ? '$value' : '--',
                style: GoogleFonts.inter(
                    fontSize: 36,
                    fontWeight: FontWeight.w200,
                    color: Colors.white.withValues(alpha: 0.95)),
              ),
              const SizedBox(width: 8),
              Text(status, style: _inter(13, color: color, weight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            width: double.infinity,
            child: connected
                ? CustomPaint(painter: _BarChartPainter(_kOrbStress, _barData))
                : const _ConnectHint(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Daily Average',
                        style: _inter(10,
                            color: Colors.white.withValues(alpha: 0.4),
                            weight: FontWeight.w400)),
                    const SizedBox(height: 2),
                    Text(value > 0 ? '$value' : '--',
                        style: _inter(13,
                            weight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.85))),
                    Text(status,
                        style: _inter(10,
                            color: color, weight: FontWeight.w400)),
                  ],
                ),
              ),
              Container(width: 0.5, height: 36,
                  color: Colors.white.withValues(alpha: 0.08)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Daily Range',
                          style: _inter(10,
                              color: Colors.white.withValues(alpha: 0.4),
                              weight: FontWeight.w400)),
                      const SizedBox(height: 2),
                      Text(value > 0 ? '${(value * 0.8).round()}-$value' : '--',
                          style: _inter(13,
                              weight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.85))),
                      Text(status,
                          style: _inter(10,
                              color: color, weight: FontWeight.w400)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Activity card (full-width) ────────────────────────────────────────────────

class _ActivityCard extends StatelessWidget {
  final int steps;
  final double distanceM;
  final int calories;
  final bool connected;
  final VoidCallback? onTap;

  const _ActivityCard({
    required this.steps,
    required this.distanceM,
    required this.calories,
    required this.connected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasData = steps > 0;
    final km = distanceM / 1000;

    return _GlassCard(
      orbColor: _kOrbActivity,
      orbOnRight: true,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Activity',
                  style: _inter(13,
                      weight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.85))),
              _chevron(),
            ],
          ),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _ActivityStat(
                    value: hasData ? '$steps' : '--',
                    unit: 'steps',
                    color: _kOrbActivity,
                  ),
                ),
                VerticalDivider(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1, thickness: 0.5),
                Expanded(
                  child: _ActivityStat(
                    value: hasData ? km.toStringAsFixed(2) : '--',
                    unit: 'km',
                    color: AppTheme.success,
                  ),
                ),
                VerticalDivider(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1, thickness: 0.5),
                Expanded(
                  child: _ActivityStat(
                    value: hasData ? '$calories' : '--',
                    unit: 'kcal',
                    color: _kOrbSport,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 28,
            width: double.infinity,
            child: connected
                ? CustomPaint(
                    painter: _SparkPainter(
                      _kOrbActivity,
                      const [0.2, 0.4, 0.6, 0.5, 0.7, 0.8, 0.6, 0.5, 0.7, 0.9, 0.7, 0.5],
                    ),
                  )
                : const _ConnectHint(),
          ),
        ],
      ),
    );
  }
}

class _ActivityStat extends StatelessWidget {
  final String value;
  final String unit;
  final Color color;

  const _ActivityStat({
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w200,
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
          const SizedBox(height: 2),
          Text(unit, style: _inter(11, color: color, weight: FontWeight.w500)),
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
  const _AlarmModeInfo(this.title, this.subtitle, this.segmentLabel, this.color, this.icon);
}

const Map<PhoneMode, _AlarmModeInfo> _kAlarmModeInfo = {
  PhoneMode.focus: _AlarmModeInfo(
      'Focus', 'Until 13:00', 'Focus', AppTheme.gold, Icons.adjust_rounded),
  PhoneMode.base: _AlarmModeInfo(
      'Normal', 'All alerts on', 'Base', AppTheme.gold, Icons.circle_outlined),
  PhoneMode.prayer: _AlarmModeInfo(
      'Prayer mode', 'Dhuhr 13:14', 'Prayer', _kOrbStress, Icons.self_improvement_rounded),
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
                      Text('ALARMS',
                          style: _inter(11,
                              weight: FontWeight.w700,
                              color: info.color, // Matched to screenshot (colors dynamically change per mode)
                              letterSpacing: 1.2)),
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
                              color: info.color),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(info.subtitle,
                            style: _inter(13,
                                color: Colors.white.withValues(alpha: 0.6))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
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
      width: 152, // Specified width
      height: 46, // Specified height
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _kBtnBg,
        borderRadius: BorderRadius.circular(23), // Fully rounded ends matching the visual pill shape
        border: Border.all(color: _kBtnBorder, width: 0.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: PhoneMode.values.map((m) {
          return _AlarmSegment(
            mode: m,
            selected: m == mode,
            onTap: () => onChanged(m),
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

  const _AlarmSegment({required this.mode, required this.selected, required this.onTap});

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
        width: 46.66, // Specified width
        height: 40, // Specified height
        decoration: BoxDecoration(
          color: info.color.withValues(alpha: selected ? 0.16 : 0),
          borderRadius: BorderRadius.circular(20), // Highly rounded individual selected states
          border: Border.all(color: info.color.withValues(alpha: selected ? 0.5 : 0), width: 1),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center, // Vertically center icon and text
          children: [
            Icon(info.icon, size: 14, color: color), // Specified icon size
            const SizedBox(height: 2), // Small gap between icon and text
            Text(
              info.segmentLabel,
              style: _inter(10, weight: FontWeight.w500, color: color), // Specified text size
            ),
          ],
        ),
      ),
    );
  }
}
// ── Women's Health card ───────────────────────────────────────────────────────

class _WomensHealthCard extends StatefulWidget {
  final VoidCallback? onTap;
  const _WomensHealthCard({this.onTap});

  @override
  State<_WomensHealthCard> createState() => _WomensHealthCardState();
}

class _WomensHealthCardState extends State<_WomensHealthCard> {
  int _cycleDay    = 0;
  int _cycleLength = 28;
  int _periodLen   = 5;

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
      final periodStart  = DateTime.parse(row['period_start'] as String);
      final cycleLength  = (row['cycle_length'] as num? ?? 28).toInt();
      final periodLength = (row['period_length'] as num? ?? 5).toInt();
      final day = DateTime.now().difference(periodStart).inDays + 1;
      setState(() {
        _cycleDay    = day.clamp(1, cycleLength);
        _cycleLength = cycleLength;
        _periodLen   = periodLength;
      });
    } catch (_) {}
  }

  String get _phaseName {
    if (_cycleDay <= 0) return '---';
    if (_cycleDay <= _periodLen) return 'Menstruation';
    if (_cycleDay <= 13) return 'Follicular';
    if (_cycleDay <= 16) return 'Ovulating';
    return 'Luteal';
  }

  String get _footerText {
    if (_cycleDay <= 0) return 'No cycle data logged yet';
    final daysLeft = _cycleLength - _cycleDay;
    if (_cycleDay <= _periodLen) return 'Period · ${_periodLen - _cycleDay + 1} days left';
    if (_cycleDay <= 16) return 'Fertile window · $daysLeft days to next';
    return 'Next period in $daysLeft days';
  }

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      orbColor: _kOrbWomen,
      orbOnRight: true,
      onTap: widget.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.nightlight_round,
                      color: _kOrbWomen, size: 13),
                  const SizedBox(width: 5),
                  Text('CYCLE',
                      style: _inter(11,
                          weight: FontWeight.w700,
                          color: _kOrbWomen,
                          letterSpacing: 1.2)),
                ],
              ),
              _chevron(),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  _phaseName,
                  style: _inter(18,
                      weight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.95)),
                ),
              ),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Day ',
                      style: _inter(13,
                          color: Colors.white.withValues(alpha: 0.45)),
                    ),
                    TextSpan(
                      text: _cycleDay > 0 ? '$_cycleDay' : '--',
                      style: GoogleFonts.inter(
                        fontSize: 28,
                        fontWeight: FontWeight.w200,
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 24,
            width: double.infinity,
            child: _cycleDay > 0
                ? CustomPaint(
                    painter: _CycleBarPainter(
                      currentDay: _cycleDay,
                      cycleLength: _cycleLength,
                      periodLength: _periodLen,
                    ),
                  )
                : const SizedBox(),
          ),
          const SizedBox(height: 10),
          Text(
            _footerText,
            style: _inter(11, color: Colors.white.withValues(alpha: 0.4)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
    final connected    = ble.isConnected;
    final reconnecting = ble.isReconnecting;
    final battery      = ble.battery;

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
                    width: 7, height: 7,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: AppTheme.gold),
                  )
                else
                  Container(
                    width: 7, height: 7,
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
                  Text('$battery%',
                      style: _inter(11,
                          color: Colors.white.withValues(alpha: 0.5))),
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
        child: Icon(Icons.bluetooth_disabled_rounded,
            size: 16, color: Colors.white.withValues(alpha: 0.2)),
      );
    }
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          Icon(Icons.bluetooth_disabled_rounded,
              size: 11, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(width: 5),
          Text('Connect Ring to Track',
              style: _inter(10,
                  color: Colors.white.withValues(alpha: 0.3))),
        ],
      ),
    );
  }
}

// ── Edit Cards button ─────────────────────────────────────────────────────────

class _EditCardsButton extends StatelessWidget {
  const _EditCardsButton();

  @override
  Widget build(BuildContext context) {
    return _ShrinkButton(
      onTap: () {},
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
                'Edit Cards',
                style: _inter(14,
                    weight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.5)),
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
        final px  = (i - 1) * step;
        final py  = size.height - data[i - 1] * size.height * 0.9;
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
      final x   = i * (barW + 2);
      final h   = data[i] * size.height;
      final y   = size.height - h;

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
    const barH   = 4.0;
    const radius = Radius.circular(2);
    final barY   = size.height - barH - 6;

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
    final double ovEnd   = dayW * 16;
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
