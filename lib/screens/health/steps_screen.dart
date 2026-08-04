import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/glass_icon_button.dart';
import '../../widgets/glass_menu.dart';
import '../../widgets/offline_notice.dart';
import '../../widgets/screenshot_share.dart';
import '../settings/card_settings_screen.dart';
import 'activity_description_screen.dart';
import '../../widgets/app_typography.dart';

// ── Design tokens ───────────────────────────────────────────────────────────
const _kBg = Color(0xFF050505);
const _kStepsColor = Color(0xFF4ADE80);
const _kDistColor = Color(0xFF60A5FA);
const _kCalColor = Color(0xFFFB923C);

const List<String> _monthAbbr = [
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

TextStyle _t(
  double s, {
  FontWeight w = FontWeight.w400,
  Color? c,
  double? ls,
}) => AppTypography.inter(
  fontSize: s,
  fontWeight: w,
  color: c ?? Colors.white.withValues(alpha: 0.95),
  letterSpacing: ls,
);

BoxDecoration _glass({double r = 20}) => BoxDecoration(
  color: Colors.white.withValues(alpha: 0.06),
  borderRadius: BorderRadius.circular(r),
  border: Border.all(color: Colors.white.withValues(alpha: 0.09), width: 0.5),
);

// ══════════════════════════════════════════════════════════════════════════════

class StepsScreen extends StatefulWidget {
  const StepsScreen({super.key});
  @override
  State<StepsScreen> createState() => _StepsScreenState();
}

class _DaySnapshot {
  final int steps;
  final int cal;
  final double distM;
  final List<int> stepSlots;
  final List<int> calSlots;
  final List<double> distSlots;

  const _DaySnapshot({
    required this.steps,
    required this.cal,
    required this.distM,
    required this.stepSlots,
    required this.calSlots,
    required this.distSlots,
  });

  bool get hasTotals => steps > 0 || cal > 0 || distM > 0;
  bool get hasIntervals =>
      stepSlots.any((v) => v > 0) ||
      calSlots.any((v) => v > 0) ||
      distSlots.any((v) => v > 0);

  static _DaySnapshot empty() => _DaySnapshot(
    steps: 0,
    cal: 0,
    distM: 0,
    stepSlots: List.filled(96, 0),
    calSlots: List.filled(96, 0),
    distSlots: List.filled(96, 0.0),
  );
}

class _StepsScreenState extends State<StepsScreen> {
  final _ble = BleService();
  final _moreButtonKey = GlobalKey();
  final _screenshotKey = GlobalKey();

  bool _dayLoad = false;
  bool _pastDayOffline = false;
  int _loadGen = 0;

  DateTime _selectedDate = DateTime.now();

  int _totalSteps = 0;
  int _totalCal = 0;
  double _totalDistM = 0.0;
  List<int> _todayStepSlots = List.filled(96, 0);
  List<int> _todayCalSlots = List.filled(96, 0);
  List<double> _todayDistSlots = List.filled(96, 0.0);

  int _daySteps = 0;
  int _dayCal = 0;
  double _dayDistM = 0.0;
  List<int> _stepsSlots = List.filled(96, 0);
  List<int> _calSlots = List.filled(96, 0);
  List<double> _distSlots = List.filled(96, 0.0);

  final Map<String, _DaySnapshot> _dayCache = {};

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _dateKey(DateTime d) {
    final x = _dateOnly(d);
    return '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
  }

  int _dayIndexFor(DateTime d) {
    final today = _dateOnly(DateTime.now());
    return today.difference(_dateOnly(d)).inDays;
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = _dateOnly(DateTime.now());
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final ble = context.read<BleProvider>();
    final curSteps = ble.todaySteps;
    final curCal = ble.todayCalories;
    final curDist = ble.todayDistanceM;

    final nowSlot = (DateTime.now().hour * 60 + DateTime.now().minute) ~/ 15;
    final stepSlots = List<int>.filled(96, 0);
    final calSlots = List<int>.filled(96, 0);
    final distSlots = List<double>.filled(96, 0.0);

    if (ble.todayStepsByInterval.length == 96 && ble.todayStepsByInterval.any((s) => s > 0)) {
      for (int i = 0; i < 96; i++) {
        stepSlots[i] = ble.todayStepsByInterval[i];
      }
    } else if (curSteps > 0) {
      // Distribute steps across active daytime intervals up to nowSlot
      final activeSlotsCount = (nowSlot - 28).clamp(1, 96); // starting ~7 AM
      final stepsPerSlot = (curSteps / activeSlotsCount).round();
      final calPerSlot = (curCal / activeSlotsCount).round();
      final distPerSlot = curDist / activeSlotsCount;

      for (int i = 28; i <= nowSlot && i < 96; i++) {
        stepSlots[i] = stepsPerSlot;
        calSlots[i] = calPerSlot;
        distSlots[i] = distPerSlot;
      }
    }

    setState(() {
      _totalSteps = curSteps;
      _totalCal = curCal;
      _totalDistM = curDist;
      _todayStepSlots = stepSlots;
      _todayCalSlots = calSlots;
      _todayDistSlots = distSlots;
      _daySteps = curSteps;
      _dayCal = curCal;
      _dayDistM = curDist;
      _stepsSlots = List<int>.from(stepSlots);
      _calSlots = List<int>.from(calSlots);
      _distSlots = List<double>.from(distSlots);
    });

    _dayCache[_dateKey(DateTime.now())] = _DaySnapshot(
      steps: curSteps,
      cal: curCal,
      distM: curDist,
      stepSlots: List<int>.from(stepSlots),
      calSlots: List<int>.from(calSlots),
      distSlots: List<double>.from(distSlots),
    );

    _loadDay(_selectedDate, force: true);
  }

  void _applySnapshot(_DaySnapshot snap, {required bool isToday}) {
    setState(() {
      _daySteps = snap.steps;
      _dayCal = snap.cal;
      _dayDistM = snap.distM;
      _stepsSlots = List<int>.from(snap.stepSlots);
      _calSlots = List<int>.from(snap.calSlots);
      _distSlots = List<double>.from(snap.distSlots);
      if (isToday) {
        _totalSteps = snap.steps;
        _totalCal = snap.cal;
        _totalDistM = snap.distM;
        _todayStepSlots = List<int>.from(snap.stepSlots);
        _todayCalSlots = List<int>.from(snap.calSlots);
        _todayDistSlots = List<double>.from(snap.distSlots);
      }
    });
  }

  // ── Interval JSON parsing (today + past ring payloads) ───────────────────

  _DaySnapshot? _parseIntervalJson(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      final list = decoded is List ? decoded : <dynamic>[];
      if (list.isEmpty) return null;

      final stepSlots = List<int>.filled(96, 0);
      final calSlots = List<int>.filled(96, 0);
      final distSlots = List<double>.filled(96, 0.0);
      int totalSteps = 0, totalCal = 0;
      double totalDist = 0.0;

      for (final item in list) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);

        // ProGuard-obfuscated keys (production AAR) and clear SDK field names.
        final slot =
            (m['d'] as num?)?.toInt() ??
            (m['timeIndex'] as num?)?.toInt() ??
            -1;
        final steps =
            (m['f'] as num?)?.toInt() ?? (m['walkSteps'] as num?)?.toInt() ?? 0;
        final runSteps = (m['runSteps'] as num?)?.toInt() ?? 0;
        final stepTotal = steps + runSteps;
        final calRaw =
            (m['e'] as num?)?.toInt() ?? (m['calorie'] as num?)?.toInt() ?? 0;
        final cal = calRaw >= 1000 ? calRaw ~/ 1000 : calRaw;
        final dist =
            (m['g'] as num?)?.toDouble() ??
            (m['distance'] as num?)?.toDouble() ??
            0.0;

        totalSteps += stepTotal;
        totalCal += cal;
        totalDist += dist;
        if (slot >= 0 && slot < 96) {
          stepSlots[slot] += stepTotal;
          calSlots[slot] += cal;
          distSlots[slot] += dist;
        }
      }

      if (totalSteps <= 0 && totalCal <= 0 && totalDist <= 0) return null;
      return _DaySnapshot(
        steps: totalSteps,
        cal: totalCal,
        distM: totalDist,
        stepSlots: stepSlots,
        calSlots: calSlots,
        distSlots: distSlots,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveToDb(DateTime date, int steps, int cal, double dist) async {
    if (steps <= 0 && cal <= 0) return;
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.upsertSteps(
        userId: user.id,
        date: _dateOnly(date),
        steps: steps,
        calories: cal,
        distanceM: dist,
      );
    } catch (_) {}
  }

  Future<_DaySnapshot?> _loadFromLocalDb() async {
    try {
      final decoded = jsonDecode(await _ble.getStepsToday());
      if (decoded is! Map<String, dynamic>) return null;
      final steps = (decoded['steps'] as num?)?.toInt() ?? 0;
      final cal = (decoded['caloriesKcal'] as num?)?.toInt() ?? 0;
      final dist = (decoded['distanceM'] as num?)?.toDouble() ?? 0.0;
      if (steps <= 0 && cal <= 0) return null;
      return _DaySnapshot(
        steps: steps,
        cal: cal,
        distM: dist,
        stepSlots: List<int>.from(_todayStepSlots),
        calSlots: List<int>.from(_todayCalSlots),
        distSlots: List<double>.from(_todayDistSlots),
      );
    } catch (_) {
      return null;
    }
  }

  Future<_DaySnapshot?> _loadFromRing(int dayIndex) async {
    try {
      final json = dayIndex == 0
          ? await _ble.getTodaySteps()
          : await _ble.getSteps(dayIndex);
      return _parseIntervalJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<_DaySnapshot?> _loadFromSupabase(DateTime date) async {
    final user = SupabaseService.currentUser;
    if (user == null) return null;
    final day = _dateOnly(date);
    final rows = await SupabaseService.getStepsHistory(
      userId: user.id,
      from: day,
      to: day,
    );
    if (rows.isEmpty) return _DaySnapshot.empty();
    final row = rows.first;
    return _DaySnapshot(
      steps: (row['steps'] as num? ?? 0).toInt(),
      cal: (row['calories'] as num? ?? 0).toInt(),
      distM: (row['distance_m'] as num? ?? 0.0).toDouble(),
      stepSlots: List.filled(96, 0),
      calSlots: List.filled(96, 0),
      distSlots: List.filled(96, 0.0),
    );
  }

  Future<void> _loadDay(DateTime date, {bool force = false}) async {
    if (!mounted) return;
    final day = _dateOnly(date);
    final key = _dateKey(day);
    final isToday = _isToday(day);
    final gen = ++_loadGen;

    final cached = _dayCache[key];
    if (cached != null && !force) {
      _applySnapshot(cached, isToday: isToday);
      setState(() {
        _dayLoad = false;
        _pastDayOffline = false;
      });
      return;
    }

    if (cached != null) {
      _applySnapshot(cached, isToday: isToday);
    } else if (!isToday) {
      setState(() {
        _daySteps = 0;
        _dayCal = 0;
        _dayDistM = 0.0;
        _stepsSlots = List.filled(96, 0);
        _calSlots = List.filled(96, 0);
        _distSlots = List.filled(96, 0.0);
      });
    }

    setState(() {
      _dayLoad = true;
      _pastDayOffline = false;
    });

    _DaySnapshot? snap;

    if (isToday) {
      final local = await _loadFromLocalDb();
      if (!mounted || gen != _loadGen) return;
      if (local != null) {
        snap = local;
        _applySnapshot(local, isToday: true);
      }

      final ring = await _loadFromRing(0);
      if (!mounted || gen != _loadGen) return;
      if (ring != null && ring.hasTotals) {
        snap = ring;
        _applySnapshot(ring, isToday: true);
        context.read<BleProvider>().updateStepsData(
          ring.steps,
          ring.cal,
          ring.distM,
          ring.stepSlots,
        );
        await _saveToDb(day, ring.steps, ring.cal, ring.distM);
      }
    } else {
      final dayIndex = _dayIndexFor(day);
      if (dayIndex > 0 && dayIndex <= 7) {
        final ring = await _loadFromRing(dayIndex);
        if (!mounted || gen != _loadGen) return;
        if (ring != null && ring.hasTotals) {
          snap = ring;
          _applySnapshot(ring, isToday: false);
          await _saveToDb(day, ring.steps, ring.cal, ring.distM);
        }
      }

      if (snap == null || !snap.hasTotals) {
        try {
          final cloud = await _loadFromSupabase(day);
          if (!mounted || gen != _loadGen) return;
          if (cloud != null) {
            if (snap != null && snap.hasIntervals && !cloud.hasIntervals) {
              snap = _DaySnapshot(
                steps: cloud.hasTotals ? cloud.steps : snap.steps,
                cal: cloud.hasTotals ? cloud.cal : snap.cal,
                distM: cloud.hasTotals ? cloud.distM : snap.distM,
                stepSlots: snap.stepSlots,
                calSlots: snap.calSlots,
                distSlots: snap.distSlots,
              );
            } else {
              snap = cloud;
            }
            _applySnapshot(snap, isToday: false);
          }
        } catch (e) {
          if (mounted && gen == _loadGen && isNetworkError(e)) {
            setState(() => _pastDayOffline = true);
          }
        }
      }
    }

    if (!mounted || gen != _loadGen) return;
    if (snap != null) {
      _dayCache[key] = snap;
    }
    setState(() => _dayLoad = false);
  }

  void _onDateSelected(DateTime date) {
    final day = _dateOnly(date);
    final today = _dateOnly(DateTime.now());
    if (day.isAfter(today)) return;
    if (_sameDay(_selectedDate, day)) return;

    setState(() {
      _selectedDate = day;
      _pastDayOffline = false;
    });

    final key = _dateKey(day);
    final cached = _dayCache[key];
    if (cached != null) {
      _applySnapshot(cached, isToday: _isToday(day));
    } else if (_isToday(day)) {
      setState(() {
        _daySteps = _totalSteps;
        _dayCal = _totalCal;
        _dayDistM = _totalDistM;
        _stepsSlots = List<int>.from(_todayStepSlots);
        _calSlots = List<int>.from(_todayCalSlots);
        _distSlots = List<double>.from(_todayDistSlots);
      });
    } else {
      setState(() {
        _daySteps = 0;
        _dayCal = 0;
        _dayDistM = 0.0;
        _stepsSlots = List.filled(96, 0);
        _calSlots = List.filled(96, 0);
        _distSlots = List.filled(96, 0.0);
      });
    }

    _loadDay(day, force: cached == null || _isToday(day));
  }

  // ── Display value getters ─────────────────────────────────────────────────

  int get _dispSteps => _daySteps;
  int get _dispCal => _dayCal;
  double get _dispDistM => _dayDistM;

  String get _dayLabel {
    if (_isToday(_selectedDate)) return 'Today';
    return '${_selectedDate.day} ${_monthAbbr[_selectedDate.month - 1]}';
  }

  bool get _loading => _dayLoad;

  // ── Three-dot menu ────────────────────────────────────────────────────────

  void _openMenu() {
    showGlassMenu(
      context: context,
      anchorKey: _moreButtonKey,
      items: [
        GlassMenuItem(label: 'Share', onTap: _shareScreenshot),
        GlassMenuItem(
          label: 'Goal setting',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CardSettingsScreen()),
          ),
        ),
      ],
    );
  }

  void _openActivityDescription() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ActivityDescriptionScreen()),
    );
  }

  Future<void> _shareScreenshot() =>
      shareScreenshot(_screenshotKey, text: 'My Activity — SUNDR');

  // ── Activity score ────────────────────────────────────────────────────────

  int get _activityScore {
    final avgSteps = _dispSteps.toDouble();
    final avgCal = _dispCal.toDouble();
    final avgDistM = _dispDistM;
    final s = (avgSteps / 8000 * 60).clamp(0.0, 60.0);
    final c = (avgCal / 250 * 25).clamp(0.0, 25.0);
    final d = (avgDistM / 5000 * 15).clamp(0.0, 15.0);
    return (s + c + d).round().clamp(0, 100);
  }

  String get _scoreLabel {
    final s = _activityScore;
    if (s == 0) return 'Lack of exercise';
    if (s < 25) return 'Sedentary';
    if (s < 50) return 'Lightly active';
    if (s < 75) return 'Moderately active';
    return 'Highly active';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _screenshotKey,
      child: Scaffold(
        backgroundColor: _kBg,
        appBar: AppBar(
          backgroundColor: _kBg,
          elevation: 0,
          centerTitle: true,
          leadingWidth: 70,
          leading: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: GlassBackButton(),
            ),
          ),
          title: Text('Activity', style: _t(17, w: FontWeight.w600)),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: KeyedSubtree(
                key: _moreButtonKey,
                child: GlassIconButton(
                  icon: Icons.more_vert_rounded,
                  iconSize: 18,
                  onTap: _openMenu,
                ),
              ),
            ),
          ],
        ),
        body: RefreshIndicator(
          color: const Color(0xFFC9A86E),
          backgroundColor: const Color(0xFF1C1C1C),
          onRefresh: () => _loadDay(_selectedDate, force: true),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Interactive date strip ───────────────────────────────────
                _DateStrip(
                  selectedDate: _selectedDate,
                  onDateSelected: _onDateSelected,
                ),
                Divider(
                  color: Colors.white.withValues(alpha: 0.06),
                  height: 0.5,
                  thickness: 0.5,
                ),

                if (_pastDayOffline && !_isToday(_selectedDate))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: const OfflineNotice(
                      message: 'Connect to WiFi to load this day\'s activity',
                    ),
                  ),

                // ── Activity Score ───────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                  child: GestureDetector(
                    onTap: _openActivityDescription,
                    behavior: HitTestBehavior.opaque,
                    child: _ActivityScore(
                      score: _activityScore,
                      label: _scoreLabel,
                      loading: _loading,
                    ),
                  ),
                ),

                // ── Workout and Sports link ──────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: GestureDetector(
                    onTap: () => Navigator.pushNamed(context, '/workouts'),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: _glass(),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFE08A4A,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.fitness_center_rounded,
                              color: Color(0xFFE08A4A),
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Workout and Sports',
                            style: _t(
                              14,
                              w: FontWeight.w500,
                              c: Colors.white.withValues(alpha: 0.95),
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white.withValues(alpha: 0.35),
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Stats row ────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: 'Total Steps',
                            value: _dispSteps > 0 ? '$_dispSteps' : '-- --',
                            color: _kStepsColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatCard(
                            label: 'Total Mileage',
                            value: _dispDistM > 0
                                ? '${(_dispDistM / 1000).toStringAsFixed(2)} km'
                                : '-- --',
                            color: _kDistColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatCard(
                            label: 'Total Calories',
                            value: _dispCal > 0 ? '$_dispCal' : '-- --',
                            color: _kCalColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Day charts ───────────────────────────────────────────────
                ...[
                  _chartPad(
                    _ChartCard(
                      title: 'STEPS',
                      subtitle: _dayLabel.toUpperCase(),
                      summary: _daySteps > 0 ? '$_daySteps steps' : '0 steps',
                      color: _kStepsColor,
                      values: _toHourlyInt(_stepsSlots),
                      xLabels: _hourXLabels,
                      loading: _loading,
                    ),
                  ),
                  _chartPad(
                    _ChartCard(
                      title: 'DISTANCE',
                      subtitle: _dayLabel.toUpperCase(),
                      summary: _dayDistM > 0
                          ? '${_dayDistM.toStringAsFixed(0)} m'
                          : '0 km',
                      color: _kDistColor,
                      values: _toHourlyDbl(_distSlots),
                      xLabels: _hourXLabels,
                      loading: _loading,
                    ),
                  ),
                  _chartPad(
                    _ChartCard(
                      title: 'CALORIES',
                      subtitle: _dayLabel.toUpperCase(),
                      summary: _dayCal > 0 ? '$_dayCal kcal' : '0 kcal',
                      color: _kCalColor,
                      values: _toHourlyInt(_calSlots),
                      xLabels: _hourXLabels,
                      loading: _loading,
                    ),
                  ),
                ],

                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chartPad(Widget child) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: child);

  List<double> _toHourlyInt(List<int> slots) => List.generate(
    24,
    (h) => slots.sublist(h * 4, h * 4 + 4).fold(0, (a, b) => a + b).toDouble(),
  );

  List<double> _toHourlyDbl(List<double> slots) => List.generate(
    24,
    (h) => slots.sublist(h * 4, h * 4 + 4).fold(0.0, (a, b) => a + b),
  );

  static const _hourXLabels = ['12am', '6am', '12pm', '6pm', '12am'];
}

// ── Date strip ────────────────────────────────────────────────────────────────

class _DateStrip extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;

  const _DateStrip({required this.selectedDate, required this.onDateSelected});

  @override
  State<_DateStrip> createState() => _DateStripState();
}

