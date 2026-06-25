import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/workout_provider.dart';
import '../../models/workout_model.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import 'active_workout_screen.dart';

class WorkoutsScreen extends StatefulWidget {
  const WorkoutsScreen({super.key});
  @override
  State<WorkoutsScreen> createState() => _WorkoutsScreenState();
}

class _WorkoutsScreenState extends State<WorkoutsScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _loadingHistory = false;
  bool _wasWorkoutActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadHistory());
  }

  Future<void> _loadHistory() async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) return;
    setState(() => _loadingHistory = true);
    try {
      final now = DateTime.now();
      final data = await SupabaseService.getWorkoutHistory(
        userId: userId,
        from: now.subtract(const Duration(days: 90)),
        to: now,
      );
      if (mounted) setState(() { _history = data; _loadingHistory = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
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
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 80),
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 4),
                    child: Text(
                      'Workouts',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 20),
                    child: Text(
                      'Choose a category to start tracking',
                      style: TextStyle(color: AppTheme.textSec, fontSize: 14),
                    ),
                  ),
                  if (workout.isWorkoutActive) _ActiveBanner(workout: workout),
                  ...WorkoutCategory.values.map(
                    (cat) => _CategoryCard(category: cat, locked: workout.isWorkoutActive),
                  ),
                  const SizedBox(height: 28),
                  _HistorySection(history: _history, loading: _loadingHistory),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Active workout banner ────────────────────────────────────────────────────

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
    final label = workout.currentSport ?? workout.currentCategory?.label ?? 'Workout';
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ActiveWorkoutScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.goldBorder,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.gold.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.circle, color: AppTheme.danger, size: 8),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$label in progress',
                    style: const TextStyle(
                      color: AppTheme.gold,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _fmt(workout.elapsedSeconds),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 18, fontWeight: FontWeight.w300),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.gold),
          ],
        ),
      ),
    );
  }
}

// ── Category card ────────────────────────────────────────────────────────────

class _CategoryCard extends StatelessWidget {
  final WorkoutCategory category;
  final bool locked;
  const _CategoryCard({required this.category, this.locked = false});

