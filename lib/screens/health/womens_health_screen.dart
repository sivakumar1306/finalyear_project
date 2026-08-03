import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/glass_menu.dart';
import '../../widgets/screenshot_share.dart';
import 'vital_note_screen.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../models/womens_health_models.dart';
import '../../services/womens_health_prediction_service.dart';

// ── Design tokens (glass card system per DESIGN.md) ────────────────────────

const _kGlassBg = Color(0x0FFFFFFF); // rgba(255,255,255,0.06)
const _kGlassBorder = Color(0x17FFFFFF); // rgba(255,255,255,0.09)
const _kFertile = AppTheme.hrvColor; // teal
const _kOvulation = Color(0xFFA855F7); // purple
const _kToday = Color(0xFF60A5FA); // blue
const _kPeriod = AppTheme.womenColor; // pink

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
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _kWeekdaysShort = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const _kWeekdaysFull = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

String _fmtMD(DateTime d) => '${_kMonthsShort[d.month - 1]} ${d.day}';
String _fmtTillDate(DateTime d) =>
    'Till ${_kWeekdaysFull[d.weekday - 1].substring(0, 3)}, ${_fmtMD(d)}';

// ── Data model ─────────────────────────────────────────────────────────────────

class CycleData {
  final String id;
  final DateTime periodStart;
  final int cycleLength;
  final int periodLength;
  final String? notes;

  const CycleData({
    required this.id,
    required this.periodStart,
    required this.cycleLength,
    required this.periodLength,
    this.notes,
  });

  DateTime get ovulationDate =>
      periodStart.add(Duration(days: cycleLength - 14));
  DateTime get fertileStart =>
      periodStart.add(Duration(days: cycleLength - 14 - 5));
  DateTime get fertileEnd =>
      periodStart.add(Duration(days: cycleLength - 14 + 1));
  DateTime get periodEnd =>
      periodStart.add(Duration(days: periodLength - 1));
  DateTime get nextPeriod => periodStart.add(Duration(days: cycleLength));