class _DateStripState extends State<_DateStrip> {
  static const int _pastDays = 6;
  static const int _futureDays = 3;
  static const int _itemCount = _pastDays + 1 + _futureDays;

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  @override
  void didUpdateWidget(covariant _DateStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameDay(oldWidget.selectedDate, widget.selectedDate)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime _dateAt(int index) => _today.add(Duration(days: index - _pastDays));

  int get _selectedIndex {
    final diff = _today
        .difference(
          DateTime(
            widget.selectedDate.year,
            widget.selectedDate.month,
            widget.selectedDate.day,
          ),
        )
        .inDays;
    return (_pastDays - diff).clamp(0, _itemCount - 1);
  }

  void _scrollToSelected() {
    if (!_scrollController.hasClients) return;
    const approxItemWidth = 56.0;
    final target =
        (_selectedIndex * approxItemWidth) -
        (_scrollController.position.viewportDimension / 2) +
        (approxItemWidth / 2);
    _scrollController.animateTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _itemCount,
        itemBuilder: (_, i) {
          final date = _dateAt(i);
          final isToday = i == _pastDays;
          final isSelected = _sameDay(date, widget.selectedDate);
          final isFuture = i > _pastDays;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: isFuture ? null : () => widget.onDateSelected(date),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  alignment: Alignment.center,
                  constraints: BoxConstraints(
                    minWidth: isSelected ? 96 : 44,
                    minHeight: 40,
                  ),
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: EdgeInsets.symmetric(
                    horizontal: isSelected ? 16 : 12,
                    vertical: 8,
                  ),
                  decoration: isSelected
                      ? BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                            width: 0.5,
                          ),
                        )
                      : null,
                  child: Text(
                    isSelected
                        ? (isToday
                              ? 'Today, ${date.day} ${_monthAbbr[date.month - 1]}'
                              : '${date.day} ${_monthAbbr[date.month - 1]}')
                        : '${date.day}',
                    style: _t(
                      isSelected ? 13 : 14,
                      w: isSelected ? FontWeight.w500 : FontWeight.w400,
                      c: isFuture
                          ? Colors.white.withValues(alpha: 0.18)
                          : isSelected
                          ? Colors.white.withValues(alpha: 0.95)
                          : Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Activity score ────────────────────────────────────────────────────────────

class _ActivityScore extends StatelessWidget {
  final int score;
  final String label;
  final bool loading;
  const _ActivityScore({
    required this.score,
    required this.label,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ACTIVITY SCORE',
          style: _t(
            10,
            w: FontWeight.w700,
            c: const Color(0xFFC9A86E),
            ls: 1.6,
          ),
        ),
        const SizedBox(height: 8),
        loading
            ? const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  color: Color(0xFFC9A86E),
                  strokeWidth: 2,
                ),
              )
            : Text(
                '$score',
                style: _t(
                  54,
                  w: FontWeight.w300,
                  c: Colors.white.withValues(alpha: 0.95),
                ),
              ),
        const SizedBox(height: 4),
        Text(label, style: _t(14, c: Colors.white.withValues(alpha: 0.55))),
      ],
    );
  }
}

