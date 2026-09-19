import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/incident_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/glass_icon_button.dart';
import '../../widgets/glass_menu.dart';
import '../../widgets/not_enough_data_card.dart';
import '../../widgets/offline_notice.dart';
import '../../widgets/screenshot_share.dart';
import '../settings/goal_setting_screen.dart';
import 'activity_description_screen.dart';
import '../../services/goal_prefs.dart';
import '../../services/health_engine/activity_engine.dart';
import '../../services/health_engine/health_engine.dart';
import '../../utils/date_keys.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/date_scroll_row.dart';
import '../../theme/app_theme.dart';
import '../../utils/hourly_aggregator.dart';
import '../../widgets/chart_scrubber.dart';

// ── Design tokens ───────────────────────────────────────────────────────────

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

  bool _isToday(DateTime d) => DateKeys.isToday(d);

  bool _sameDay(DateTime a, DateTime b) => DateKeys.sameDay(a, b);

  DateTime _dateOnly(DateTime d) => DateKeys.dateOnly(d);

  String _dateKey(DateTime d) => DateKeys.dateKey(d);

  int _dayIndexFor(DateTime d) => DateKeys.dayIndexFor(d);

  @override
  void initState() {
    super.initState();
    _selectedDate = _dateOnly(DateTime.now());
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    await _ensureGoals();
    if (!mounted) return;
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
      final dist = ActivityEngine.distributeSteps(curSteps, curCal, curDist, nowSlot);
      for (int i = 0; i < 96; i++) {
        stepSlots[i] = dist.stepSlots[i];
        calSlots[i] = dist.calSlots[i];
        distSlots[i] = dist.distSlots[i];
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
    // Ring-buffer backfill (dayIndex 0..6) in the background — persists
    // previous days the trend has never seen, then refreshes the view.
    unawaited(_pullRingHistory());
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
    final snap = ActivityEngine.parseIntervalJson(jsonStr);
    if (snap == null) return null;
    return _DaySnapshot(
      steps: snap.steps,
      cal: snap.cal,
      distM: snap.distM,
      stepSlots: snap.stepSlots,
      calSlots: snap.calSlots,
      distSlots: snap.distSlots,
    );
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
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'steps_screen',
        error: e,
        stackTrace: st,
        customMessage: '_saveToDb failed',
      );
    }
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
    final stepsCount = (row['steps'] as num? ?? 0).toInt();
    final rawCal = (row['calories'] as num? ?? 0).toInt();
    final cal = ActivityEngine.normalizeSupabaseCalories(rawCal, stepsCount);
    return _DaySnapshot(
      steps: stepsCount,
      cal: cal,
      distM: (row['distance_m'] as num? ?? 0.0).toDouble(),
      stepSlots: List.filled(96, 0),
      calSlots: List.filled(96, 0),
      distSlots: List.filled(96, 0.0),
    );
  }

  /// Pulls the ring's full 7-day buffer (getStepsList 0..6) and persists each
  /// day via the same parse+upsert path as single days, then refreshes the
  /// visible day. Best-effort and generation-guarded.
  Future<void> _pullRingHistory() async {
    final gen = _loadGen;
    bool alive() => mounted && gen == _loadGen;
    try {
      if (!context.read<BleProvider>().isConnected) return;
      final raw = await _ble.fetchRingHistory('steps');
      if (!alive()) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) return;
      final today = _dateOnly(DateTime.now());
      var wroteAny = false;
      for (final e in decoded) {
        if (e is! Map<String, dynamic>) continue;
        final dayIdx =
            (e['dayIndex'] as num? ?? e['day_index'] as num? ?? -1).toInt();
        if (dayIdx < 0 || dayIdx > 6) continue;
        final inner = e['data'];
        if (inner == null) continue;
        final snap = _parseIntervalJson(jsonEncode(inner));
        if (snap == null || !snap.hasTotals) continue;
        await _saveToDb(
          today.subtract(Duration(days: dayIdx)),
          snap.steps,
          snap.cal,
          snap.distM,
        );
        wroteAny = true;
        if (!alive()) return;
      }
      if (wroteAny && alive()) _loadDay(_selectedDate, force: true);
    } catch (_) {}
  }

  Future<void> _loadDay(DateTime date, {bool force = false}) async {    if (!mounted) return;
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

    // Cache-first: local/Supabase snapshots render immediately and clear the
    // spinner; the ring refresh runs in the background (bounded by the BLE
    // timeouts in BleService). Previously the page awaited ring calls before
    // showing anything, stalling on a dead ring.
    if (isToday) {
      final local = await _loadFromLocalDb();
      if (!mounted || gen != _loadGen) return;
      if (local != null) {
        snap = local;
        _applySnapshot(local, isToday: true);
        _dayCache[key] = local;
        setState(() => _dayLoad = false);
      }

      unawaited(() async {
        final ring = await _loadFromRing(0);
        if (!mounted || gen != _loadGen) return;
        if (ring != null && ring.hasTotals) {
          _applySnapshot(ring, isToday: true);
          try {
            context.read<BleProvider>().updateStepsData(
              ring.steps,
              ring.cal,
              ring.distM,
              ring.stepSlots,
            );
          } catch (_) {}
          await _saveToDb(day, ring.steps, ring.cal, ring.distM);
          _dayCache[key] = ring;
        }
        if (mounted && gen == _loadGen) setState(() => _dayLoad = false);
      }());
      return;
    }

    // Past day: Supabase first so scores show instantly…
    try {
      final cloud = await _loadFromSupabase(day);
      if (!mounted || gen != _loadGen) return;
      if (cloud != null) {
        snap = cloud;
        _applySnapshot(cloud, isToday: false);
        _dayCache[key] = cloud;
        setState(() => _dayLoad = false);
      }
    } catch (e) {
      if (mounted && gen == _loadGen && isNetworkError(e)) {
        setState(() => _pastDayOffline = true);
      }
    }

    // …then upgrade from the ring in the background (7-day on-device window).
    final dayIndex = _dayIndexFor(day);
    if (dayIndex > 0 && dayIndex <= 7) {
      unawaited(() async {
        final ring = await _loadFromRing(dayIndex);
        if (!mounted || gen != _loadGen) return;
        if (ring != null && ring.hasTotals) {
          _applySnapshot(ring, isToday: false);
          await _saveToDb(day, ring.steps, ring.cal, ring.distM);
          _dayCache[key] = ring;
        } else if (ring != null &&
            ring.hasIntervals &&
            snap != null &&
            !snap.hasIntervals) {
          final merged = _DaySnapshot(
            steps: snap.steps,
            cal: snap.cal,
            distM: snap.distM,
            stepSlots: ring.stepSlots,
            calSlots: ring.calSlots,
            distSlots: ring.distSlots,
          );
          _applySnapshot(merged, isToday: false);
          _dayCache[key] = merged;
        }
        if (mounted && gen == _loadGen) setState(() => _dayLoad = false);
      }());
      return;
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
            MaterialPageRoute(builder: (_) => const GoalSettingScreen()),
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

  // ── Activity score — goal-aware via HealthEngine ─────────────────────
  // Keeps a cached GoalTargets to stay sync in build; refresh on pull-to-refresh & resume.
  GoalTargets? _goals;
  Future<void> _ensureGoals() async {
    _goals ??= await GoalPrefs.load();
  }

  int get _activityScore {
    final goals = _goals ??
        const GoalTargets(steps: 10000, calories: 1000, distanceKm: 5.0, sleepStartMin: 1260, sleepEndMin: 300);
    // If still default placeholder and last remote config has different fallback, merge:
    // _goals will be overwritten after first _ensureGoals completes, build will repaint.
    return HealthEngine.instance.calcActivityScoreWithGoals(
      steps: _dispSteps,
      calories: _dispCal,
      distanceM: _dispDistM,
      goals: goals,
    );
  }

  String get _scoreLabel => HealthEngine.instance.activityLabel(_activityScore);

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _screenshotKey,
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(
          backgroundColor: AppTheme.bg,
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
          color: AppTheme.gold,
          backgroundColor: const Color(0xFF1C1C1C),
          onRefresh: () => _loadDay(_selectedDate, force: true),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Interactive date strip ───────────────────────────────────
                DateScrollRow(
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
                              color: AppTheme.focus,
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

                // ── Daily section — collapse to single card when empty ──────
                if (_daySteps == 0 && _dayCal == 0 && _dayDistM == 0 && !_pastDayOffline)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: NotEnoughDataCard(
                      metric: 'activity',
                      date: _selectedDate,
                      loading: _dayLoad,
                      isConnected: (() {
                        try {
                          return context.read<BleProvider>().isConnected;
                        } catch (_) {
                          return false;
                        }
                      })(),
                    ),
                  )
                else ...[
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
                              color: AppTheme.softGreen,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _StatCard(
                              label: 'Total Mileage',
                              value: _dispDistM > 0
                                  ? '${(_dispDistM / 1000).toStringAsFixed(2)} km'
                                  : '-- --',
                              color: AppTheme.softBlue,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _StatCard(
                              label: 'Total Calories',
                              value: _dispCal > 0 ? '$_dispCal' : '-- --',
                              color: AppTheme.softOrange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Day charts ───────────────────────────────────────────────
                  _chartPad(
                    _ChartCard(
                      title: 'STEPS',
                      subtitle: _dayLabel.toUpperCase(),
                      summary: _daySteps > 0 ? '$_daySteps steps' : '0 steps',
                      color: AppTheme.softGreen,
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
                      color: AppTheme.softBlue,
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
                      color: AppTheme.softOrange,
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

  List<double> _toHourlyInt(List<int> slots) => HourlyAggregator.toHourlyInt(slots);

  List<double> _toHourlyDbl(List<double> slots) => HourlyAggregator.toHourlyDouble(slots);

  // Keep ActivityEngine.normalizeCalories wiring (used via parseIntervalJson delegation)
  // ignore: unused_element
  int _demoNormalize(int raw) => ActivityEngine.normalizeCalories(raw, 0);
  // ignore: unused_element
  DaySnapshot? _demoParse(String jsonStr) {
    return ActivityEngine.parseIntervalJson(jsonStr);
  }

  static const _hourXLabels = ['12am', '6am', '12pm', '6pm', '12am'];
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
            c: AppTheme.gold,
            ls: 1.6,
          ),
        ),
        const SizedBox(height: 8),
        loading
            ? const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  color: AppTheme.gold,
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
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = _initialIndex();
  }

  @override
  void didUpdateWidget(covariant _ChartCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.values != widget.values) {
      final newIdx = _initialIndex();
      if (newIdx != _selectedIndex) {
        _selectedIndex = newIdx.clamp(0, (widget.values.length - 1).clamp(0, 999));
      } else if (_selectedIndex >= widget.values.length) {
        _selectedIndex = (widget.values.length - 1).clamp(0, 999);
      }
    }
  }

  int _initialIndex() {
    if (widget.values.isEmpty) return 0;
    for (int i = widget.values.length - 1; i >= 0; i--) {
      if (widget.values[i] > 0) return i;
    }
    return 0;
  }

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
                        onLongPressStart: (details) =>
                            _handleTapOrDrag(details.localPosition, size),
                        onLongPressMoveUpdate: (details) =>
                            _handleTapOrDrag(details.localPosition, size),
                        onTapDown: (details) =>
                            _handleTapOrDrag(details.localPosition, size),
                        onHorizontalDragStart: (details) =>
                            _handleTapOrDrag(details.localPosition, size),
                        onHorizontalDragUpdate: (details) =>
                            _handleTapOrDrag(details.localPosition, size),
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
            if (hasData) ...[
              const SizedBox(height: 14),
              ChartScrubber(
                itemCount: widget.values.length,
                selectedIndex: _selectedIndex,
                accent: widget.color,
                enabled: !widget.loading,
                onChanged: (idx) {
                  setState(() => _selectedIndex = idx);
                },
              ),
            ],
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
        barColor = AppTheme.gold;
      } else if (ratio >= 0.65) {
        barColor = Colors.white.withValues(alpha: 0.85);
      } else {
        barColor = AppTheme.stressColor;
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
        Paint()..color = Colors.black,
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

      canvas.drawPath(path, Paint()..color = Colors.black);

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
