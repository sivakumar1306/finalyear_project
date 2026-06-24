import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/workout_provider.dart';
import '../../models/workout_model.dart';
import '../../theme/app_theme.dart';

class ActiveWorkoutScreen extends StatelessWidget {
  const ActiveWorkoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final confirm = await _showAbandonDialog(context);
        if (confirm == true && context.mounted) {
          await context.read<WorkoutProvider>().stopWorkout();
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        body: SafeArea(
          child: Consumer<WorkoutProvider>(
            builder: (context, workout, _) {
              return Column(
                children: [
                  _Header(workout: workout),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          const SizedBox(height: 8),
                          _MetricsGrid(workout: workout),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                  _FinishButton(workout: workout),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<bool?> _showAbandonDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: const Text('End Workout?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Your workout will be stopped and progress will be saved.',
          style: TextStyle(color: AppTheme.textSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continue', style: TextStyle(color: AppTheme.gold)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End Workout', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final WorkoutProvider workout;
  const _Header({required this.workout});

  String _formatElapsed(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.goldBorder,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.circle, color: AppTheme.danger, size: 8),
                    const SizedBox(width: 6),
                    Text(
                      workout.currentType?.label ?? 'Workout',
                      style: const TextStyle(
                        color: AppTheme.gold,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _formatElapsed(workout.elapsedSeconds),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 56,
              fontWeight: FontWeight.w200,
              letterSpacing: 4,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const Text(
            'ELAPSED TIME',
            style: TextStyle(
              color: AppTheme.textSec,
              fontSize: 11,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  final WorkoutProvider workout;
  const _MetricsGrid({required this.workout});

  String _formatDistance(double meters) {
    if (meters <= 0) return '—';
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(2)} km';
    return '${meters.toStringAsFixed(0)} m';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Steps',
                value: workout.workoutSteps > 0 ? '${workout.workoutSteps}' : '—',
                icon: Icons.directions_walk_rounded,
                color: AppTheme.stepsColor,
                subtitle: 'This session',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                label: 'Calories',
                value: workout.workoutCalories > 0 ? '${workout.workoutCalories} kcal' : '—',
                icon: Icons.local_fire_department_rounded,
                color: const Color(0xFFFF6B35),
                subtitle: 'Burned',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _MetricCard(
          label: 'Distance',
          value: _formatDistance(workout.workoutDistanceM),
          icon: Icons.straighten_rounded,
          color: AppTheme.success,
          subtitle: 'Covered',
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String subtitle;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.textSec,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: value == '—' ? AppTheme.textSec : Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(color: AppTheme.textSec, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _FinishButton extends StatefulWidget {
  final WorkoutProvider workout;
  const _FinishButton({required this.workout});

  @override
  State<_FinishButton> createState() => _FinishButtonState();
}

class _FinishButtonState extends State<_FinishButton> {
  bool _finishing = false;

  Future<void> _finish() async {
    setState(() => _finishing = true);
    final session = await widget.workout.stopWorkout();
    if (!mounted) return;
    setState(() => _finishing = false);
    Navigator.of(context).pop();
    if (session != null) _showSummaryDialog(context, session);
  }

  void _showSummaryDialog(BuildContext context, WorkoutSession session) {
    final duration = session.durationSeconds;
    final h = duration ~/ 3600;
    final m = (duration % 3600) ~/ 60;
    final s = duration % 60;
    final timeStr = h > 0
        ? '${h}h ${m}m ${s}s'
        : m > 0
            ? '${m}m ${s}s'
            : '${s}s';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 24),
            const SizedBox(width: 8),
            Text(
              '${session.type.label} Complete',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SummaryRow(label: 'Duration', value: timeStr),
            _SummaryRow(label: 'Steps', value: '${session.steps}'),
            _SummaryRow(label: 'Calories', value: '${session.calories} kcal'),
            _SummaryRow(
              label: 'Distance',
              value: session.distanceM >= 1000
                  ? '${(session.distanceM / 1000).toStringAsFixed(2)} km'
                  : '${session.distanceM.toStringAsFixed(0)} m',
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.gold,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.danger,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: _finishing ? null : _finish,
          child: _finishing
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : const Text(
                  'Finish Workout',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textSec, fontSize: 14)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
