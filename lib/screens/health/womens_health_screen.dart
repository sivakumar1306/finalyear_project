import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import '../../services/incident_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';

import '../../widgets/screenshot_share.dart';
import 'vital_note_screen.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../models/womens_health_models.dart';
import '../../services/womens_health_prediction_service.dart';
import 'cycle_statistics_screen.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/legend_dot.dart';
import 'womens_health_widgets.dart';
import '../../services/notification_prefs.dart';
import '../../widgets/glass_menu.dart';
import 'womens_health_notifications_screen.dart';
import '../../services/local_notification_service.dart';
import 'log_period_screen.dart';

// ── Design tokens (glass card system per DESIGN.md) ────────────────────────

const _kGlassBg = AppTheme.glassCard; // rgba(255,255,255,0.06)
const _kGlassBorder = AppTheme.glassBorder; // rgba(255,255,255,0.09)


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

const _kMonthsShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _kWeekdaysFull = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _fmtMD(DateTime d) => '${_kMonthsShort[d.month - 1]} ${d.day}';
String _fmtTillDate(DateTime d) =>
    'Till ${_kWeekdaysFull[d.weekday - 1].substring(0, 3)}, ${_fmtMD(d)}';

// ── Screen ─────────────────────────────────────────────────────────────────────

class WomensHealthScreen extends StatefulWidget {
  const WomensHealthScreen({super.key});
  @override
  State<WomensHealthScreen> createState() => _WomensHealthScreenState();
}

class _WomensHealthScreenState extends State<WomensHealthScreen> {
  bool _loading = true;
  String _gender = '';
  List<CycleData> _cycles = [];

  final Set<DateTime> _periodDays = {};
  final Set<DateTime> _fertileDays = {};
  final Set<DateTime> _ovulationDays = {};

  DateTime _setupPeriodStart = DateTime.now().subtract(const Duration(days: 7));
  final int _setupCycleLen = 28;
  final int _setupPeriodLen = 5;
  bool _savingSetup = false;



  final _screenshotKey = GlobalKey();
  final _moreButtonKey = GlobalKey();

  static const _phaseColors = {
    'Menstrual': AppTheme.danger,
    'Follicular': AppTheme.bpColor,
    'Ovulation': Color(0xFF0D9488),
    'Luteal': AppTheme.danger,
  };

  PredictionResult? _awheResult;

  CycleData? get _latest => _cycles.isEmpty ? null : _cycles.first;

  int get _currentCycleDay {
    final c = _latest;
    if (c == null) return 0;
    return DateTime.now().difference(c.periodStart).inDays + 1;
  }