  String _metricsSubtitle() {
    const names = {
      WorkoutMetric.heartRate: 'heart rate',
      WorkoutMetric.steps: 'steps',
      WorkoutMetric.distance: 'distance',
      WorkoutMetric.calories: 'calories',
    };
    // Keep a consistent display order
    const order = [
      WorkoutMetric.heartRate,
      WorkoutMetric.steps,
      WorkoutMetric.distance,
      WorkoutMetric.calories,
    ];
    final active = order
        .where((m) => category.metrics.contains(m))
        .map((m) => names[m]!)
        .toList();
    if (active.length == 1) return active.first;
    return '${active.sublist(0, active.length - 1).join(', ')} & ${active.last}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.div),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppTheme.goldBorder,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(category.icon, color: AppTheme.gold, size: 26),
        ),
        title: Text(
          category.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          '${category.sports.length} activities • ${_metricsSubtitle()}',
          style: const TextStyle(color: AppTheme.textSec, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textSec),
        onTap: locked ? null : () => _showSportPicker(context),
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
                MaterialPageRoute(builder: (_) => const ActiveWorkoutScreen()),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Sport picker sheet ───────────────────────────────────────────────────────

class _SportPickerSheet extends StatelessWidget {
  final WorkoutCategory category;
  final ValueChanged<String> onSportSelected;
  const _SportPickerSheet({required this.category, required this.onSportSelected});

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
                      child: Icon(category.icon, color: AppTheme.gold, size: 22),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: category.sports.length,
              shrinkWrap: true,
              itemBuilder: (_, i) {
                final sport = category.sports[i];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  title: Text(
                    sport,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
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

// ── Pre-start sheet ──────────────────────────────────────────────────────────

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
                child: Icon(widget.category.icon, color: AppTheme.gold, size: 26),
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
                      style: const TextStyle(color: AppTheme.textSec, fontSize: 13),
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
            (Icons.lock_rounded, 'Other app features are paused until you finish'),
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
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
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
                      await workout.startWorkout(widget.category, widget.sport);
                      if (!mounted) return;
                      nav.pop();
                      widget.onWorkoutStarted();
                    },
              child: _starting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.black,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text(
                      'Start Workout',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── History section ──────────────────────────────────────────────────────────

class _HistorySection extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  final bool loading;
  const _HistorySection({required this.history, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'RECENT WORKOUTS',
            style: TextStyle(
              color: AppTheme.textSec,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
        if (loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: CircularProgressIndicator(color: AppTheme.gold, strokeWidth: 2),
            ),
          )
        else if (history.isEmpty)
          _EmptyHistory()
        else
          ...history.map((row) => _HistoryCard(row: row)),
      ],
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.div),
      ),
      child: Column(
        children: [
          Icon(
            Icons.directions_run_rounded,
            color: AppTheme.textSec.withValues(alpha: 0.35),
            size: 40,
          ),
          const SizedBox(height: 10),
          const Text(
            'No workouts yet',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Complete a workout to see your history here',
            style: TextStyle(color: AppTheme.textSec, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final Map<String, dynamic> row;
  const _HistoryCard({required this.row});

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

  static String _fmtDistance(double meters) {
    if (meters <= 0) return '—';
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(2)} km';
    return '${meters.toStringAsFixed(0)} m';
  }

  static String _fmtSteps(int steps) {
    if (steps >= 1000) return '${(steps / 1000).toStringAsFixed(1)}k';
    return '$steps';
  }

  @override
  Widget build(BuildContext context) {
    final type = (row['workout_type'] as String? ?? 'running');
    final startedAt = row['started_at'] as String? ?? '';
    final durationS = (row['duration_s'] as num? ?? 0).toInt();
    final steps = (row['steps'] as num? ?? 0).toInt();
    final calories = (row['calories'] as num? ?? 0).toInt();
    final distanceM = (row['distance_m'] as num? ?? 0.0).toDouble();
    final avgHr = (row['avg_hr'] as num? ?? 0).toInt();

    final category = workoutCategoryFromString(type);
    final metrics = category?.metrics ?? WorkoutCategory.running.metrics;
    final icon = category?.icon ?? Icons.fitness_center_rounded;
    // Sport label: capitalize if needed (handles legacy "running" and new "GPS Running")
    final label = type.isNotEmpty ? '${type[0].toUpperCase()}${type.substring(1)}' : 'Workout';

    // Build stat chips respecting the category's metric set
    final chips = <Widget>[];
    if (metrics.contains(WorkoutMetric.steps)) {
      chips.add(_StatChip(
        icon: Icons.directions_walk_rounded,
        label: steps > 0 ? _fmtSteps(steps) : '—',
        sub: 'steps',
      ));
    }
    chips.add(_StatChip(
      icon: Icons.local_fire_department_rounded,
      label: calories > 0 ? '$calories' : '—',
      sub: 'kcal',
      iconColor: const Color(0xFFFF6B35),
    ));
    if (metrics.contains(WorkoutMetric.distance)) {
      chips.add(_StatChip(
        icon: Icons.straighten_rounded,
        label: _fmtDistance(distanceM),
        sub: 'dist',
        iconColor: AppTheme.success,
      ));
    }
    if (avgHr > 0) {
      chips.add(_StatChip(
        icon: Icons.monitor_heart_rounded,
        label: '$avgHr',
        sub: 'bpm',
        iconColor: AppTheme.hrColor,
      ));
    }

    // Build row children with separators
    final rowChildren = <Widget>[];
    for (int i = 0; i < chips.length; i++) {
      if (i > 0) rowChildren.add(const SizedBox(width: 8));
      rowChildren.add(chips[i]);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.div),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.goldBorder,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppTheme.gold, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (startedAt.isNotEmpty)
                      Text(
                        _fmtDate(startedAt),
                        style: const TextStyle(color: AppTheme.textSec, fontSize: 12),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.goldBorder,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _fmtDuration(durationS),
                  style: const TextStyle(
                    color: AppTheme.gold,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppTheme.div, height: 1),
          const SizedBox(height: 12),
          Row(children: rowChildren),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final Color iconColor;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.sub,
    this.iconColor = AppTheme.gold,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 16),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            sub,
            style: const TextStyle(color: AppTheme.textSec, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
