import 'dart:async';
import 'dart:convert';
import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../providers/workout_provider.dart';
import '../../models/workout_model.dart';
import '../../services/ble_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/offline_notice.dart';
import '../../widgets/glass_back_button.dart';
import 'active_workout_screen.dart';
import 'workout_detail_screen.dart';
import '../../widgets/app_typography.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _kBg     = Color(0xFF080808);
const _kSec    = Color(0xFF555555);

TextStyle _inter(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = Colors.white,
  double? letterSpacing,
  double? height,
}) =>
    AppTypography.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );

// ── Screen ────────────────────────────────────────────────────────────────────

class WorkoutsScreen extends StatefulWidget {
  const WorkoutsScreen({super.key});
  @override
  State<WorkoutsScreen> createState() => _WorkoutsScreenState();
}

class _WorkoutsScreenState extends State<WorkoutsScreen> {
  final _ble = BleService();
  List<Map<String, dynamic>> _history = [];
  bool _loadingHistory = false;
  bool _wasWorkoutActive = false;
  bool _historyOffline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHistory();
      // Ring auto-detected sports (getSports 0..6) merge in the background —
      // cache-first so the page never waits on the ring.
      unawaited(_pullRingSports());
    });
  }

  Future<void> _loadHistory() async {
    setState(() { _loadingHistory = true; _historyOffline = false; });
    try {
      final workoutProvider = context.read<WorkoutProvider>();
      final localData = await workoutProvider.getLocalWorkouts();
      List<Map<String, dynamic>> supabaseData = [];

      final userId = SupabaseService.currentUser?.id;
      if (userId != null) {
        try {
          final now = DateTime.now();
          supabaseData = await SupabaseService.getWorkoutHistory(
            userId: userId,
            from: now.subtract(const Duration(days: 90)),
            to: now,
          );
        } catch (e) {
          if (mounted) {
            setState(() { _historyOffline = isNetworkError(e); });
          }
        }
      }

      final Map<String, Map<String, dynamic>> merged = {};
      for (final item in [...localData, ...supabaseData]) {
        final key = item['id']?.toString() ?? item['started_at']?.toString() ?? '';
        if (key.isNotEmpty) {
          merged[key] = item;
        }
      }

      final result = merged.values.toList();
      result.sort((a, b) {
        final tA = a['started_at']?.toString() ?? '';
        final tB = b['started_at']?.toString() ?? '';
        return tB.compareTo(tA);
      });

      if (mounted) {
        setState(() {
          _history = result;
          _loadingHistory = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  /// Ring auto-detected sport sessions (SportPlusType ids) → app sport names.
  /// Names match WorkoutModel sports so categories/icons/metrics resolve.
  static String _ringSportName(int t) => switch (t) {
        1 => 'GPS Running',
        2 || 9 || 13 => 'Cycling',
        3 || 8 || 14 => 'Walking',
        5 => 'Jump Rope',
        6 => 'Swimming',
        10 => 'Strength Training',
        11 => 'Outdoor Sports',
        _ => 'Running',
      };

  /// Normalizes one SportPlusEntity into a history-row shape. Returns null
  /// when the session has no usable start/duration.
  static Map<String, dynamic>? _ringSportRow(Map<String, dynamic> s) {
    final type = (s['mSportType'] as num? ?? 0).toInt();
    var startMs = (s['mStartTime'] as num? ?? 0).toInt();
    // mStartTime is epoch seconds; tolerate millis just in case.
    if (startMs > 0 && startMs < 100000000000) startMs *= 1000;
    final durS = (s['mDuration'] as num? ?? 0).toInt();
    if (startMs <= 0 || durS <= 0) return null;
    final start = DateTime.fromMillisecondsSinceEpoch(startMs);
    final end = start.add(Duration(seconds: durS));
    // mCalories unit is firmware-dependent: real sessions never reach
    // 10000 kcal, so anything at/above that is 小卡 (÷1000, min 1).
    final calRaw = (s['mCalories'] as num? ?? 0).toDouble();
    final calories =
        calRaw >= 10000 ? (calRaw ~/ 1000).clamp(1, 1 << 31) : calRaw.toInt();
    return {
      'id': 'ring-$startMs-$type',
      'workout_type': _ringSportName(type),
      'started_at': start.toIso8601String(),
      'ended_at': end.toIso8601String(),
      'duration_s': durS,
      'steps': (s['steps'] as num? ?? 0).toInt(),
      'calories': calories,
      'distance_m': (s['mDistance'] as num? ?? 0).toDouble(),
      'avg_hr': (s['mRateAvg'] as num? ?? 0).toInt(),
      'source': 'ring',
    };
  }

  static int _epochSec(String? iso) {
    final dt = DateTime.tryParse(iso ?? '');
    if (dt == null) return -1;
    return dt.millisecondsSinceEpoch ~/ 1000;
  }

  /// Auto-invoked sport sync: pulls the ring's sport buffer (getSports 0..6),
  /// merges unseen auto-detected sessions into history with a RING badge, and
  /// persists them to Supabase so they track across devices. Best-effort and
  /// silent when the ring is unreachable.
  Future<void> _pullRingSports() async {
    try {
      if (!context.read<BleProvider>().isConnected) return;
      final raw = await _ble.fetchRingHistory('sport');
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) return;
      if (!mounted) return;
      final ringRows = <Map<String, dynamic>>[];
      for (final e in decoded) {
        if (e is! Map<String, dynamic>) continue;
        final inner = e['data'];
        final List<dynamic> sessions;
        if (inner is List) {
          sessions = inner;
        } else if (inner is Map<String, dynamic>) {
          sessions = [inner];
        } else {
          continue;
        }
        for (final s in sessions) {
          if (s is! Map<String, dynamic>) continue;
          final row = _ringSportRow(s);
          if (row != null) ringRows.add(row);
        }
      }
      if (ringRows.isEmpty || !mounted) return;

      // Dedupe against what's already shown (manual + cloud) by start second —
      // app-started sessions (TYPE_APP_*) overlap manual entries.
      final knownStarts = <int>{
        for (final h in _history) _epochSec(h['started_at'] as String?),
      };
      final fresh =
          ringRows.where((r) => !knownStarts.contains(_epochSec(r['started_at'] as String?))).toList();
      if (fresh.isEmpty || !mounted) return;

      // Persist unseen sessions so auto-detected sports track in history.
      final userId = SupabaseService.currentUser?.id;
      if (userId != null) {
        var insertErrors = 0;
        for (final r in fresh) {
          try {
            final startedAt = DateTime.parse(r['started_at'] as String);
            await SupabaseService.insertWorkout(
              userId: userId,
              type: r['workout_type'] as String,
              startedAt: startedAt,
              endedAt: DateTime.parse(r['ended_at'] as String),
              durationS: (r['duration_s'] as num).toInt(),
              steps: (r['steps'] as num).toInt(),
              calories: (r['calories'] as num).toInt(),
              distanceM: (r['distance_m'] as num).toDouble(),
              avgHr: (r['avg_hr'] as num).toInt(),
              avgSpo2: 0,
              avgBpSbp: 0,
              avgBpDbp: 0,
            );
          } catch (e) {
            insertErrors++;
            debugPrint('[Workouts] ring insert failed: $e');
          }
          if (!mounted) return;
        }
        if (insertErrors == fresh.length && fresh.isNotEmpty && mounted) {
          // All inserts failed — still show ring rows locally this session.
          debugPrint('[Workouts] all ${fresh.length} ring inserts failed');
        }
      }

      if (!mounted) return;
      setState(() {
        final merged = <String, Map<String, dynamic>>{};
        for (final item in [..._history, ...fresh]) {
          final key = item['id']?.toString() ?? item['started_at']?.toString() ?? '';
          if (key.isNotEmpty) merged[key] = item;
        }
        final result = merged.values.toList();
        result.sort((a, b) {
          final tA = a['started_at']?.toString() ?? '';
          final tB = b['started_at']?.toString() ?? '';
          return tB.compareTo(tA);
        });
        _history = result;
      });
    } catch (_) {}
  }

  static String _dateHeader(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const weekdays = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${weekdays[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}';
  }

  List<Widget> _buildGroupedHistory(List<Map<String, dynamic>> rows) {
    final widgets = <Widget>[];
    String? lastKey;
    for (final row in rows) {
      final dtStr = row['started_at'] as String?;
      if (dtStr == null) continue;
      final dt = DateTime.tryParse(dtStr)?.toLocal();
      if (dt == null) continue;

      final key = '${dt.year}${dt.month.toString().padLeft(2,'0')}${dt.day.toString().padLeft(2,'0')}';
      if (key != lastKey) {
        if (lastKey != null) widgets.add(const SizedBox(height: 4));
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              _dateHeader(dt),
              style: _inter(11, weight: FontWeight.w600, color: AppTheme.textSec, letterSpacing: 0.6),
            ),
          ),
        );
        lastKey = key;
      }
      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _HistoryRow(row: row),
        ),
      );
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Consumer<WorkoutProvider>(
        builder: (context, workout, _) {
          if (_wasWorkoutActive && !workout.isWorkoutActive) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _loadHistory());
          }
          _wasWorkoutActive = workout.isWorkoutActive;

          return SafeArea(
            child: RefreshIndicator(
              onRefresh: _loadHistory,
              color: AppTheme.gold,
              backgroundColor: AppTheme.card,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // ── Header ─────────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const GlassBackButton(),
                              const SizedBox(width: 14),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Workouts',
                                      style: _inter(28, weight: FontWeight.w700)),
                                  Text('Track your fitness journey',
                                      style: _inter(13, color: AppTheme.textSec)),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),

                  // ── Active banner ───────────────────────────────────────────
                  if (workout.isWorkoutActive)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        child: _ActiveBanner(workout: workout),
                      ),
                    ),

                  // ── Categories grid ─────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'START WORKOUT',
                                style: _inter(11,
                                    weight: FontWeight.w700,
                                    color: AppTheme.textSec,
                                    letterSpacing: 1.4),
                              ),
                              if (workout.isWorkoutActive) ...[
                                const Spacer(),
                                Text('finish active first',
                                    style: _inter(11, color: _kSec)),
                              ],
                            ],
                          ),
                          const SizedBox(height: 14),
                          GridView.count(
                            crossAxisCount: 4,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 0.80,
                            children: WorkoutCategory.values.map((cat) {
                              return _CategoryGridItem(
                                category: cat,
                                locked: workout.isWorkoutActive,
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 28),
                        ],
                      ),
                    ),
                  ),

                  // ── Section divider ─────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      height: 0.5,
                      color: AppTheme.div,
                    ),
                  ),

                  // ── History header ──────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "TODAY'S WORKOUTS",
                            style: _inter(11,
                                weight: FontWeight.w700,
                                color: AppTheme.textSec,
                                letterSpacing: 1.4),
                          ),
                          if (_history.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.card,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppTheme.div),
                              ),
                              child: Text(
                                '${_history.length}',
                                style: _inter(11,
                                    weight: FontWeight.w600, color: AppTheme.textSec),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // ── History content ─────────────────────────────────────────
                  if (_loadingHistory)
                    const SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: CircularProgressIndicator(
                              color: AppTheme.gold, strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (_history.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _historyOffline
                            ? const OfflineNotice(message: 'Connect to WiFi to load workout history')
                            : _EmptyWorkouts(),
                      ),
                    )
                  else ...[
                    // Horizontal spotlight cards — 3 most recent
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 164,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: min(_history.length, 3),
                          itemBuilder: (_, i) =>
                              _SpotlightCard(row: _history[i]),
                        ),
                      ),
                    ),

                    // Grouped history list — everything after the first 3
                    if (_history.length > 3) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                          child: Text(
                            'HISTORY',
                            style: _inter(11,
                                weight: FontWeight.w700,
                                color: AppTheme.textSec,
                                letterSpacing: 1.4),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children:
                              _buildGroupedHistory(_history.sublist(3)),
                        ),
                      ),
                    ],
                  ],

                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Active Banner ─────────────────────────────────────────────────────────────

