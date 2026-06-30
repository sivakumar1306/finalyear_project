import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../providers/workout_provider.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import 'ring_scan_sheet.dart';

// ── Local design tokens ───────────────────────────────────────────────────────

const _kBorder = Color(0xFF242424);
const _kSec2   = Color(0xFF888888);

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

  // ── Label/status helpers ──────────────────────────────────────────────────

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
    if (score >= 60) return AppTheme.sleepColor;
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
      backgroundColor: AppTheme.card,
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

                // ── Row 1: Steps / Distance / Calories ────────────────────
                _ActivityCard(
                  steps: ble.todaySteps,
                  distanceM: ble.todayDistanceM,
                  calories: ble.todayCalories,
                  connected: ble.isConnected,
                  onTap: () => Navigator.pushNamed(context, '/steps'),
                ),
                const SizedBox(height: 12),

                // ── Row 2: Women's Health (full-width, females only) ──────
                if (_gender.toLowerCase() == 'female') ...[
                  _WomensHealthCard(
                    onTap: () => Navigator.pushNamed(context, '/womens-health'),
                  ),
                  const SizedBox(height: 12),
                ],

                // ── Row 3: Heart Rate + Blood Oxygen ──────────────────────
                Row(children: [
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
                      statusColor: ble.todayAvgHr > 0 ? AppTheme.hrColor : _kSec2,
                      accentColor: AppTheme.hrColor,
                      sparkData: const [0.45, 0.5, 0.55, 0.5, 0.6, 0.55, 0.5, 0.48, 0.52, 0.58, 0.54, 0.5],
                      connected: ble.isConnected,
                      onTap: () => Navigator.pushNamed(context, '/heart-rate'),
                    ),
                  ),
                  const SizedBox(width: 12),
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
                      statusColor: ble.todayAvgSpo2 > 0 ? AppTheme.spo2Color : _kSec2,
                      accentColor: AppTheme.spo2Color,
                      sparkData: const [0.96, 0.97, 0.96, 0.98, 0.97, 0.99, 0.98, 0.97, 0.96, 0.98, 0.97, 0.99],
                      connected: ble.isConnected,
                      onTap: () => Navigator.pushNamed(context, '/blood-oxygen'),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),

                // ── Row 4: Blood Pressure + HRV ───────────────────────────
                Row(children: [
                  Expanded(
                    child: _HomeCard(
                      label: 'Blood Pressure',
                      value: ble.latestBpSbp > 0
                          ? '${ble.latestBpSbp}/${ble.latestBpDbp}'
                          : '--/--',
                      unit: ble.latestBpSbp > 0 ? 'mmHg' : '',
                      status: ble.latestBpSbp > 0 ? 'Latest reading' : 'No data',
                      statusColor: ble.latestBpSbp > 0 ? AppTheme.bpColor : _kSec2,
                      accentColor: AppTheme.bpColor,
                      sparkData: const [0.6, 0.65, 0.6, 0.68, 0.65, 0.6, 0.64, 0.67, 0.64, 0.6, 0.65, 0.62],
                      connected: ble.isConnected,
                      onTap: () => Navigator.pushNamed(context, '/blood-pressure'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _HomeCard(
                      label: 'HRV',
                      value: ble.todayAvgHrv > 0 ? '${ble.todayAvgHrv}' : '--',
                      unit: ble.todayAvgHrv > 0 ? 'ms' : '',
                      status: _hrvStatus(ble.todayAvgHrv),
                      statusColor: ble.todayAvgHrv > 0 ? AppTheme.hrvColor : _kSec2,
                      accentColor: AppTheme.hrvColor,
                      sparkData: const [0.5, 0.6, 0.45, 0.7, 0.55, 0.8, 0.6, 0.5, 0.45, 0.65, 0.7, 0.55],
                      connected: ble.isConnected,
                      onTap: () => Navigator.pushNamed(context, '/hrv'),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),

                // ── Row 5: Sleep + Temperature ─────────────────────────────
                Row(children: [
                  Expanded(
                    child: _HomeCard(
                      label: 'Sleep',
                      value: _sleepDurationLabel(ble.todaySleepDuration),
                      unit: '',
                      status: ble.todaySleepDuration > 0
                          ? 'Score: ${ble.todaySleepScore} · ${_sleepStatus(ble.todaySleepScore)}'
                          : 'No data',
                      statusColor: _sleepStatusColor(ble.todaySleepScore),
                      accentColor: AppTheme.sleepColor,
                      sparkData: const [0.5, 0.7, 0.9, 0.8, 0.6, 0.4, 0.3, 0.5, 0.7, 0.8, 0.6, 0.4],
                      connected: ble.isConnected,
                      onTap: () => Navigator.pushNamed(context, '/sleep'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _HomeCard(
                      label: 'Temperature',
                      value: '--',
                      unit: '°F',
                      status: 'No data',
                      statusColor: _kSec2,
                      accentColor: AppTheme.tempColor,
                      sparkData: const [0.5, 0.52, 0.51, 0.53, 0.52, 0.51, 0.5, 0.52, 0.53, 0.51, 0.5, 0.52],
                      connected: ble.isConnected,
                      onTap: () => Navigator.pushNamed(context, '/temperature'),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),

                // ── Row 6: Sport + Stress ──────────────────────────────────
                Row(children: [
                  Expanded(
                    child: _HomeCard(
                      label: 'Sport',
                      value: _workoutDurationLabel(workout.todayWorkoutDurationS),
                      unit: workout.todayWorkoutDurationS > 0 ? 'today' : '',
                      status: workout.todayWorkoutDurationS > 0 ? 'Active today' : 'No activity',
                      statusColor: workout.todayWorkoutDurationS > 0
                          ? const Color(0xFFD97706)
                          : _kSec2,
                      accentColor: const Color(0xFFD97706),
                      sparkData: const [0.2, 0.3, 0.5, 0.4, 0.6, 0.7, 0.5, 0.3, 0.2, 0.4, 0.5, 0.3],
                      connected: ble.isConnected,
                      onTap: () => Navigator.pushNamed(context, '/workouts'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _HomeCard(
                      label: 'Stress',
                      value: ble.latestStressValue > 0 ? '${ble.latestStressValue}' : '--',
                      unit: '',
                      status: _stressStatus(ble.latestStressValue),
                      statusColor: _stressColor(ble.latestStressValue),
                      accentColor: AppTheme.stressColor,
                      sparkData: const [0.30, 0.45, 0.38, 0.52, 0.48, 0.55, 0.42, 0.38, 0.47, 0.35, 0.40, 0.30],
                      connected: ble.isConnected,
                      onTap: () => Navigator.pushNamed(context, '/pressure'),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),

                // ── Edit Cards button ──────────────────────────────────────
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
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
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
        'ALL METRICS  TODAY',
        style: _inter(11,
            weight: FontWeight.w700,
            color: AppTheme.gold.withValues(alpha: 0.85),
            letterSpacing: 1.5),
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1C),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: connected
                ? AppTheme.gold.withValues(alpha: 0.25)
                : _kBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reconnecting)
              const SizedBox(
                width: 7, height: 7,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.gold),
              )
            else
              Container(
                width: 7, height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: connected ? AppTheme.success : const Color(0xFF555555),
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
                color: battery > 20 ? _kSec2 : AppTheme.danger,
                size: 14,
              ),
              Text('$battery%', style: _inter(11, color: _kSec2)),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Generic half-width metric card ────────────────────────────────────────────

// ── Shrink Click Animation Widget ───────────────────────────────────────────

class _ShrinkButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _ShrinkButton({
    required this.child,
    this.onTap,
  });

  @override
  State<_ShrinkButton> createState() => _ShrinkButtonState();
}

class _ShrinkButtonState extends State<_ShrinkButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onTap != null) {
      _controller.forward();
    }
  }

  void _onTapUp(TapUpDetails details) {
    if (widget.onTap != null) {
      _controller.reverse();
      widget.onTap!();
    }
  }

  void _onTapCancel() {
    if (widget.onTap != null) {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final String status;
  final Color statusColor;
  final Color accentColor;
  final List<double> sparkData;
  final bool connected;
  final VoidCallback? onTap;

  const _HomeCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.status,
    required this.statusColor,
    required this.accentColor,
    required this.sparkData,
    required this.connected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _ShrinkButton(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: const Color(0xFF1A1A1A),
        ),
        child: Container(
          height: 162,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accentColor.withValues(alpha: 0.12),
                accentColor.withValues(alpha: 0.02),
              ],
            ),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.15),
              width: 1.0,
            ),
          ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Title and arrow
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: _inter(13, weight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.9)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white70,
                        size: 16,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // Middle row: Value/Unit and Graph/Sparkline
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Value & Unit
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
                                  fontSize: 28,
                                  fontWeight: FontWeight.w200,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          if (unit.isNotEmpty) ...[
                            const SizedBox(width: 3),
                            Text(
                              unit,
                              style: _inter(11, weight: FontWeight.w600, color: Colors.white60),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Sparkline
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 28,
                        child: connected
                            ? CustomPaint(
                                painter: _SparkPainter(accentColor, sparkData),
                              )
                            : const _ConnectHint(compact: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Bottom row: Status
                Text(
                  status,
                  style: _inter(11, color: statusColor, weight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
    );
  }
}

// ── Activity card (full-width: steps + distance + calories) ──────────────────


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
    final accentColor = AppTheme.stepsColor;

    return _ShrinkButton(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: const Color(0xFF1A1A1A),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accentColor.withValues(alpha: 0.12),
                accentColor.withValues(alpha: 0.02),
              ],
            ),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.15),
              width: 1.0,
            ),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Activity',
                      style: _inter(13, weight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.9)),
                    ),
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white70,
                        size: 16,
                      ),
                    ),
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
                          color: AppTheme.stepsColor,
                        ),
                      ),
                      VerticalDivider(color: accentColor.withValues(alpha: 0.15), width: 1, thickness: 0.5),
                      Expanded(
                        child: _ActivityStat(
                          value: hasData ? km.toStringAsFixed(2) : '--',
                          unit: 'km',
                          color: AppTheme.success,
                        ),
                      ),
                      VerticalDivider(color: accentColor.withValues(alpha: 0.15), width: 1, thickness: 0.5),
                      Expanded(
                        child: _ActivityStat(
                          value: hasData ? '$calories' : '--',
                          unit: 'kcal',
                          color: const Color(0xFFD97706),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (connected)
                  SizedBox(
                    height: 28,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _SparkPainter(
                        AppTheme.stepsColor,
                        const [0.2, 0.4, 0.6, 0.5, 0.7, 0.8, 0.6, 0.5, 0.7, 0.9, 0.7, 0.5],
                      ),
                    ),
                  )
                else
                  const _ConnectHint(),
              ],
          ),
        ),
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
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(unit, style: _inter(11, color: color, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Women's Health card (full-width) ─────────────────────────────────────────

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
      final periodStart = DateTime.parse(row['period_start'] as String);
      final cycleLength = (row['cycle_length'] as num? ?? 28).toInt();
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
    if (_cycleDay <= _periodLen) return 'Period ongoing · ${_periodLen - _cycleDay + 1} days left';
    if (_cycleDay <= 13) return 'Next period in $daysLeft days';
    if (_cycleDay <= 16) return 'Next period in $daysLeft days · fertile window now';
    return 'Next period in $daysLeft days';
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = AppTheme.womenColor;
    return _ShrinkButton(
      onTap: widget.onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: const Color(0xFF1A1A1A),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accentColor.withValues(alpha: 0.12),
                accentColor.withValues(alpha: 0.02),
              ],
            ),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.15),
              width: 1.0,
            ),
          ),
          child: _body(),
        ),
      ),
    );
  }

  Widget _body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.nightlight_round, color: AppTheme.womenColor, size: 14),
                const SizedBox(width: 6),
                Text(
                  'CYCLE',
                  style: _inter(11,
                      weight: FontWeight.w700,
                      color: AppTheme.womenColor,
                      letterSpacing: 1.4),
                ),
              ],
            ),
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              child: const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white70,
                size: 16,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Phase + day number
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                _phaseName,
                style: _inter(18, weight: FontWeight.w600, color: Colors.white),
              ),
            ),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'Day ',
                    style: _inter(13, color: _kSec2),
                  ),
                  TextSpan(
                    text: _cycleDay > 0 ? '$_cycleDay' : '--',
                    style: GoogleFonts.inter(
                      fontSize: 28,
                      fontWeight: FontWeight.w200,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Cycle bar
        SizedBox(
          height: 26,
          width: double.infinity,
          child: CustomPaint(
            painter: _CycleBarPainter(
              currentDay: _cycleDay > 0 ? _cycleDay : 1,
              cycleLength: _cycleLength,
              periodLength: _periodLen,
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Footer
        RichText(
          text: TextSpan(
            style: _inter(11, color: _kSec2),
            children: _buildFooterSpans(),
          ),
        ),
      ],
    );
  }

  List<InlineSpan> _buildFooterSpans() {
    final text = _footerText;
    final boldParts = RegExp(r'\d+ days?');
    final spans = <InlineSpan>[];
    int last = 0;
    for (final m in boldParts.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      spans.add(TextSpan(
        text: m.group(0),
        style: _inter(11,
            weight: FontWeight.w700, color: AppTheme.womenColor),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return spans;
  }
}

// ── Connect hint ──────────────────────────────────────────────────────────────

class _ConnectHint extends StatelessWidget {
  final bool compact;
  const _ConnectHint({this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return const Align(
        alignment: Alignment.centerRight,
        child: Icon(
          Icons.bluetooth_disabled_rounded,
          size: 16,
          color: Color(0xFF555555),
        ),
      );
    }
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          const Icon(Icons.bluetooth_disabled_rounded, size: 11, color: Color(0xFF555555)),
          const SizedBox(width: 5),
          Text(
            'Connect Ring to Track',
            style: _inter(10, color: const Color(0xFF555555)),
          ),
        ],
      ),
    );
  }
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

  static const _pink   = AppTheme.womenColor;          // menstruation / ovulation
  static const _dark   = Color(0xFF2A2A2A);             // follicular / luteal track
  static const _marker = AppTheme.womenColor;

  @override
  void paint(Canvas canvas, Size size) {
    const barH   = 6.0;
    const radius = Radius.circular(3);
    final barY   = size.height - barH - 6; // leave 6px above for marker

    final Paint trackPaint = Paint()..color = _dark;
    final Paint pinkPaint  = Paint()..color = _pink;

    // Full track background
    canvas.drawRRect(
      RRect.fromLTRBR(0, barY, size.width, barY + barH, radius),
      trackPaint,
    );

    // Phase widths as fraction of cycleLength
    final double dayW = size.width / cycleLength;

    // Segment 1: Menstruation (days 1 – periodLength)
    final double menW = dayW * periodLength;
    canvas.drawRRect(
      RRect.fromLTRBR(0, barY, menW, barY + barH, radius),
      pinkPaint,
    );

    // Segment 2: Ovulation window (days 13–16)
    final double ovStart = dayW * 12;
    final double ovEnd   = dayW * 16;
    canvas.drawRect(
      Rect.fromLTRB(ovStart, barY, ovEnd, barY + barH),
      pinkPaint,
    );

    // Current day marker triangle ▼
    final double markerX = dayW * (currentDay - 0.5);
    final markerPath = Path()
      ..moveTo(markerX - 5, 0)
      ..lineTo(markerX + 5, 0)
      ..lineTo(markerX, 7)
      ..close();
    canvas.drawPath(markerPath, Paint()..color = _marker);
  }

  @override
  bool shouldRepaint(_CycleBarPainter old) =>
      old.currentDay != currentDay ||
      old.cycleLength != cycleLength ||
      old.periodLength != periodLength;
}

// ── Edit Cards button ─────────────────────────────────────────────────────────

class _EditCardsButton extends StatelessWidget {
  const _EditCardsButton();

  @override
  Widget build(BuildContext context) {
    return _ShrinkButton(
      onTap: () {},
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: const Color(0xFF1A1A1A),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.06),
                Colors.white.withValues(alpha: 0.02),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1.0,
            ),
          ),
          child: const Center(
            child: Text(
              'Edit Cards',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white60,
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
        ..color = color.withValues(alpha: 0.75)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.color != color || old.data != data;
}

