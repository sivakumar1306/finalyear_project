import 'package:flutter/material.dart';
import '../../models/health_data.dart';
import '../../models/workout_model.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/metric_chart_card.dart';
import '../../widgets/metric_bar_painter.dart';

TextStyle _inter(double size, {FontWeight weight = FontWeight.w400, Color color = Colors.white}) =>
    AppTypography.inter(fontSize: size, fontWeight: weight, color: color);

class SportTypeDetailScreen extends StatefulWidget {
  final String type;
  const SportTypeDetailScreen({super.key, required this.type});
  @override
  State<SportTypeDetailScreen> createState() => _SportTypeDetailScreenState();
}

class _SportTypeDetailScreenState extends State<SportTypeDetailScreen> {
  List<WorkoutRecord> _records = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final user = SupabaseService.currentUser;
    if (user != null) {
      try {
        final rows = await SupabaseService.getWorkoutHistory(userId: user.id, from: DateTime.now().subtract(const Duration(days: 30)), to: DateTime.now());
        final list = rows.map((r) => WorkoutRecord.fromMap(r)).where((w) => w.type.toLowerCase() == widget.type.toLowerCase()).toList();
        if (mounted) setState(() { _records = list; _loading = false; });
        return;
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    WorkoutCategory cat;
    try {
      cat = WorkoutCategory.values.firstWhere((c) => c.name.toLowerCase() == widget.type.toLowerCase());
    } catch (_) {
      cat = WorkoutCategory.running;
    }
    final vals = _records.map<int>((r) => r.durationS ~/ 60).toList();
    final displayVals = vals.length >= 7 ? vals.sublist(vals.length - 7) : vals;
    while (displayVals.length < 7) {
      displayVals.insert(0, 0);
    }
    final rangeLabel = _records.isEmpty
        ? '--'
        : '${_records.map<int>((r) => r.durationS).reduce((a, b) => a < b ? a : b) ~/ 60} - ${_records.map<int>((r) => r.durationS).reduce((a, b) => a > b ? a : b) ~/ 60} min';
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(backgroundColor: AppTheme.bg, foregroundColor: Colors.white, centerTitle: true, elevation: 0, leading: const GlassBackButton(), title: Text(widget.type, style: _inter(17, weight: FontWeight.w600))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.gold))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                GlassCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(cat.label.toUpperCase(), style: _inter(11, weight: FontWeight.w600, color: AppTheme.gold)),
                  const SizedBox(height: 4),
                  Text('${_records.length} sessions · ${cat.sports.take(4).join(', ')}', style: _inter(13, color: AppTheme.textTertiary)),
                ])),
                const SizedBox(height: 12),
                MetricChartCard(
                    headerLabel: 'DURATION (MIN) LAST 7',
                    rangeLabel: rangeLabel,
                    yLabels: const ['60', '40', '20', '0'],
                    loadingAccent: AppTheme.gold,
                    barCount: displayVals.length,
                    xLabels: const ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
                    child: CustomPaint(
                        painter: MetricBarPainter(values: displayVals, maxY: 60, yLines: const [60, 40, 20, 0], barColor: AppTheme.gold.withValues(alpha: 0.88)),
                        child: const SizedBox.expand())),
                const SizedBox(height: 12),
                if (_records.isEmpty)
                  GlassCard(
                      child: Center(
                          child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text('No ${widget.type} records yet — start a workout from Workouts tab.', style: _inter(13, color: AppTheme.textTertiary))))),
                for (final r in _records.reversed.take(8))
                  Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GlassCard(
                          child: Row(children: [
                        Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(color: AppTheme.gold.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.fitness_center, color: AppTheme.gold, size: 18)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${r.durationS ~/ 60} min · ${r.calories} kcal', style: _inter(14, weight: FontWeight.w600)),
                          Text('${r.startedAt.month}/${r.startedAt.day} ${r.distanceM.toStringAsFixed(0)}m · ${r.steps} steps', style: _inter(11, color: AppTheme.textTertiary)),
                        ])),
                      ]))),
              ],
            ),
    );
  }
}
