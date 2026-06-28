import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';


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

  // Calendar
  DateTime _calMonth = DateTime(DateTime.now().year, DateTime.now().month);

  // Computed day sets
  final Set<DateTime> _periodDays = {};
  final Set<DateTime> _fertileDays = {};
  final Set<DateTime> _ovulationDays = {};

  // Symptom state
  String _mood = '';
  int _energy = 0;
  bool _cramps = false, _headache = false, _bloating = false;
  String _notes = '';
  bool _savingSymptoms = false;
  bool _symptomsExpanded = true;

  // Setup form (empty state)
  DateTime _setupPeriodStart = DateTime.now().subtract(const Duration(days: 7));
  int _setupCycleLen = 28;
  int _setupPeriodLen = 5;
  bool _savingSetup = false;

  // Scroll-to keys for action buttons
  final GlobalKey _calendarKey = GlobalKey();
  final GlobalKey _symptomsKey = GlobalKey();

  // ── Phase helpers ──────────────────────────────────────────────────────────

  static const _phaseColors = {
    'Menstrual': Color(0xFFEF4444),
    'Follicular': Color(0xFF818CF8),
    'Ovulation': Color(0xFF34D399),
    'Luteal': AppTheme.womenColor,
  };
  static const _phaseIcons = {
    'Menstrual': Icons.water_drop_rounded,
    'Follicular': Icons.eco_rounded,
    'Ovulation': Icons.brightness_high_rounded,
    'Luteal': Icons.nightlight_round,
  };
  static const _phaseDescs = {
    'Menstrual': 'Your period is here. Rest well, stay hydrated, and take it easy on intense workouts.',
    'Follicular': 'Energy is rising. A great time for new projects, social activities, and high-intensity workouts.',
    'Ovulation': 'Peak fertility window. You may feel your most energetic, confident, and social right now.',
    'Luteal': 'Wind down and practice self-care. Your body is preparing — PMS symptoms may arise.',
  };

  CycleData? get _latest => _cycles.isEmpty ? null : _cycles.first;

  int get _currentCycleDay {
    final c = _latest;
    if (c == null) return 0;
    return DateTime.now().difference(c.periodStart).inDays + 1;
  }

  String get _currentPhase {
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

  // ── Init ───────────────────────────────────────────────────────────────────

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
        SupabaseService.getSymptomsForDate(user.id, DateTime.now()),
      ]);

      final profile = results[0] as Map<String, dynamic>?;
      final cycleRows = results[1] as List<Map<String, dynamic>>;
      final symptomsRow = results[2] as Map<String, dynamic>?;

      final cycles = cycleRows.map(CycleData.fromMap).toList();

      if (!mounted) return;
      setState(() {
        _gender = profile?['gender'] as String? ?? '';
        _cycles = cycles;
        if (symptomsRow != null) {
          _mood = symptomsRow['mood'] as String? ?? '';
          _energy = (symptomsRow['energy'] as num? ?? 0).toInt();
          _cramps = symptomsRow['cramps'] as bool? ?? false;
          _headache = symptomsRow['headache'] as bool? ?? false;
          _bloating = symptomsRow['bloating'] as bool? ?? false;
          _notes = symptomsRow['notes'] as String? ?? '';
        }
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

  // ── Setup save ─────────────────────────────────────────────────────────────

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

  // ── Symptom save ──────────────────────────────────────────────────────────

  Future<void> _saveSymptoms() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() => _savingSymptoms = true);
    try {
      await SupabaseService.upsertSymptoms(
        userId: user.id,
        date: DateTime.now(),
        mood: _mood.isNotEmpty ? _mood : null,
        energy: _energy > 0 ? _energy : null,
        cramps: _cramps,
        headache: _headache,
        bloating: _bloating,
        notes: _notes,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Symptoms saved')));
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _savingSymptoms = false);
    }
  }

  // ── Calendar navigation ────────────────────────────────────────────────────

  void _prevMonth() => setState(
      () => _calMonth = DateTime(_calMonth.year, _calMonth.month - 1));
  void _nextMonth() => setState(
      () => _calMonth = DateTime(_calMonth.year, _calMonth.month + 1));

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: _appBar(),
        body: const Center(
            child: CircularProgressIndicator(color: AppTheme.womenColor)),
      );
    }

    if (_gender != 'Female') {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: _appBar(),
        body: _buildGenderGate(),
      );
    }

    if (_cycles.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: _appBar(),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _buildOnboarding(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _appBar(),
      body: RefreshIndicator(
        color: AppTheme.womenColor,
        backgroundColor: AppTheme.card,
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              // ── Header ─────────────────────────────────────────────────
              Text(
                'WOMEN\'S HEALTH',
                style: GoogleFonts.inter(
                  color: AppTheme.womenColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Understand your changing rhythms with more clarity',
                style: GoogleFonts.inter(color: AppTheme.textSec, fontSize: 12),
              ),

              const SizedBox(height: 24),

              // ── Cycle ring ─────────────────────────────────────────────
              _buildRingSection(),

              const SizedBox(height: 20),

              // ── Three info boxes ───────────────────────────────────────
              _buildPredictionRow(),

              const SizedBox(height: 12),

              // ── Action buttons ─────────────────────────────────────────
              _buildActionButtons(),

              const SizedBox(height: 16),

              // ── Today's insight ────────────────────────────────────────
              _buildInsightCard(),

              const SizedBox(height: 20),

              // ── Calendar ───────────────────────────────────────────────
              SizedBox(key: _calendarKey, child: _buildCalendar()),

              const SizedBox(height: 16),

              _buildStats(),

              const SizedBox(height: 16),

              // ── Symptoms ───────────────────────────────────────────────
              SizedBox(key: _symptomsKey, child: _buildSymptomCard()),

              const SizedBox(height: 16),

              _buildHistory(),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  AppBar _appBar() => AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Women\'s Health',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
        actions: [
          if (_cycles.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded,
                  color: AppTheme.womenColor),
              tooltip: 'Log new period',
              onPressed: _showNewCycleSheet,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(color: AppTheme.div, height: 0.5),
        ),
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
                  style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text(
                'This feature is available for users who selected Female during onboarding.',
                style: GoogleFonts.inter(color: AppTheme.textSec, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

  // ── Onboarding / empty state ───────────────────────────────────────────────

  Widget _buildOnboarding() => Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: AppTheme.womenColor.withValues(alpha: 0.3)),
          ),
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
                style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Enter your last period date and cycle details to get predictions for your next period, ovulation, and fertile window.',
              style: GoogleFonts.inter(color: AppTheme.textSec, fontSize: 13),
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
                  style: GoogleFonts.inter(
                      color: Colors.white, fontWeight: FontWeight.w500),
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
                      style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
            ),
          ),
        ),
      ]);

  // ── Cycle ring ─────────────────────────────────────────────────────────────

  Widget _buildRingSection() {
    final day = _currentCycleDay;
    final c = _latest!;

    return Center(
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
                  'CYCLE DAY',
                  style: GoogleFonts.inter(
                    color: AppTheme.textSec,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Day $day',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Prediction row (three info boxes) ─────────────────────────────────────

  Widget _buildPredictionRow() {
    final c = _latest!;
    final now = DateTime.now();
    final today = _d(now);

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    String fmtShort(DateTime d) {
      if (d.year == now.year) return '${months[d.month - 1]} ${d.day}';
      return '${months[d.month - 1]} ${d.day}, ${d.year}';
    }

    final daysToNext =
        c.nextPeriod.difference(today).inDays.clamp(0, 999);

    final isFertile = _fertileDays.contains(today);

    final phase = _currentPhase;
    final phaseColor = _phaseColors[phase] ?? AppTheme.womenColor;
    final phaseIcon = _phaseIcons[phase] ?? Icons.nightlight_round;

    DateTime phaseEnd;
    switch (phase) {
      case 'Menstrual':
        phaseEnd = c.periodEnd;
        break;
      case 'Follicular':
        phaseEnd = c.fertileStart;
        break;
      case 'Ovulation':
        phaseEnd = c.fertileEnd;
        break;
      default:
        phaseEnd = c.nextPeriod;
    }

    return Row(children: [
      Expanded(
        child: _InfoBox(
          label: 'NEXT PERIOD',
          value: '$daysToNext DAYS',
          valueColor: AppTheme.danger,
          subtitle: 'Till ${fmtShort(c.nextPeriod)}',
          icon: Icons.water_drop_rounded,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _InfoBox(
          label: 'FERTILITY',
          value: isFertile ? 'ACTIVE' : 'INACTIVE',
          valueColor: isFertile ? AppTheme.success : AppTheme.textSec,
          subtitle: '${fmtShort(c.fertileStart)} – ${fmtShort(c.fertileEnd)}',
          icon: Icons.favorite_rounded,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _InfoBox(
          label: 'PHASE',
          value: phase.toUpperCase(),
          valueColor: phaseColor,
          subtitle: 'Till ${fmtShort(phaseEnd)}',
          icon: phaseIcon,
        ),
      ),
    ]);
  }

  // ── Action buttons ─────────────────────────────────────────────────────────

  Widget _buildActionButtons() {
    void scrollTo(GlobalKey key) {
      final ctx = key.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut);
      }
    }

    return Row(children: [
      Expanded(
        child: _ActionBtn(
          label: 'VIEW FULL\nCYCLE',
          onTap: () => scrollTo(_calendarKey),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _ActionBtn(
          label: 'ADD\nSYMPTOMS',
          onTap: () => scrollTo(_symptomsKey),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _ActionBtn(
          label: 'ADD TODAY\'S\nMOOD',
          onTap: () {
            setState(() => _symptomsExpanded = true);
            Future.delayed(const Duration(milliseconds: 80),
                () => scrollTo(_symptomsKey));
          },
        ),
      ),
    ]);
  }

  // ── Today's insight ────────────────────────────────────────────────────────

  Widget _buildInsightCard() {
    final phase = _currentPhase;
    final desc = _phaseDescs[phase] ?? '';
    final color = _phaseColors[phase] ?? AppTheme.womenColor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.lightbulb_outline_rounded,
                  color: color, size: 17),
            ),
            const SizedBox(width: 10),
            Text(
              'TODAY\'S INSIGHT',
              style: GoogleFonts.inter(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Text(
            desc,
            style: GoogleFonts.inter(
                color: Colors.white, fontSize: 13, height: 1.55),
          ),
        ],
      ),
    );
  }

  // ── Calendar ───────────────────────────────────────────────────────────────

  Widget _buildCalendar() {
    final firstDay = DateTime(_calMonth.year, _calMonth.month, 1);
    final daysInMonth =
        DateTime(_calMonth.year, _calMonth.month + 1, 0).day;
    // Monday-first: weekday Mon=1 → offset 0, Sun=7 → offset 6
    final offset = firstDay.weekday - 1;
    final today = _d(DateTime.now());

    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    const headers = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final totalCells = offset + daysInMonth;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        // Month nav
        Row(children: [
          GestureDetector(
            onTap: _prevMonth,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.chevron_left_rounded,
                  color: Colors.white, size: 22),
            ),
          ),
          Expanded(
            child: Text(
              '${months[_calMonth.month - 1]} ${_calMonth.year}',
              style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15),
              textAlign: TextAlign.center,
            ),
          ),
          GestureDetector(
            onTap: _nextMonth,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.chevron_right_rounded,
                  color: Colors.white, size: 22),
            ),
          ),
        ]),
        const SizedBox(height: 8),

        // Day-of-week headers
        Row(
          children: headers
              .map((h) => Expanded(
                    child: Center(
                      child: Text(h,
                          style: GoogleFonts.inter(
                              color: AppTheme.textSec,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4)),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 6),

        // Day grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7, childAspectRatio: 1.05),
          itemCount: totalCells,
          itemBuilder: (_, i) {
            if (i < offset) return const SizedBox();
            final dayNum = i - offset + 1;
            final date =
                DateTime(_calMonth.year, _calMonth.month, dayNum);
            final d = _d(date);
            final isPeriod = _periodDays.contains(d);
            final isOvulation = _ovulationDays.contains(d);
            final isFertile = _fertileDays.contains(d);
            final isToday = d == today;

            Color? bgColor;
            Color textColor = Colors.white;
            Border? border;

            if (isPeriod) {
              bgColor = AppTheme.danger.withValues(alpha: 0.25);
              textColor = AppTheme.danger;
            } else if (isOvulation) {
              bgColor = AppTheme.success.withValues(alpha: 0.2);
              textColor = AppTheme.success;
            } else if (isFertile) {
              bgColor = AppTheme.womenColor.withValues(alpha: 0.15);
              textColor = AppTheme.womenColor;
            }

            if (isToday) {
              border = Border.all(color: AppTheme.gold, width: 1.5);
            }

            return Container(
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(8),
                border: border,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$dayNum',
                    style: GoogleFonts.inter(
                      color: isToday ? AppTheme.gold : textColor,
                      fontSize: 12,
                      fontWeight:
                          isToday ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  if (isOvulation)
                    Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.only(top: 1),
                      decoration: const BoxDecoration(
                          color: AppTheme.success, shape: BoxShape.circle),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),

        // Legend
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegDot(AppTheme.danger, 'Period'),
            const SizedBox(width: 14),
            _LegDot(AppTheme.womenColor, 'Fertile'),
            const SizedBox(width: 14),
            _LegDot(AppTheme.success, 'Ovulation'),
            const SizedBox(width: 14),
            _LegDot(AppTheme.gold, 'Today'),
          ],
        ),
      ]),
    );
  }

  // ── Stats ──────────────────────────────────────────────────────────────────

  Widget _buildStats() {
    int avgCycle = 0, avgPeriod = 0;
    if (_cycles.isNotEmpty) {
      avgCycle =
          (_cycles.map((c) => c.cycleLength).reduce((a, b) => a + b) /
                  _cycles.length)
              .round();
      avgPeriod =
          (_cycles.map((c) => c.periodLength).reduce((a, b) => a + b) /
                  _cycles.length)
              .round();
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.div)),
      child: Row(children: [
        _StatCell('Avg Cycle', '$avgCycle', 'days'),
        Container(width: 1, height: 40, color: AppTheme.div),
        _StatCell('Avg Period', '$avgPeriod', 'days'),
        Container(width: 1, height: 40, color: AppTheme.div),
        _StatCell('Cycle Day', '$_currentCycleDay', 'today'),
      ]),
    );
  }

  // ── Symptoms ───────────────────────────────────────────────────────────────

  Widget _buildSymptomCard() {
    final now = DateTime.now();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final dateLabel = '${months[now.month - 1]} ${now.day}';

    return Container(
      decoration: BoxDecoration(
          color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        GestureDetector(
          onTap: () => setState(() => _symptomsExpanded = !_symptomsExpanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(children: [
              const Icon(Icons.notes_rounded,
                  color: AppTheme.womenColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TODAY\'S SYMPTOMS',
                          style: GoogleFonts.inter(
                              color: AppTheme.womenColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2)),
                      Text(dateLabel,
                          style: GoogleFonts.inter(
                              color: AppTheme.textSec, fontSize: 12)),
                    ]),
              ),
              Icon(
                _symptomsExpanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: AppTheme.textSec,
              ),
            ]),
          ),
        ),

        if (_symptomsExpanded) ...[
          const Divider(color: AppTheme.div, height: 0.5),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionLabel('HOW ARE YOU FEELING?'),
                  const SizedBox(height: 10),
                  _buildMoodRow(),
                  const SizedBox(height: 16),

                  _SectionLabel('ENERGY LEVEL'),
                  const SizedBox(height: 10),
                  _buildEnergyRow(),
                  const SizedBox(height: 16),

                  _SectionLabel('SYMPTOMS'),
                  const SizedBox(height: 10),
                  _buildSymptomToggles(),
                  const SizedBox(height: 16),

                  _SectionLabel('NOTES (OPTIONAL)'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: TextEditingController(text: _notes)
                      ..selection = TextSelection.collapsed(
                          offset: _notes.length),
                    onChanged: (v) => _notes = v,
                    maxLines: 2,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Add notes…',
                      hintStyle: GoogleFonts.inter(color: AppTheme.textSec),
                      filled: true,
                      fillColor: AppTheme.card2,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppTheme.div)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppTheme.div)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: AppTheme.womenColor)),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 16),

                  GestureDetector(
                    onTap: _savingSymptoms ? null : _saveSymptoms,
                    child: Container(
                      width: double.infinity,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.womenColor,
                            AppTheme.womenColor.withValues(alpha: 0.7)
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: _savingSymptoms
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : Text('Save',
                                style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15)),
                      ),
                    ),
                  ),
                ]),
          ),
        ],
      ]),
    );
  }

  Widget _buildMoodRow() {
    const moods = ['Great', 'Good', 'Neutral', 'Sad', 'Awful'];
    const moodEmojis = ['😊', '🙂', '😐', '😕', '😢'];
    return Row(
      children: List.generate(moods.length, (i) {
        final active = _mood == moods[i];
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _mood = moods[i]),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: active
                    ? AppTheme.womenColor.withValues(alpha: 0.2)
                    : AppTheme.card2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: active ? AppTheme.womenColor : AppTheme.div),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(moodEmojis[i], style: GoogleFonts.inter(fontSize: 20)),
                const SizedBox(height: 2),
                Text(moods[i],
                    style: GoogleFonts.inter(
                        color: active ? AppTheme.womenColor : AppTheme.textSec,
                        fontSize: 9,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildEnergyRow() {
    return Row(
      children: List.generate(5, (i) {
        final level = i + 1;
        final active = level <= _energy;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _energy = level),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 36,
              decoration: BoxDecoration(
                color: active
                    ? AppTheme.womenColor.withValues(alpha: 0.2)
                    : AppTheme.card2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: active ? AppTheme.womenColor : AppTheme.div),
              ),
              child: Center(
                child: Icon(
                  active ? Icons.bolt_rounded : Icons.bolt_outlined,
                  color: active ? AppTheme.womenColor : AppTheme.textSec,
                  size: 18,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildSymptomToggles() {
    final items = [
      (label: 'Cramps', icon: Icons.sick_rounded,
        active: _cramps, onTap: () => setState(() => _cramps = !_cramps)),
      (label: 'Headache', icon: Icons.psychology_alt_rounded,
        active: _headache, onTap: () => setState(() => _headache = !_headache)),
      (label: 'Bloating', icon: Icons.bubble_chart_rounded,
        active: _bloating, onTap: () => setState(() => _bloating = !_bloating)),
    ];
    return Row(
      children: items.map((item) {
        return Expanded(
          child: GestureDetector(
            onTap: item.onTap,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: item.active
                    ? AppTheme.womenColor.withValues(alpha: 0.15)
                    : AppTheme.card2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: item.active ? AppTheme.womenColor : AppTheme.div),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(item.icon,
                    color: item.active ? AppTheme.womenColor : AppTheme.textSec,
                    size: 20),
                const SizedBox(height: 4),
                Text(item.label,
                    style: GoogleFonts.inter(
                        color: item.active
                            ? AppTheme.womenColor
                            : AppTheme.textSec,
                        fontSize: 11,
                        fontWeight: item.active
                            ? FontWeight.w600
                            : FontWeight.w400)),
              ]),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── History ────────────────────────────────────────────────────────────────

  Widget _buildHistory() {
    if (_cycles.isEmpty) return const SizedBox();
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    return Container(
      decoration: BoxDecoration(
          color: AppTheme.card, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text('CYCLE HISTORY',
              style: GoogleFonts.inter(
                  color: AppTheme.textSec,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
        ),
        ..._cycles.asMap().entries.map((e) {
          final c = e.value;
          final isLast = e.key == _cycles.length - 1;
          final label =
              '${months[c.periodStart.month - 1]} ${c.periodStart.year}';
          return Column(children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: AppTheme.womenColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.calendar_month_rounded,
                      color: AppTheme.womenColor, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(label,
                          style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                      Text(
                          'Period: ${c.periodLength} days  ·  Started ${_fmt(c.periodStart)}',
                          style: GoogleFonts.inter(
                              color: AppTheme.textSec, fontSize: 12)),
                    ])),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: AppTheme.womenColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppTheme.womenColor.withValues(alpha: 0.3))),
                  child: Text('${c.cycleLength} days',
                      style: GoogleFonts.inter(
                          color: AppTheme.womenColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 12)),
                ),
              ]),
            ),
            if (!isLast)
              const Divider(
                  color: AppTheme.div, height: 0.5, indent: 66),
          ]);
        }),
      ]),
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
                Text('Log New Period',
                    style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
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
                        Text(_fmt(newStart),
                            style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.w500)),
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
                              style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15)),
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

  static String _fmt(DateTime d) {
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }
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

    // Background track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF2A2A2A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW,
    );

    // Progress arc
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

// ── Info box ──────────────────────────────────────────────────────────────────

class _InfoBox extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final String subtitle;
  final IconData icon;

  const _InfoBox({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.div),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: valueColor, size: 16),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              color: AppTheme.textSec.withValues(alpha: 0.8),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.inter(
              color: valueColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

// ── Action button ─────────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _ActionBtn({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppTheme.womenColor.withValues(alpha: 0.35)),
        ),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }
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
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.inter(color: AppTheme.textSec, fontSize: 10)),
        ],
      );
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  const _StatCell(this.label, this.value, this.unit);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(label,
              style: GoogleFonts.inter(color: AppTheme.textSec, fontSize: 10)),
          const SizedBox(height: 4),
          Text(value,
              style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
          Text(unit,
              style:
                  GoogleFonts.inter(color: AppTheme.textSec, fontSize: 10)),
        ]),
      );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: GoogleFonts.inter(
          color: AppTheme.textSec,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2));
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
              style: GoogleFonts.inter(
                  color: AppTheme.textSec,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
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
                      style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700)),
                  TextSpan(
                      text: unit,
                      style: GoogleFonts.inter(
                          color: AppTheme.textSec, fontSize: 13)),
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