class _ActiveBanner extends StatelessWidget {
  final WorkoutProvider workout;
  const _ActiveBanner({required this.workout});

  String _fmt(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final label =
        workout.currentSport ?? workout.currentCategory?.label ?? 'Workout';
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ActiveWorkoutScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.goldBorder,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.gold.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                  color: AppTheme.danger, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$label in progress',
                    style: _inter(12,
                        weight: FontWeight.w600, color: AppTheme.gold),
                  ),
                  Text(_fmt(workout.elapsedSeconds),
                      style: _inter(20, weight: FontWeight.w300)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.gold, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Category Grid Item ────────────────────────────────────────────────────────

class _CategoryGridItem extends StatelessWidget {
  final WorkoutCategory category;
  final bool locked;
  const _CategoryGridItem({required this.category, this.locked = false});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: locked ? 0.4 : 1.0,
      child: GestureDetector(
        onTap: locked ? null : () => _showSportPicker(context),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.div),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.goldBorder,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(category.icon, color: AppTheme.gold, size: 20),
              ),
              const SizedBox(height: 7),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Text(
                  category.label,
                  style: _inter(9.5, weight: FontWeight.w500),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSportPicker(BuildContext context) {
    final nav = Navigator.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => _SportPickerSheet(
        category: category,
        onSportSelected: (sport) {
          Navigator.pop(sheetCtx);
          showModalBottomSheet(
            context: context,
            backgroundColor: AppTheme.card,
            isScrollControlled: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            builder: (_) => _PreStartSheet(
              category: category,
              sport: sport,
              onWorkoutStarted: () => nav.push(
                MaterialPageRoute(
                    builder: (_) => const ActiveWorkoutScreen()),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Spotlight Card ────────────────────────────────────────────────────────────

class _SpotlightCard extends StatelessWidget {
  final Map<String, dynamic> row;
  const _SpotlightCard({required this.row});

  static String _fmtDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  static String _fmtDate(String isoString) {
    final dt = DateTime.parse(isoString).toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = h < 12 ? 'AM' : 'PM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final time = '$h12:$m $ampm';
    if (diff == 0) return 'Today • $time';
    if (diff == 1) return 'Yesterday • $time';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day} • $time';
  }

  @override
  Widget build(BuildContext context) {
    final type       = (row['workout_type'] as String? ?? 'running');
    final startedAt  = row['started_at'] as String? ?? '';
    final durationS  = (row['duration_s'] as num? ?? 0).toInt();
    final calories   = (row['calories'] as num? ?? 0).toInt();
    final avgHr      = (row['avg_hr'] as num? ?? 0).toInt();
    final distanceM  = (row['distance_m'] as num? ?? 0.0).toDouble();

    final category = workoutCategoryFromString(type);
    final icon  = category?.icon ?? Icons.fitness_center_rounded;
    final label = type.isNotEmpty
        ? '${type[0].toUpperCase()}${type.substring(1)}'
        : 'Workout';

    return GestureDetector(
      onTap: () => _showWorkoutDetailSheet(context, row),
      child: Container(
        width: 152,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.div),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.goldBorder,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppTheme.gold, size: 18),
            ),
            const SizedBox(height: 10),
            // Name
            Text(
              label,
              style: _inter(12, weight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // Date
            Text(
              startedAt.isNotEmpty ? _fmtDate(startedAt) : '',
              style: _inter(9.5, color: AppTheme.textSec),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            // Duration — prominent
            Text(
              _fmtDuration(durationS),
              style: _inter(22, weight: FontWeight.w700, color: AppTheme.gold),
            ),
            const SizedBox(height: 6),
            // Mini stats row
            Row(
              children: [
                if (avgHr > 0) ...[
                  Icon(Icons.monitor_heart_rounded,
                      color: AppTheme.hrColor, size: 11),
                  const SizedBox(width: 2),
                  Text('$avgHr',
                      style: _inter(10,
                          weight: FontWeight.w600, color: AppTheme.textSec)),
                  const SizedBox(width: 6),
                ],
                if (calories > 0) ...[
                  const Icon(Icons.local_fire_department_rounded,
                      color: AppTheme.warmOrange, size: 11),
                  const SizedBox(width: 2),
                  Text('$calories',
                      style: _inter(10,
                          weight: FontWeight.w600, color: AppTheme.textSec)),
                  const SizedBox(width: 6),
                ],
                if (distanceM > 0) ...[
                  Icon(Icons.straighten_rounded,
                      color: AppTheme.success, size: 11),
                  const SizedBox(width: 2),
                  Text(
                    distanceM >= 1000
                        ? '${(distanceM / 1000).toStringAsFixed(1)}k'
                        : '${distanceM.toStringAsFixed(0)}m',
                    style: _inter(10,
                        weight: FontWeight.w600, color: AppTheme.textSec),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── History Row (grouped list) ────────────────────────────────────────────────

class _HistoryRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _HistoryRow({required this.row});

  static String _fmtDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  static String _fmtTime(String iso) {
    final dt = DateTime.parse(iso).toLocal();
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = h < 12 ? 'AM' : 'PM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$m $ampm';
  }

  static String _fmtSteps(int steps) =>
      steps >= 1000 ? '${(steps / 1000).toStringAsFixed(1)}k steps' : '$steps steps';

  static String _fmtDist(double m) {
    if (m <= 0) return '';
    return m >= 1000
        ? '${(m / 1000).toStringAsFixed(2)} km'
        : '${m.toStringAsFixed(0)} m';
  }

  @override
  Widget build(BuildContext context) {
    final type      = (row['workout_type'] as String? ?? 'running');
    final startedAt = row['started_at'] as String? ?? '';
    final durationS = (row['duration_s'] as num? ?? 0).toInt();
    final steps     = (row['steps'] as num? ?? 0).toInt();
    final calories  = (row['calories'] as num? ?? 0).toInt();
    final distanceM = (row['distance_m'] as num? ?? 0.0).toDouble();
    final avgHr     = (row['avg_hr'] as num? ?? 0).toInt();

    final category = workoutCategoryFromString(type);
    final icon     = category?.icon ?? Icons.fitness_center_rounded;
    final label    = type.isNotEmpty
        ? '${type[0].toUpperCase()}${type.substring(1)}'
        : 'Workout';

    // Show any stat the ring actually recorded — category metric lists
    // would otherwise hide valid steps/distance for non-running sports.
    final stats = <(IconData, Color, String)>[];
    if (avgHr > 0) {
      stats.add((Icons.monitor_heart_rounded, AppTheme.hrColor, '$avgHr bpm'));
    }
    if (steps > 0) {
      stats.add((Icons.directions_walk_rounded, AppTheme.gold, _fmtSteps(steps)));
    }
    if (distanceM > 0) {
      stats.add((Icons.straighten_rounded, AppTheme.success, _fmtDist(distanceM)));
    }
    if (calories > 0) {
      stats.add((Icons.local_fire_department_rounded,
          AppTheme.warmOrange, '$calories kcal'));
    }

    return GestureDetector(
      onTap: () => _showWorkoutDetailSheet(context, row),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.div),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppTheme.goldBorder,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: AppTheme.gold, size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(label,
                                style: _inter(14, weight: FontWeight.w600)),
                          ),
                          if (row['source'] == 'ring') ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.goldBorder,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: AppTheme.gold
                                        .withValues(alpha: 0.35)),
                              ),
                              child: Text('RING',
                                  style: _inter(9,
                                      weight: FontWeight.w700,
                                      color: AppTheme.gold)),
                            ),
                          ],
                        ],
                      ),
                      if (startedAt.isNotEmpty)
                        Text(_fmtTime(startedAt),
                            style: _inter(11, color: AppTheme.textSec)),
                    ],
                  ),
                ),
                Text(
                  _fmtDuration(durationS),
                  style: _inter(14,
                      weight: FontWeight.w700, color: AppTheme.gold),
                ),
              ],
            ),
            if (stats.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: stats
                    .map((s) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(s.$1, color: s.$2, size: 12),
                            const SizedBox(width: 3),
                            Text(s.$3, style: _inter(11, color: AppTheme.textSec)),
                          ],
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Detail Sheet ─────────────────────────────────────────────────────────────

void _showWorkoutDetailSheet(BuildContext context, Map<String, dynamic> row) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => WorkoutDetailScreen(row: row),
    ),
  );
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyWorkouts extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.div),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.goldBorder,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.directions_run_rounded,
                color: AppTheme.gold, size: 28),
          ),
          const SizedBox(height: 16),
          Text('No workouts yet',
              style: _inter(15, weight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            'Start a workout above to see\nyour history here',
            style: _inter(12, color: AppTheme.textSec, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Sport picker sheet ────────────────────────────────────────────────────────

class _SportPickerSheet extends StatelessWidget {
  final WorkoutCategory category;
  final ValueChanged<String> onSportSelected;
  const _SportPickerSheet(
      {required this.category, required this.onSportSelected});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.div,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.goldBorder,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child:
                          Icon(category.icon, color: AppTheme.gold, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            category.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${category.sports.length} activities',
                            style: const TextStyle(
                              color: AppTheme.textSec,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: AppTheme.div, height: 1),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: category.sports.length,
              shrinkWrap: true,
              itemBuilder: (_, i) {
                final sport = category.sports[i];
                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  title: Text(
                    sport,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.textSec,
                    size: 20,
                  ),
                  onTap: () => onSportSelected(sport),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Pre-start sheet ───────────────────────────────────────────────────────────

class _PreStartSheet extends StatefulWidget {
  final WorkoutCategory category;
  final String sport;
  final VoidCallback onWorkoutStarted;
  const _PreStartSheet({
    required this.category,
    required this.sport,
    required this.onWorkoutStarted,
  });

  @override
  State<_PreStartSheet> createState() => _PreStartSheetState();
}

class _PreStartSheetState extends State<_PreStartSheet> {
  bool _starting = false;

  String _metricsDescription() {
    const names = {
      WorkoutMetric.heartRate: 'heart rate',
      WorkoutMetric.steps: 'steps',
      WorkoutMetric.distance: 'distance',
      WorkoutMetric.calories: 'calories',
    };
    const order = [
      WorkoutMetric.heartRate,
      WorkoutMetric.steps,
      WorkoutMetric.distance,
      WorkoutMetric.calories,
    ];
    final active = order
        .where((m) => widget.category.metrics.contains(m))
        .map((m) => names[m]!)
        .toList();
    final joined = active.length == 1
        ? active.first
        : '${active.sublist(0, active.length - 1).join(', ')} & ${active.last}';
    return '${joined[0].toUpperCase()}${joined.substring(1)} polled from ring every 20 seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24, 24, 24, 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.div,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.goldBorder,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(widget.category.icon,
                    color: AppTheme.gold, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.sport,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      widget.category.label,
                      style: const TextStyle(
                          color: AppTheme.textSec, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'What happens during your workout:',
            style: TextStyle(
              color: AppTheme.textSec,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          ...[
            (Icons.timer_rounded, 'Timer starts immediately'),
            (Icons.monitor_heart_rounded, _metricsDescription()),
            (Icons.lock_rounded,
                'Other app features are paused until you finish'),
          ].map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(e.$1, color: AppTheme.gold, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      e.$2,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _starting
                  ? null
                  : () async {
                      setState(() => _starting = true);
                      final workout = context.read<WorkoutProvider>();
                      final nav = Navigator.of(context);
                      await workout.startWorkout(
                          widget.category, widget.sport);
                      if (!mounted) return;
                      nav.pop();
                      widget.onWorkoutStarted();
                    },
              child: _starting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.black, strokeWidth: 2.5),
                    )
                  : const Text(
                      'Start Workout',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