  factory CycleData.fromMap(Map<String, dynamic> m) => CycleData(
        id: m['id'] as String,
        periodStart: DateTime.parse(m['period_start'] as String),
        cycleLength: (m['cycle_length'] as num? ?? 28).toInt(),
        periodLength: (m['period_length'] as num? ?? 5).toInt(),
        notes: m['notes'] as String?,
      );
}

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
  int _setupCycleLen = 28;
  int _setupPeriodLen = 5;
  bool _savingSetup = false;

  final _moreButtonKey = GlobalKey();
  final _screenshotKey = GlobalKey();

  static const _phaseColors = {
    'Menstrual': Color(0xFFEF4444),
    'Follicular': Color(0xFF818CF8),
    'Ovulation': _kOvulation,
    'Luteal': AppTheme.womenColor,
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
      final metrics = HealthMetrics(
        temperature: (ble.todayAvgSpo2 > 0 ? ble.todayAvgSpo2.toDouble() : 50.0).clamp(0, 100),
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

        final adjustedCycleLen = awheResult.finalPrediction.difference(l.periodStart).inDays;
        
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
    } catch (_) {
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
      toDraw.add(CycleData(
        id: 'predicted',
        periodStart: l.nextPeriod,
        cycleLength: l.cycleLength,
        periodLength: l.periodLength,
      ));
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
            SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger));
      }
    } finally {
      if (mounted) setState(() => _savingSetup = false);
    }
  }

  // ── Three-dot menu ──────────────────────────────────────────────────────────

  void _openMenu() {
    showGlassMenu(
      context: context,
      anchorKey: _moreButtonKey,
      items: [
        GlassMenuItem(
          label: 'Share',
          onTap: () =>
              shareScreenshot(_screenshotKey, text: 'My Cycle — SUNDR'),
        ),
        GlassMenuItem(
          label: 'Note',
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
                        'A small, sustained rise in basal temperature is a '
                        'common sign that ovulation has occurred.',
                  ),
                  VitalTip(
                    icon: Icons.bedtime_rounded,
                    color: AppTheme.sleepColor,
                    title: 'Sleep can get lighter pre-period',
                    tip:
                        'Rising progesterone in the late luteal phase can make '
                        'sleep feel lighter or more restless.',
                  ),
                ],
                didYouKnow:
                    'Cycle length naturally varies month to month — anywhere '
                    'from 21 to 35 days is considered typical.',
              ),
            ),
          ),
        ),
        GlassMenuItem(
          label: 'Log Period',
          onTap: _showNewCycleSheet,
        ),
      ],
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: _appBar(),
        body: const Center(
            child: CircularProgressIndicator(color: AppTheme.womenColor)),
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
          color: AppTheme.womenColor,
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
                if (_awheResult != null) ...[
                  _buildAwheCard(),
                  const SizedBox(height: 14),
                ],
                _buildPredictionCard(),
                const SizedBox(height: 14),
                _buildCalendarCard(),
                const SizedBox(height: 14),
                _buildCyclePatternsCard(),
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

  AppBar _appBar() => AppBar(
        backgroundColor: AppTheme.bg,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: const GlassBackButton(),
        title: Text('Women\'s Health',
            style: _inter(16, weight: FontWeight.w600)),
        actions: [
          if (_cycles.isNotEmpty)
            IconButton(
              key: _moreButtonKey,
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
              onPressed: _openMenu,
            ),
        ],
      );

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
                    color: AppTheme.womenColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle),
                child: const Icon(Icons.female_rounded,
                    color: AppTheme.womenColor, size: 40),
              ),
              const SizedBox(height: 20),
              Text('Women\'s Health',
                  style: _inter(22, weight: FontWeight.w700)),
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

  Widget _buildOnboarding() => Column(children: [
        _glassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                  color: AppTheme.womenColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle),
              child: const Icon(Icons.favorite_rounded,
                  color: AppTheme.womenColor, size: 26),
            ),
            const SizedBox(height: 16),
            Text('Track your menstrual cycle',
                style: _inter(20, weight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Enter your last period date and cycle details to get predictions for your next period, ovulation, and fertile window.',
              style: _inter(13, color: AppTheme.textSec),
            ),
          ]),
        ),
        const SizedBox(height: 20),

        _SetupField(
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
                        primary: AppTheme.womenColor, surface: AppTheme.card),
                  ),
                  child: child!,
                ),
              );
              if (picked != null) setState(() => _setupPeriodStart = picked);
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                  color: AppTheme.card2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.div)),
              child: Row(children: [
                const Icon(Icons.calendar_today_rounded,
                    color: AppTheme.womenColor, size: 18),
                const SizedBox(width: 10),
                Text(
                  _fmt(_setupPeriodStart),
                  style: _inter(14, weight: FontWeight.w500),
                ),
                const Spacer(),
                const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textSec),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 12),

        _SetupField(
          label: 'TYPICAL CYCLE LENGTH',
          child: _StepperTile(
            value: _setupCycleLen,
            unit: 'days',
            min: 21,
            max: 40,
            onChanged: (v) => setState(() => _setupCycleLen = v),
          ),
        ),
        const SizedBox(height: 12),

        _SetupField(
          label: 'TYPICAL PERIOD LENGTH',
          child: _StepperTile(
            value: _setupPeriodLen,
            unit: 'days',
            min: 2,
            max: 10,
            onChanged: (v) => setState(() => _setupPeriodLen = v),
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
                colors: [Color(0xFFEC4899), Color(0xFFA21B6A)],
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
                          color: Colors.white, strokeWidth: 2.5))
                  : Text('Start Tracking',
                      style: _inter(16, weight: FontWeight.w700)),
            ),
          ),
        ),
      ]);

  // ── Cycle ring ─────────────────────────────────────────────────────────────

  Widget _buildRingSection() {
    final day = _currentCycleDay;
    final c = _latest!;

    return Center(
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppTheme.womenColor.withValues(alpha: 0.16),
              blurRadius: 70,
              spreadRadius: 6,
            ),
          ],
        ),
        child: SizedBox(
          width: 210,
          height: 210,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(210, 210),
                painter: _CycleRingPainter(
                  currentDay: day,
                  cycleLength: c.cycleLength,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Day $day',
                    style: _inter(30, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'CYCLE DAY',
                    style: _inter(
                      11,
                      color: AppTheme.womenColor,
                      weight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── AWHE Adaptive Engine card ─────────────────────────────────────────────

  Widget _buildAwheCard() {
    final res = _awheResult;
    if (res == null) return const SizedBox.shrink();

    final phaseName = res.estimatedPhase.displayName;
    final summary = res.estimatedPhase.physiologicalSummary;
    final score = res.confidenceScore.round();
    final reasons = res.explainableReasons;
    final isVitalsOnly = res.isVitalsOnlyPath;

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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ADAPTIVE WOMEN\'S HEALTH ENGINE',
                    style: _inter(11, color: const Color(0xFFA855F7), weight: FontWeight.w700, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isVitalsOnly ? 'Wearable Vitals-Only Inference' : 'Smart Ring Vitals + Calendar Engine',
                    style: _inter(12, color: AppTheme.textSec),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.hrvColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.hrvColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '$score% Confidence',
                  style: _inter(12, color: AppTheme.hrvColor, weight: FontWeight.bold),
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
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.womenColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  res.confidenceLevel.toUpperCase(),
                  style: _inter(10, color: AppTheme.womenColor, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            summary,
            style: _inter(13, color: AppTheme.textSec, height: 1.3),
          ),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'PHYSIOLOGICAL SUPPORTING REASONS',
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
        ],
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
        colors: [
          AppTheme.womenColor.withValues(alpha: 0.16),
          Colors.transparent,
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _PredictionCol(
              label: 'Next Period',
              value: '$daysToNext',
              valueSuffix: ' Days',
              subtitle: 'Till ${_fmtMD(c.nextPeriod)}',
            ),
          ),
          Expanded(
            child: _PredictionCol(
              label: 'Fertility',
              value: isFertile ? 'Active' : 'Inactive',
              subtitle: _fmtTillDate(c.fertileEnd),
            ),
          ),
          Expanded(
            child: _PredictionCol(
              label: 'Phase',
              value: phase.isEmpty ? '--' : phase,
              subtitle: _fmtTillDate(phaseEnd),
            ),
          ),
        ],
      ),
    );
  }

  // ── Calendar ───────────────────────────────────────────────────────────────

  Widget _buildCalendarCard() {
    final now = DateTime.now();
    final today = _d(now);
    final firstOfMonth = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final startOffset = firstOfMonth.weekday % 7; // Sunday-first
    final gridStart = firstOfMonth.subtract(Duration(days: startOffset));
    final weeksNeeded = ((startOffset + daysInMonth) / 7).ceil();
    final totalCells = weeksNeeded * 7;

    final cells = List.generate(totalCells, (i) {
      final date = gridStart.add(Duration(days: i));
      final d = _d(date);
      return _CalCell(
        date: date,
        inMonth: date.month == now.month && date.year == now.year,
        isPeriod: _periodDays.contains(d),
        isFertile: _fertileDays.contains(d),
        isOvulation: _ovulationDays.contains(d),
        isToday: d == today,
      );
    });

    final weeks = <List<_CalCell>>[
      for (int i = 0; i < cells.length; i += 7) cells.sublist(i, i + 7),
    ];

    return _glassCard(
      child: Column(
        children: [
          Text(
            '${_fmtMD(now)}, ${_kWeekdaysFull[now.weekday - 1]}',
            style: _inter(14, weight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.9)),
          ),
          const SizedBox(height: 16),
          Row(
            children: _kWeekdaysShort
                .map((h) => Expanded(
                      child: Center(
                        child: Text(h,
                            style: _inter(11,
                                weight: FontWeight.w600, color: AppTheme.textSec)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          for (final week in weeks) _buildWeekRow(week),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 6,
            children: const [
              _LegDot(_kPeriod, 'Period'),
              _LegDot(_kFertile, 'Fertile Window'),
              _LegDot(_kOvulation, 'Ovulation'),
              _LegDot(_kToday, 'Today'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeekRow(List<_CalCell> week) {
    final isFert = week.map((c) => c.isFertile).toList();
    return SizedBox(
      height: 38,
      child: Stack(
        children: [
          Row(
            children: [
              for (int i = 0; i < 7; i++)
                Expanded(child: _fertileSegment(isFert, i)),
            ],
          ),
          Row(
            children: [for (final c in week) Expanded(child: _dayCell(c))],
          ),
        ],
      ),
    );
  }

  Widget _fertileSegment(List<bool> isFert, int i) {
    if (!isFert[i]) return const SizedBox.shrink();
    final isFirst = i == 0 || !isFert[i - 1];
    final isLast = i == 6 || !isFert[i + 1];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: _kFertile.withValues(alpha: 0.7), width: 1.2),
          bottom:
              BorderSide(color: _kFertile.withValues(alpha: 0.7), width: 1.2),
          left: isFirst
              ? BorderSide(color: _kFertile.withValues(alpha: 0.7), width: 1.2)
              : BorderSide.none,
          right: isLast
              ? BorderSide(color: _kFertile.withValues(alpha: 0.7), width: 1.2)
              : BorderSide.none,
        ),
        borderRadius: BorderRadius.horizontal(
          left: isFirst ? const Radius.circular(18) : Radius.zero,
          right: isLast ? const Radius.circular(18) : Radius.zero,
        ),
      ),
    );
  }

  Widget _dayCell(_CalCell c) {
    Color? bg;
    Color textColor = c.inMonth
        ? Colors.white.withValues(alpha: 0.9)
        : Colors.white.withValues(alpha: 0.25);
    FontWeight weight = FontWeight.w400;

    if (c.isOvulation) {
      bg = _kOvulation.withValues(alpha: c.inMonth ? 0.85 : 0.35);
      textColor = Colors.white;
      weight = FontWeight.w700;
    } else if (c.isPeriod) {
      bg = c.inMonth
          ? _kPeriod.withValues(alpha: 0.28)
          : Colors.white.withValues(alpha: 0.08);
      textColor = c.inMonth ? _kPeriod : Colors.white.withValues(alpha: 0.4);
    }

    Border? border;
    if (c.isToday) {
      border = Border.all(color: _kToday, width: 1.5);
      textColor = _kToday;
      weight = FontWeight.w700;
    }

    return Center(
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: border,
        ),
        child: Text(
          '${c.date.day}',
          style: _inter(12, color: textColor, weight: weight),
        ),
      ),
    );
  }

  // ── Cycle patterns over time ────────────────────────────────────────────────

  Widget _buildCyclePatternsCard() {
    final shown = _cycles.take(3).toList();
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CYCLE PATTERNS OVER TIME',
            style: _inter(10,
                weight: FontWeight.w700,
                color: AppTheme.textSec,
                letterSpacing: 1.2),
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(height: 18),
            _CyclePatternRow(
              index: i + 1,
              cycle: shown[i],
            ),
          ],
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
                child: Icon(Icons.water_drop_rounded,
                    color: AppTheme.tempColor, size: 14),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('BASAL BODY TEMPERATURE',
                        style: _inter(11,
                            weight: FontWeight.w700,
                            color: AppTheme.textSec,
                            letterSpacing: 1.0)),
                    const SizedBox(height: 2),
                    Text('Tracks tiny temperature shifts to detect ovulation.',
                        style: _inter(9, color: AppTheme.textSec.withValues(alpha: 0.7))),
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
                child: Text('No data found', style: _inter(12, color: AppTheme.textSec)),
              ),
            )
          else
            Column(
              children: [
                SizedBox(
                  height: 20,
                  width: double.infinity,
                  child: CustomPaint(painter: _TempGaugePainter(delta: delta)),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('-1.0°C', style: _inter(10, color: AppTheme.textSec)),
                    Text('Baseline (${baseline.toStringAsFixed(1)}°C / ${((baseline * 9 / 5) + 32).toStringAsFixed(1)}°F)', style: _inter(10, color: AppTheme.textSec)),
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
    final caption =
        hasData ? 'Lighter in late luteal phase.' : 'Connect ring to track sleep.';

    final deepSecs = ble.todaySleepDeepSecs;
    final lightSecs = ble.todaySleepLightSecs;
    final remSecs = ble.todaySleepRemSecs;
    final awakeSecs = math.max(0, durationSec - (deepSecs + lightSecs + remSecs));

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bedtime_rounded,
                  color: AppTheme.sleepColor, size: 14),
              const SizedBox(width: 6),
              Text('SLEEP',
                  style: _inter(11,
                      weight: FontWeight.w700,
                      color: AppTheme.textSec,
                      letterSpacing: 1.0)),
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
                child: Text('No data found', style: _inter(12, color: AppTheme.textSec)),
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
                        if (awakeSecs > 0) Expanded(flex: awakeSecs, child: Container(color: AppTheme.sleepAwake.withValues(alpha: 0.55))),
                        if (remSecs > 0) Expanded(flex: remSecs, child: Container(color: const Color(0xFF38BDF8))),
                        if (lightSecs > 0) Expanded(flex: lightSecs, child: Container(color: AppTheme.sleepLight)),
                        if (deepSecs > 0) Expanded(flex: deepSecs, child: Container(color: AppTheme.sleepDeep)),
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
                    _LegDot(AppTheme.sleepAwake, 'Awake'),
                    _LegDot(const Color(0xFF38BDF8), 'REM'),
                    _LegDot(AppTheme.sleepLight, 'Light'),
                    _LegDot(AppTheme.sleepDeep, 'Deep'),
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

    final caption =
        hasData ? 'Higher in follicular phase.' : 'Connect ring to track stress.';

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.monitor_heart_rounded,
                    color: AppTheme.stressColor, size: 14),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('STRESS',
                        style: _inter(11,
                            weight: FontWeight.w700,
                            color: AppTheme.textSec,
                            letterSpacing: 1.0)),
                    const SizedBox(height: 2),
                    Text('How physical stress impacts your cycle timing.',
                        style: _inter(9, color: AppTheme.textSec.withValues(alpha: 0.7))),
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
                child: Text('No data found', style: _inter(12, color: AppTheme.textSec)),
              ),
            )
          else
            Column(
              children: [
                SizedBox(
                  height: 20,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _StressGaugePainter(
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
                    Text('50 (Med)', style: _inter(10, color: AppTheme.textSec)),
                    Text('100 (High)', style: _inter(10, color: AppTheme.textSec)),
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

  // ── New cycle bottom sheet ─────────────────────────────────────────────────

  Future<void> _showNewCycleSheet() async {
    DateTime newStart = DateTime.now();
    int newCycleLen = _latest?.cycleLength ?? 28;
    int newPeriodLen = _latest?.periodLength ?? 5;
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setModal) {
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                left: 20,
                right: 20,
                top: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppTheme.div,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Log New Period', style: _inter(18, weight: FontWeight.w700)),
                const SizedBox(height: 20),

                _SetupField(
                  label: 'PERIOD START DATE',
                  child: GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: newStart,
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 180)),
                        lastDate: DateTime.now(),
                        builder: (c, child) => Theme(
                          data: ThemeData.dark().copyWith(
                              colorScheme: const ColorScheme.dark(
                                  primary: AppTheme.womenColor,
                                  surface: AppTheme.card)),
                          child: child!,
                        ),
                      );
                      if (picked != null) setModal(() => newStart = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                          color: AppTheme.card2,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.div)),
                      child: Row(children: [
                        const Icon(Icons.calendar_today_rounded,
                            color: AppTheme.womenColor, size: 18),
                        const SizedBox(width: 10),
                        Text(_fmt(newStart), style: _inter(14, weight: FontWeight.w500)),
                        const Spacer(),
                        const Icon(Icons.chevron_right_rounded,
                            color: AppTheme.textSec),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _SetupField(
                  label: 'CYCLE LENGTH',
                  child: _StepperTile(
                    value: newCycleLen,
                    unit: 'days',
                    min: 21,
                    max: 40,
                    onChanged: (v) => setModal(() => newCycleLen = v),
                  ),
                ),
                const SizedBox(height: 12),
                _SetupField(
                  label: 'PERIOD LENGTH',
                  child: _StepperTile(
                    value: newPeriodLen,
                    unit: 'days',
                    min: 2,
                    max: 10,
                    onChanged: (v) => setModal(() => newPeriodLen = v),
                  ),
                ),
                const SizedBox(height: 24),

                GestureDetector(
                  onTap: saving
                      ? null
                      : () async {
                          setModal(() => saving = true);
                          final user = SupabaseService.currentUser;
                          if (user != null) {
                            await SupabaseService.saveCycle(
                              userId: user.id,
                              periodStart: newStart,
                              cycleLength: newCycleLen,
                              periodLength: newPeriodLen,
                            );
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                          await _load();
                        },
                  child: Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFFEC4899), Color(0xFFA21B6A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : Text('Save Period',
                              style: _inter(15, weight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  // ── Utilities ──────────────────────────────────────────────────────────────

  static String _fmt(DateTime d) => '${_kMonthsShort[d.month - 1]} ${d.day}, ${d.year}';
}

// ── Calendar cell model ────────────────────────────────────────────────────────

class _CalCell {
  final DateTime date;
  final bool inMonth;
  final bool isPeriod;
  final bool isFertile;
  final bool isOvulation;
  final bool isToday;

  const _CalCell({
    required this.date,
    required this.inMonth,
    required this.isPeriod,
    required this.isFertile,
    required this.isOvulation,
    required this.isToday,
  });
}

// ── Cycle ring painter ────────────────────────────────────────────────────────

class _CycleRingPainter extends CustomPainter {
  final int currentDay;
  final int cycleLength;

  const _CycleRingPainter({required this.currentDay, required this.cycleLength});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 18;
    const strokeW = 14.0;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW,
    );

    final progress = (currentDay / cycleLength).clamp(0.0, 1.0);
    if (progress <= 0) return;

    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round
        ..shader = const LinearGradient(
          colors: [Color(0xFFEC4899), Color(0xFFA855F7)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_CycleRingPainter old) =>
      old.currentDay != currentDay || old.cycleLength != cycleLength;
}

// ── Prediction column ──────────────────────────────────────────────────────────

class _PredictionCol extends StatelessWidget {
  final String label;
  final String value;
  final String valueSuffix;
  final String subtitle;

  const _PredictionCol({
    required this.label,
    required this.value,
    this.valueSuffix = '',
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: _inter(10.5,
              weight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.45)),
        ),
        const SizedBox(height: 6),
        RichText(
          text: TextSpan(children: [
            TextSpan(
                text: value,
                style: _inter(20, weight: FontWeight.w600, color: Colors.white)),
            if (valueSuffix.isNotEmpty)
              TextSpan(
                  text: valueSuffix,
                  style: _inter(12, color: Colors.white.withValues(alpha: 0.6))),
          ]),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: _inter(11, color: Colors.white.withValues(alpha: 0.4)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ── Cycle pattern row ──────────────────────────────────────────────────────────

class _CyclePatternRow extends StatelessWidget {
  final int index;
  final CycleData cycle;
  const _CyclePatternRow({required this.index, required this.cycle});

  @override
  Widget build(BuildContext context) {
    final rangeEnd = cycle.periodStart.add(Duration(days: cycle.cycleLength - 1));
    final rangeLabel = '${_fmtMD(cycle.periodStart)} – ${_fmtMD(rangeEnd)}';
    final markerRatio = ((cycle.cycleLength - 14) / cycle.cycleLength).clamp(0.05, 0.95);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 74,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cycle $index',
                  style: _inter(13, weight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('${cycle.cycleLength} days',
                  style: _inter(11, color: AppTheme.textSec)),
            ],
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 22,
            child: _CyclePatternTrack(markerRatio: markerRatio),
          ),
        ),
        const SizedBox(width: 10),
        Text(rangeLabel, style: _inter(11, color: AppTheme.textSec)),
      ],
    );
  }
}

class _CyclePatternTrack extends StatelessWidget {
  final double markerRatio;
  const _CyclePatternTrack({required this.markerRatio});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        const markerSize = 20.0;
        return Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(w, 22),
              painter: _CyclePatternDotsPainter(markerRatio: markerRatio),
            ),
            Positioned(
              left: (markerRatio * w - markerSize / 2).clamp(0.0, w - markerSize),
              child: Container(
                width: markerSize,
                height: markerSize,
                decoration: const BoxDecoration(
                  color: _kToday,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.circle, color: Colors.white, size: 8),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CyclePatternDotsPainter extends CustomPainter {
  final double markerRatio;
  const _CyclePatternDotsPainter({required this.markerRatio});

  static const _dotCount = 26;

  @override
  void paint(Canvas canvas, Size size) {
    final gap = size.width / (_dotCount - 1);
    for (int i = 0; i < _dotCount; i++) {
      final ratio = i / (_dotCount - 1);
      if ((ratio - markerRatio).abs() < 0.06) continue;
      final color = ratio < markerRatio
          ? AppTheme.hrvColor.withValues(alpha: 0.7)
          : AppTheme.womenColor.withValues(alpha: 0.45);
      canvas.drawCircle(
        Offset(i * gap, size.height / 2),
        2.2,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_CyclePatternDotsPainter old) =>
      old.markerRatio != markerRatio;
}

class _TempGaugePainter extends CustomPainter {
  final double delta;
  const _TempGaugePainter({required this.delta});

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    
    // Draw baseline
    canvas.drawLine(
      Offset(0, midY),
      Offset(size.width, midY),
      Paint()..color = Colors.white.withValues(alpha: 0.2)..strokeWidth = 2,
    );

    // Draw baseline tick
    canvas.drawLine(
      Offset(size.width / 2, midY - 6),
      Offset(size.width / 2, midY + 6),
      Paint()..color = Colors.white.withValues(alpha: 0.5)..strokeWidth = 2,
    );

    // Calculate dot x position
    // Range is -1.0 to +1.0
    final clampedDelta = delta.clamp(-1.0, 1.0);
    final ratio = (clampedDelta + 1.0) / 2.0; // 0.0 to 1.0
    final x = ratio * size.width;

    // Draw dot
    canvas.drawCircle(
      Offset(x, midY),
      6,
      Paint()..color = AppTheme.tempColor,
    );
  }

  @override
  bool shouldRepaint(_TempGaugePainter old) => old.delta != delta;
}

// ── Stress gauge painter ────────────────────────────────────────────────────────

class _StressGaugePainter extends CustomPainter {
  final int min;
  final int max;
  final int latest;

  const _StressGaugePainter({required this.min, required this.max, required this.latest});

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    
    // Draw background track
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, midY - 4, size.width, 8),
      const Radius.circular(4),
    );
    canvas.drawRRect(trackRect, Paint()..color = Colors.white.withValues(alpha: 0.1));

    if (max > 0) {
      // Draw range bar
      final startX = (min / 100.0).clamp(0.0, 1.0) * size.width;
      final endX = (max / 100.0).clamp(0.0, 1.0) * size.width;
      
      final rangeRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(startX, midY - 4, endX, midY + 4),
        const Radius.circular(4),
      );
      canvas.drawRRect(rangeRect, Paint()..color = AppTheme.stressColor.withValues(alpha: 0.4));
    }

    // Draw latest dot
    final latestX = (latest / 100.0).clamp(0.0, 1.0) * size.width;
    canvas.drawCircle(
      Offset(latestX, midY),
      8,
      Paint()..color = AppTheme.stressColor,
    );
    // Draw white border for dot
    canvas.drawCircle(
      Offset(latestX, midY),
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_StressGaugePainter old) => old.min != min || old.max != max || old.latest != latest;
}

// ── Small supporting widgets ───────────────────────────────────────────────────

class _LegDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegDot(this.color, this.label);

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(label, style: _inter(10, color: AppTheme.textSec)),
        ],
      );
}

class _SetupField extends StatelessWidget {
  final String label;
  final Widget child;
  const _SetupField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: _inter(10,
                  weight: FontWeight.w700,
                  color: AppTheme.textSec,
                  letterSpacing: 1)),
          const SizedBox(height: 6),
          child,
        ],
      );
}

class _StepperTile extends StatelessWidget {
  final int value;
  final String unit;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _StepperTile({
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
            color: AppTheme.card2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.div)),
        child: Row(children: [
          GestureDetector(
            onTap: value > min ? () => onChanged(value - 1) : null,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: AppTheme.div,
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.remove_rounded,
                  color: value > min ? Colors.white : AppTheme.textSec,
                  size: 18),
            ),
          ),
          Expanded(
            child: Center(
              child: RichText(
                text: TextSpan(children: [
                  TextSpan(
                      text: '$value ',
                      style: _inter(20, weight: FontWeight.w700)),
                  TextSpan(text: unit, style: _inter(13, color: AppTheme.textSec)),
                ]),
              ),
            ),
          ),
          GestureDetector(
            onTap: value < max ? () => onChanged(value + 1) : null,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: AppTheme.womenColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppTheme.womenColor.withValues(alpha: 0.3))),
              child: Icon(Icons.add_rounded,
                  color: value < max ? AppTheme.womenColor : AppTheme.textSec,
                  size: 18),
            ),
          ),
        ]),
      );
}