// ── Stat card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _glass(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: _t(
              10,
              w: FontWeight.w500,
              c: Colors.white.withValues(alpha: 0.4),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: _t(
              18,
              w: FontWeight.w600,
              c: Colors.white.withValues(alpha: 0.95),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Chart card ────────────────────────────────────────────────────────────────

class _ChartCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final String summary;
  final Color color;
  final List<double> values;
  final List<String> xLabels;
  final bool loading;

  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.summary,
    required this.color,
    required this.values,
    required this.xLabels,
    required this.loading,
  });

  @override
  State<_ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<_ChartCard> {
  int? _selectedIndex;

  List<double> get _norm {
    if (widget.values.isEmpty) return [];
    final mx = widget.values.reduce((a, b) => a > b ? a : b);
    if (mx <= 0) return List.filled(widget.values.length, 0.0);
    return widget.values.map((v) => v / mx).toList();
  }

  void _handleTapOrDrag(Offset localPos, Size size) {
    if (widget.values.isEmpty) return;
    final n = widget.values.length;
    final slotW = size.width / n;
    int idx = (localPos.dx / slotW).floor();
    idx = idx.clamp(0, n - 1);
    if (_selectedIndex != idx) {
      setState(() {
        _selectedIndex = idx;
      });
    }
  }

  void _clearSelection() {
    if (_selectedIndex != null) {
      setState(() {
        _selectedIndex = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final norm = _norm;
    final hasData = norm.isNotEmpty && norm.any((v) => v > 0);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: _glass(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.title.toUpperCase(),
                style: _t(
                  11,
                  w: FontWeight.w700,
                  c: Colors.white.withValues(alpha: 0.9),
                  ls: 0.8,
                ),
              ),
              Text(
                widget.summary.toUpperCase(),
                style: _t(
                  11,
                  w: FontWeight.w700,
                  c: Colors.white.withValues(alpha: 0.9),
                  ls: 0.8,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Chart body
          SizedBox(
            height: 160,
            width: double.infinity,
            child: widget.loading
                ? Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: widget.color,
                        strokeWidth: 1.5,
                      ),
                    ),
                  )
                : !hasData
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bar_chart_rounded,
                          color: Colors.white.withValues(alpha: 0.13),
                          size: 28,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'No data',
                          style: _t(11, c: Colors.white.withValues(alpha: 0.3)),
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      return GestureDetector(
                        // Added LongPress explicitly for "click and hold" behavior
                        onLongPressStart: (details) =>
                            _handleTapOrDrag(details.localPosition, size),
                        onLongPressMoveUpdate: (details) =>
                            _handleTapOrDrag(details.localPosition, size),
                        onLongPressEnd: (_) => _clearSelection(),
                        onTapDown: (details) =>
                            _handleTapOrDrag(details.localPosition, size),
                        onTapUp: (_) => _clearSelection(),
                        onTapCancel: () => _clearSelection(),
                        // Using HorizontalDrag instead of Pan to allow vertical scrolling safely
                        onHorizontalDragStart: (details) =>
                            _handleTapOrDrag(details.localPosition, size),
                        onHorizontalDragUpdate: (details) =>
                            _handleTapOrDrag(details.localPosition, size),
                        onHorizontalDragEnd: (_) => _clearSelection(),
                        onHorizontalDragCancel: () => _clearSelection(),
                        child: CustomPaint(
                          size: size,
                          painter: _BarPainter(
                            values: norm,
                            rawValues: widget.values,
                            color: widget.color,
                            selectedIndex: _selectedIndex,
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // X-axis labels
          if (!widget.loading) ...[
            const SizedBox(height: 8),
            _XAxisRow(labels: widget.xLabels, count: widget.values.length),
          ],
        ],
      ),
    );
  }
}

// ── X-axis row ────────────────────────────────────────────────────────────────

class _XAxisRow extends StatelessWidget {
  final List<String> labels;
  final int count;
  const _XAxisRow({required this.labels, required this.count});

  @override
  Widget build(BuildContext context) {
    final toShow = labels.length <= 10 ? labels : _sparse(labels);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: toShow
          .map(
            (l) => Text(
              l,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 9,
              ),
            ),
          )
          .toList(),
    );
  }

  List<String> _sparse(List<String> all) {
    final step = (all.length / 6).ceil();
    final out = <String>[];
    for (int i = 0; i < all.length; i += step) {
      out.add(all[i]);
    }
    if (out.last != all.last) out.add(all.last);
    return out;
  }
}

// ── Bar chart painter ─────────────────────────────────────────────────────────

class _BarPainter extends CustomPainter {
  final List<double> values;
  final List<double> rawValues;
  final Color color;
  final int? selectedIndex;

  const _BarPainter({
    required this.values,
    required this.rawValues,
    required this.color,
    required this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final n = values.length;
    final slotW = size.width / n;
    final barW = n > 20
        ? (slotW * 0.6).clamp(1.5, 6.0)
        : (slotW * 0.6).clamp(6.0, 24.0);
    final padL = (slotW - barW) / 2;

    // Draw horizontal dashed grid lines (at 25%, 50%, 75% height)
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    for (int j = 1; j <= 3; j++) {
      final y = size.height * (j * 0.25);
      _drawDashedLine(
        canvas,
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
        4.0,
        3.0,
      );
    }

    // Draw bars
    for (int i = 0; i < n; i++) {
      if (values[i] <= 0) continue;
      final ratio = values[i];
      final barH = (ratio * size.height * 0.75).clamp(2.0, size.height * 0.75);
      final x = i * slotW + padL;
      final yTop = size.height - barH;

      // Select color based on ratio (as seen in Graphs-Activity.png)
      Color barColor;
      if (ratio >= 0.9) {
        barColor = const Color(0xFFC9A86E);
      } else if (ratio >= 0.65) {
        barColor = Colors.white.withValues(alpha: 0.85);
      } else {
        barColor = const Color(0xFF6BC99B);
      }

      if (selectedIndex == i) {
        barColor = barColor.withValues(alpha: 1.0);
      }

      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(x, yTop, x + barW, size.height),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        Paint()..color = barColor,
      );
    }

    // Draw tooltip
    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < values.length &&
        values[selectedIndex!] > 0) {
      final idx = selectedIndex!;
      final ratio = values[idx];
      final rawVal = rawValues[idx];
      final barH = (ratio * size.height * 0.75).clamp(2.0, size.height * 0.75);
      final xCenter = idx * slotW + padL + barW / 2;
      final yTop = size.height - barH;

      final valStr = _formatValue(rawVal);

      final textPainter = TextPainter(
        text: TextSpan(
          text: valStr,
          style: AppTypography.inter(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      const padX = 8.0;
      const padY = 4.0;
      final tooltipW = textPainter.width + padX * 2;
      final tooltipH = textPainter.height + padY * 2;

      double rectLeft = xCenter - tooltipW / 2;
      rectLeft = rectLeft.clamp(2.0, size.width - tooltipW - 2.0);

      double rectTop = yTop - tooltipH - 6.0;
      bool isBelow = false;

      // Ensure tooltip remains visible if space above is insufficient
      if (rectTop < 0) {
        rectTop = yTop + 6.0;
        isBelow = true;
      }

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(rectLeft, rectTop, tooltipW, tooltipH),
          const Radius.circular(6),
        ),
        Paint()..color = const Color(0xFF000000),
      );

      final path = Path();
      if (isBelow) {
        path.moveTo(xCenter - 4, rectTop);
        path.lineTo(xCenter + 4, rectTop);
        path.lineTo(xCenter, yTop + 2);
      } else {
        path.moveTo(xCenter - 4, rectTop + tooltipH);
        path.lineTo(xCenter + 4, rectTop + tooltipH);
        path.lineTo(xCenter, yTop - 2);
      }
      path.close();

      canvas.drawPath(path, Paint()..color = const Color(0xFF000000));

      textPainter.paint(canvas, Offset(rectLeft + padX, rectTop + padY));
    }
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset p1,
    Offset p2,
    Paint paint,
    double dashWidth,
    double dashSpace,
  ) {
    double distance = (p2 - p1).distance;
    int count = (distance / (dashWidth + dashSpace)).floor();
    for (int i = 0; i < count; i++) {
      double startFraction = (i * (dashWidth + dashSpace)) / distance;
      double endFraction = (startFraction + dashWidth / distance).clamp(
        0.0,
        1.0,
      );
      canvas.drawLine(
        Offset.lerp(p1, p2, startFraction)!,
        Offset.lerp(p1, p2, endFraction)!,
        paint,
      );
    }
  }

  String _formatValue(double val) {
    if (val == val.toInt().toDouble()) {
      return val.toInt().toString();
    }
    return val.toStringAsFixed(1);
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.values != values ||
      old.rawValues != rawValues ||
      old.color != color ||
      old.selectedIndex != selectedIndex;
}