  String get _currentPhase {
    if (_awheResult != null) {
      return _awheResult!.estimatedPhase.displayName.replaceAll(' Phase', '');
    }
    final c = _latest;
    if (c == null) return '';
    final day = _currentCycleDay;
    if (day <= 0) return 'Luteal';
    if (day <= c.periodLength) return 'Menstrual';
    final ovDay = c.cycleLength - 14;
    if (day < ovDay - 5) return 'Follicular';
    if (day <= ovDay + 1) return 'Ovulation';
    return 'Luteal';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return;

      final results = await Future.wait([
        SupabaseService.getProfile(user.id),
        SupabaseService.getCycles(user.id),
      ]);

      final profile = results[0] as Map<String, dynamic>?;
      final cycleRows = results[1] as List<Map<String, dynamic>>;
      final cycles = cycleRows.map(CycleData.fromMap).toList();

      if (!mounted) return;

      final ble = context.read<BleProvider>();

      // Normalize temperature: 50 is baseline (36.5C). 55 is elevated (+0.5C).
      double normalizedTemp = 50.0;
      if (ble.latestTempC > 0) {
        normalizedTemp = 50.0 + ((ble.latestTempC - 36.5) * 10);
      }

      final metrics = HealthMetrics(
        temperature: normalizedTemp.clamp(0, 100),
        hrv: ble.todayAvgHrv.toDouble().clamp(0, 100),
        heartRate: ble.todayAvgHr.toDouble().clamp(0, 100),
        sleepQuality: ble.todaySleepScore.toDouble().clamp(0, 100),
        stress: ble.todayAvgStress.toDouble().clamp(0, 100),
        activityLevel: ((ble.todaySteps / 10000.0) * 100.0).clamp(0, 100),
      );

      final service = WomenHealthPredictionService();
      PredictionResult? awheResult;

      if (cycles.isNotEmpty) {
        final l = cycles.first;
        awheResult = service.predictCycle(
          lastMenstrualPeriod: l.periodStart,
          averageCycleLength: l.cycleLength,
          metrics: metrics,
          hasHistory: true,
        );

        final adjustedCycleLen = awheResult.finalPrediction
            .difference(l.periodStart)
            .inDays;

        cycles[0] = CycleData(
          id: l.id,
          periodStart: l.periodStart,
          cycleLength: adjustedCycleLen,
          periodLength: l.periodLength,
          notes: l.notes,
        );
      } else {
        awheResult = service.predictCycle(
          lastMenstrualPeriod: null,
          averageCycleLength: 28,
          metrics: metrics,
          hasHistory: false,
        );
      }

      setState(() {
        _gender = profile?['gender'] as String? ?? '';
        _cycles = cycles;
        _awheResult = awheResult;
      });
      _computeCalendarDays();

      // Sync local notifications
      final prefs = await NotificationPrefs.load();
      await LocalNotificationService().syncWomensHealthNotifications(
        nextPeriodDate: awheResult.finalPrediction,
        fertileWindowStartDate: awheResult.fertileWindowStart,
        periodRemindersEnabled: prefs['Next Period Reminder'] ?? true,
        fertileRemindersEnabled: prefs['Fertility Window'] ?? true,
      );
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'womens_health_screen',
        error: e,
        stackTrace: st,
        customMessage: '_loadData failed',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _computeCalendarDays() {
    _periodDays.clear();
    _fertileDays.clear();
    _ovulationDays.clear();

    final toDraw = [..._cycles];
    if (_cycles.isNotEmpty) {
      final l = _cycles.first;
      toDraw.add(
        CycleData(
          id: 'predicted',
          periodStart: l.nextPeriod,
          cycleLength: l.cycleLength,
          periodLength: l.periodLength,
        ),
      );
    }

    for (final c in toDraw) {
      for (int i = 0; i < c.periodLength; i++) {
        _periodDays.add(_d(c.periodStart.add(Duration(days: i))));
      }
      for (int i = -5; i <= 1; i++) {
        _fertileDays.add(_d(c.ovulationDate.add(Duration(days: i))));
      }
      _ovulationDays.add(_d(c.ovulationDate));
    }

    if (mounted) setState(() {});
  }

  static DateTime _d(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  Future<void> _saveSetup() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() => _savingSetup = true);
    try {
      await SupabaseService.saveCycle(
        userId: user.id,
        periodStart: _setupPeriodStart,
        cycleLength: _setupCycleLen,
        periodLength: _setupPeriodLen,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingSetup = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: _appBar(),
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.danger),
        ),
      );
    }

    if (_gender != 'Female') {
      return Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: _appBar(),
        body: _buildGenderGate(),
      );
    }

    if (_cycles.isEmpty) {
      return Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: _appBar(),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _buildOnboarding(),
        ),
      );
    }

    return RepaintBoundary(
      key: _screenshotKey,
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: _appBar(),
        body: RefreshIndicator(
          color: AppTheme.danger,
          backgroundColor: AppTheme.card,
          onRefresh: _load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                _buildRingSection(),
                const SizedBox(height: 20),
                _buildPredictionCard(),
                const SizedBox(height: 14),
                _buildCycleStatisticsButton(),
                const SizedBox(height: 14),
                _buildNotificationsButton(),
                const SizedBox(height: 14),
                _buildTemperatureCard(context),
                const SizedBox(height: 14),
                _buildSleepCard(context),
                const SizedBox(height: 14),
                _buildStressCard(context),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openMenu() {
    showGlassMenu(
      context: context,
      anchorKey: _moreButtonKey,
      items: [
        GlassMenuItem(label: 'History', onTap: _showHistorySheet),
        GlassMenuItem(
          label: 'Info',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VitalNoteScreen(
                title: 'Women\'s Health',
                heading: 'About Your Cycle',
                intro:
                    'Your menstrual cycle moves through four phases — each with '
                    'its own hormonal rhythm that can shift your temperature, '
                    'sleep, and stress levels.',
                ranges: [
                  VitalRange(
                    label: 'Menstrual',
                    range: 'Days 1–5',
                    color: _phaseColors['Menstrual']!,
                  ),
                  VitalRange(
                    label: 'Follicular',
                    range: 'Days 6–13',
                    color: _phaseColors['Follicular']!,
                  ),
                  VitalRange(
                    label: 'Ovulation',
                    range: 'Days 14–15',
                    color: _phaseColors['Ovulation']!,
                  ),
                  VitalRange(
                    label: 'Luteal',
                    range: 'Days 16–28',
                    color: _phaseColors['Luteal']!,
                  ),
                ],
                tips: const [
                  VitalTip(
                    icon: Icons.thermostat_rounded,
                    color: AppTheme.tempColor,
                    title: 'Temperature rises after ovulation',
                    tip:
                        'A small, sustained rise in basal temperature is a common sign that ovulation has occurred.',
                  ),
                  VitalTip(
                    icon: Icons.bedtime_rounded,
                    color: AppTheme.sleepColor,
                    title: 'Sleep can get lighter pre-period',
                    tip:
                        'Rising progesterone in the late luteal phase can make sleep feel lighter or more restless.',
                  ),
                ],
                didYouKnow:
                    'Cycle length naturally varies month to month — anywhere from 21 to 35 days is considered typical.',
              ),
            ),
          ),
        ),
        GlassMenuItem(
          label: 'Share',
          onTap: () =>
              shareScreenshot(_screenshotKey, text: 'My Cycle — SUNDR'),
        ),
      ],
    );
  }

  AppBar _appBar() => AppBar(
    backgroundColor: AppTheme.bg,
    foregroundColor: Colors.white,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: true,
    leading: const GlassBackButton(),
    title: Text('Women\'s Health', style: _inter(16, weight: FontWeight.w600)),
    actions: [
      if (_cycles.isNotEmpty)
        IconButton(
          key: _moreButtonKey,
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onPressed: _openMenu,
        ),
    ],
  );

  void _showHistorySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.div,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Period History',
                      style: _inter(18, weight: FontWeight.w700),
                    ),
                    Text(
                      'Swipe to delete',
                      style: _inter(12, color: AppTheme.textSec),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView.separated(
                    itemCount: _cycles.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final cycle = _cycles[index];
                      return Dismissible(
                        key: ValueKey(cycle.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: AppTheme.danger,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.white,
                          ),
                        ),
                        onDismissed: (direction) {
                          final removedCycle = _cycles[index];
                          setModal(() {
                            _cycles.removeAt(index);
                          });

                          final user = SupabaseService.currentUser;
                          if (user != null) {
                            SupabaseService.deleteCycle(
                                  userId: user.id,
                                  periodStart: removedCycle.periodStart,
                                  periodLength: removedCycle.periodLength,
                                )
                                .then((_) {
                                  _load();
                                })
                                .catchError((e) {
                                  setModal(() {
                                    _cycles.insert(index, removedCycle);
                                  });
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(
                                        content: Text('Failed to delete'),
                                        backgroundColor: AppTheme.danger,
                                      ),
                                    );
                                  }
                                });
                          }
                        },
                        child: CyclePatternRow(
                          index: _cycles.length - index,
                          cycle: cycle,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Gender gate ────────────────────────────────────────────────────────────

  Widget _buildGenderGate() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.danger.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.female_rounded,
              color: AppTheme.danger,
              size: 40,
            ),
          ),
          const SizedBox(height: 20),
          Text('Women\'s Health', style: _inter(22, weight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(
            'This feature is available for users who selected Female during onboarding.',
            style: _inter(14, color: AppTheme.textSec),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  // ── Onboarding / empty state ───────────────────────────────────────────────

  Widget _buildOnboarding() => Column(
    children: [
      _glassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.favorite_rounded,
                color: AppTheme.danger,
                size: 26,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Track your menstrual cycle',
              style: _inter(20, weight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Enter your last period date and cycle details to get predictions for your next period, ovulation, and fertile window.',
              style: _inter(13, color: AppTheme.textSec),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),

      SetupField(
        label: 'LAST PERIOD START DATE',
        child: GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _setupPeriodStart,
              firstDate: DateTime.now().subtract(const Duration(days: 180)),
              lastDate: DateTime.now(),
              builder: (ctx, child) => Theme(
                data: ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: AppTheme.danger,
                    surface: AppTheme.card,
                  ),
                ),
                child: child!,
              ),
            );
            if (picked != null) setState(() => _setupPeriodStart = picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.card2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.div),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  color: AppTheme.danger,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  _fmt(_setupPeriodStart),
                  style: _inter(14, weight: FontWeight.w500),
                ),
                const Spacer(),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.textSec,
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 28),

      GestureDetector(
        onTap: _savingSetup ? null : _saveSetup,
        child: Container(
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.danger, Color(0xFF991B1B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: _savingSetup
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : Text(
                    'Start Tracking',
                    style: _inter(16, weight: FontWeight.w700),
                  ),
          ),
        ),
      ),
    ],
  );

  // ── Cycle ring ─────────────────────────────────────────────────────────────

  Widget _buildRingSection() {
    final day = _currentCycleDay;
    final c = _latest!;
    final fertileStartDay = c.fertileStart.difference(c.periodStart).inDays + 1;
    final fertileEndDay = c.fertileEnd.difference(c.periodStart).inDays + 1;
    final ovulationDay = c.ovulationDate.difference(c.periodStart).inDays + 1;

    final now = DateTime.now();
    final todayStr = "TODAY · ${_fmtMD(now).toUpperCase()}";
    final nextPeriodStr = "Your next period is\ndue ${_fmtMD(c.nextPeriod)}";

    return Column(
      children: [
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 240,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(double.infinity, 240),
                painter: CycleDialPainter(
                  currentDay: day,
                  cycleLength: c.cycleLength,
                  periodLength: c.periodLength,
                  fertileStart: fertileStartDay,
                  fertileEnd: fertileEndDay,
                  ovulationDay: ovulationDay,
                ),
              ),
              Positioned(
                top: 50,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'DAY',
                            style: _inter(10, color: Colors.white.withValues(alpha: 0.5), weight: FontWeight.w600, letterSpacing: 1.5),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$day',
                            style: _inter(18, color: Colors.white, weight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      todayStr,
                      style: _inter(
                        12,
                        color: AppTheme.gold,
                        weight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      nextPeriodStr,
                      textAlign: TextAlign.center,
                      style: _inter(22, weight: FontWeight.w500, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton(
            onPressed: () => _showLogSheet(DateTime.now()),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.gold,
              side: BorderSide(color: AppTheme.gold.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              backgroundColor: AppTheme.gold.withValues(alpha: 0.05),
            ),
            child: Text(
              'Log a period',
              style: _inter(16, weight: FontWeight.w600, color: AppTheme.gold),
            ),
          ),
        ),
      ],
    );
  }

  // ── Cycle Statistics Button ─────────────────────────────────────────────

  Widget _buildCycleStatisticsButton() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                CycleStatisticsScreen(cycles: _cycles, awheResult: _awheResult),
          ),
        );
      },
      child: _glassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'View Cycle Statistics',
              style: _inter(16, weight: FontWeight.w400, color: Colors.white),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ── Notifications Button ────────────────────────────────────────────────

  Widget _buildNotificationsButton() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                WomensHealthNotificationsScreen(awheResult: _awheResult),
          ),
        );
      },
      child: _glassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Notifications',
              style: _inter(16, weight: FontWeight.w400, color: Colors.white),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ── Prediction card ─────────────────────────────────────────────────────────

  Widget _buildPredictionCard() {
    final c = _latest!;
    final now = DateTime.now();
    final today = _d(now);

    final daysToNext = c.nextPeriod.difference(today).inDays.clamp(0, 999);
    final isFertile = _fertileDays.contains(today);
    final phase = _currentPhase;

    DateTime phaseEnd;
    switch (phase) {
      case 'Menstrual':
        phaseEnd = c.periodEnd;
      case 'Follicular':
        phaseEnd = c.fertileStart;
      case 'Ovulation':
        phaseEnd = c.fertileEnd;
      default:
        phaseEnd = c.nextPeriod;
    }

    return _glassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      tint: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppTheme.danger.withValues(alpha: 0.16), Colors.transparent],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: PredictionCol(
              label: 'Next Period',
              value: '$daysToNext',
              valueSuffix: ' Days',
              subtitle: 'Till ${_fmtMD(c.nextPeriod)}',
            ),
          ),
          Expanded(
            child: PredictionCol(
              label: 'Fertility',
              value: isFertile ? 'Active' : 'Inactive',
              subtitle: _fmtTillDate(c.fertileEnd),
            ),
          ),
          Expanded(
            child: PredictionCol(
              label: 'Phase',
              value: phase.isEmpty ? '--' : phase,
              subtitle: _fmtTillDate(phaseEnd),
            ),
          ),
        ],
      ),
    );
  }



  // ── Temperature card ─────────────────────────────────────────────────────────

  Widget _buildTemperatureCard(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final tempC = ble.latestTempC;
    final hasData = tempC > 0;
    const baseline = 36.5;
    final delta = hasData ? tempC - baseline : 0.0;
    final double deltaC = delta;
    final double deltaF = delta * (9 / 5);

    String status;
    String caption;
    if (!hasData) {
      status = 'No data';
      caption = 'Connect ring to track temperature.';
    } else if (delta.abs() < 0.15) {
      status = 'Near Baseline';
      caption = 'Right at your baseline today.';
    } else if (delta > 0) {
      status = 'Slightly Raised';
      caption = 'Slightly above normal today.';
    } else {
      status = 'Slightly Lowered';
      caption = 'Slightly below normal today.';
    }

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.water_drop_rounded,
                  color: AppTheme.tempColor,
                  size: 14,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BASAL BODY TEMPERATURE',
                      style: _inter(
                        11,
                        weight: FontWeight.w700,
                        color: AppTheme.textSec,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tracks tiny temperature shifts to detect ovulation.',
                      style: _inter(
                        9,
                        color: AppTheme.textSec.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(status, style: _inter(16, weight: FontWeight.w600)),
              Text(
                hasData
                    ? '${deltaC >= 0 ? '+' : ''}${deltaC.toStringAsFixed(1)}°C / ${deltaF >= 0 ? '+' : ''}${deltaF.toStringAsFixed(1)}°F v/s Baseline'
                    : '--',
                style: _inter(12, color: AppTheme.textSec),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasData)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No data found',
                  style: _inter(12, color: AppTheme.textSec),
                ),
              ),
            )
          else
            Column(
              children: [
                SizedBox(
                  height: 20,
                  width: double.infinity,
                  child: CustomPaint(painter: TempGaugePainter(delta: delta)),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('-1.0°C', style: _inter(10, color: AppTheme.textSec)),
                    Text(
                      'Baseline (${baseline.toStringAsFixed(1)}°C / ${((baseline * 9 / 5) + 32).toStringAsFixed(1)}°F)',
                      style: _inter(10, color: AppTheme.textSec),
                    ),
                    Text('+1.0°C', style: _inter(10, color: AppTheme.textSec)),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 10),
          Container(height: 0.5, color: Colors.white.withValues(alpha: 0.08)),
          const SizedBox(height: 10),
          Text(caption, style: _inter(12, color: AppTheme.textSec)),
        ],
      ),
    );
  }

  // ── Sleep card ───────────────────────────────────────────────────────────────

  Widget _buildSleepCard(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final durationSec = ble.todaySleepDuration;
    final score = ble.todaySleepScore;
    final hasData = durationSec > 0;

    String status;
    if (!hasData) {
      status = 'No data';
    } else if (score >= 80) {
      status = 'Great night';
    } else if (score >= 60) {
      status = 'Good night';
    } else if (score >= 40) {
      status = 'Fair night';
    } else {
      status = 'Restless night';
    }

    final h = durationSec ~/ 3600;
    final m = (durationSec % 3600) ~/ 60;
    final durationLabel = hasData ? '${h}h ${m}m' : '--';
    final caption = hasData
        ? 'Lighter in late luteal phase.'
        : 'Connect ring to track sleep.';

    final deepSecs = ble.todaySleepDeepSecs;
    final lightSecs = ble.todaySleepLightSecs;
    final remSecs = ble.todaySleepRemSecs;
    final awakeSecs = math.max(
      0,
      durationSec - (deepSecs + lightSecs + remSecs),
    );

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.bedtime_rounded,
                color: AppTheme.sleepColor,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                'SLEEP',
                style: _inter(
                  11,
                  weight: FontWeight.w700,
                  color: AppTheme.textSec,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(status, style: _inter(16, weight: FontWeight.w600)),
              Text(durationLabel, style: _inter(15, weight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasData)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No data found',
                  style: _inter(12, color: AppTheme.textSec),
                ),
              ),
            )
          else
            Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 8,
                    width: double.infinity,
                    child: Row(
                      children: [
                        if (awakeSecs > 0)
                          Expanded(
                            flex: awakeSecs,
                            child: Container(
                              color: AppTheme.sleepAwake.withValues(
                                alpha: 0.55,
                              ),
                            ),
                          ),
                        if (remSecs > 0)
                          Expanded(
                            flex: remSecs,
                            child: Container(color: AppTheme.spo2Color),
                          ),
                        if (lightSecs > 0)
                          Expanded(
                            flex: lightSecs,
                            child: Container(color: AppTheme.sleepLight),
                          ),
                        if (deepSecs > 0)
                          Expanded(
                            flex: deepSecs,
                            child: Container(color: AppTheme.sleepDeep),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    LegendDot(color: AppTheme.sleepAwake, label: 'Awake'),
                    LegendDot(color: AppTheme.spo2Color, label: 'REM'),
                    LegendDot(color: AppTheme.sleepLight, label: 'Light'),
                    LegendDot(color: AppTheme.sleepDeep, label: 'Deep'),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 10),
          Container(height: 0.5, color: Colors.white.withValues(alpha: 0.08)),
          const SizedBox(height: 10),
          Text(caption, style: _inter(12, color: AppTheme.textSec)),
        ],
      ),
    );
  }

  // ── Stress card ──────────────────────────────────────────────────────────────

  Widget _buildStressCard(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final stress = ble.latestStressValue;
    final hasData = stress > 0;

    String status;
    if (!hasData) {
      status = 'No data';
    } else if (stress < 40) {
      status = 'Low Stress';
    } else if (stress < 60) {
      status = 'Normal Stress';
    } else if (stress < 80) {
      status = 'Elevated Stress';
    } else {
      status = 'High Stress';
    }

    final caption = hasData
        ? 'Higher in follicular phase.'
        : 'Connect ring to track stress.';

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.monitor_heart_rounded,
                  color: AppTheme.stressColor,
                  size: 14,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STRESS',
                      style: _inter(
                        11,
                        weight: FontWeight.w700,
                        color: AppTheme.textSec,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'How physical stress impacts your cycle timing.',
                      style: _inter(
                        9,
                        color: AppTheme.textSec.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(status, style: _inter(16, weight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasData)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No data found',
                  style: _inter(12, color: AppTheme.textSec),
                ),
              ),
            )
          else
            Column(
              children: [
                SizedBox(
                  height: 20,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: StressGaugePainter(
                      min: ble.todayMinStress,
                      max: ble.todayMaxStress,
                      latest: stress,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('0 (Low)', style: _inter(10, color: AppTheme.textSec)),
                    Text(
                      '50 (Med)',
                      style: _inter(10, color: AppTheme.textSec),
                    ),
                    Text(
                      '100 (High)',
                      style: _inter(10, color: AppTheme.textSec),
                    ),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 10),
          Container(height: 0.5, color: Colors.white.withValues(alpha: 0.08)),
          const SizedBox(height: 10),
          Text(caption, style: _inter(12, color: AppTheme.textSec)),
        ],
      ),
    );
  }

  // ── Log Period bottom sheet ────────────────────────────────────────────────

  Future<void> _showLogSheet(DateTime dateToLog) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => LogPeriodScreen(
          initialDate: dateToLog,
          periodDays: _periodDays,
          fertileDays: _fertileDays,
          onSave: (date, flow, color, notes, feelings, pains, pms) async {
            final user = SupabaseService.currentUser;
            if (user != null) {
              String finalNotes = notes;
              final extraPains = pains.where((p) => p != 'Cramps' && p != 'Pain Free').toList();
              if (extraPains.isNotEmpty) {
                finalNotes += '${finalNotes.isEmpty ? '' : '\n'}Pain: ${extraPains.join(', ')}';
              }
              if (pms) {
                finalNotes += '${finalNotes.isEmpty ? '' : '\n'}PMS: Yes';
              }

              await SupabaseService.upsertSymptoms(
                userId: user.id,
                date: date,
                flowIntensity: flow,
                flowColor: color,
                notes: finalNotes,
                mood: feelings.join(', '),
                cramps: pains.contains('Cramps'),
              );
            }
            if (mounted) {
              await _load();
            }
          },
        ),
      ),
    );
  }

  // ── Utilities ──────────────────────────────────────────────────────────────

  static String _fmt(DateTime d) =>
      '${_kMonthsShort[d.month - 1]} ${d.day}, ${d.year}';
}
