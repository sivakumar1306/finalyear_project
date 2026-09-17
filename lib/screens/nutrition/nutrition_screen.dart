import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/nutrition_model.dart';
import '../../services/incident_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/metric_chart_card.dart';
import '../../widgets/metric_bar_painter.dart';

TextStyle _inter(double size, {FontWeight weight = FontWeight.w400, Color color = Colors.white, double? letterSpacing}) =>
    AppTypography.inter(fontSize: size, fontWeight: weight, color: color, letterSpacing: letterSpacing);

class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key});
  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  List<NutritionLog> _logs = [];
  bool _loading = true;
  static const _kLocalKey = 'nutrition_logs_v1';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    List<NutritionLog> logs = [];
    final user = SupabaseService.currentUser;
    if (user != null) {
      try {
        final rows = await SupabaseService.client.from('user_nutrition_logs').select().eq('user_id', user.id).order('date', ascending: true).limit(30);
        logs = (rows as List).map((r) => NutritionLog.fromMap(Map<String,dynamic>.from(r))).toList();
      } catch (_) {}
    }
    if (logs.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_kLocalKey);
        if (raw != null) {
          final arr = jsonDecode(raw) as List;
          logs = arr.map((e) => NutritionLog.fromMap(Map<String,dynamic>.from(e as Map))).toList();
        }
      } catch (_) {}
    }
    if (mounted) setState(() { _logs = logs; _loading = false; });
  }

  Future<void> _add() async {
    final calsCtrl = TextEditingController();
    final carbsCtrl = TextEditingController();
    final proteinCtrl = TextEditingController();
    final fatCtrl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.card,
      title: Text('Log Meal', style: _inter(16, weight: FontWeight.w600)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: calsCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Calories', labelStyle: _inter(12, color: AppTheme.textTertiary)), style: _inter(14)),
        TextField(controller: carbsCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Carbs g', labelStyle: _inter(12, color: AppTheme.textTertiary)), style: _inter(14)),
        TextField(controller: proteinCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Protein g', labelStyle: _inter(12, color: AppTheme.textTertiary)), style: _inter(14)),
        TextField(controller: fatCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Fat g', labelStyle: _inter(12, color: AppTheme.textTertiary)), style: _inter(14)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: _inter(13))),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: AppTheme.gold), child: Text('Save', style: _inter(13, weight: FontWeight.w600, color: Colors.black))),
      ],
    ));
    if (ok != true) return;
    final log = NutritionLog(date: DateTime.now(), calories: int.tryParse(calsCtrl.text) ?? 0, carbs: int.tryParse(carbsCtrl.text) ?? 0, protein: int.tryParse(proteinCtrl.text) ?? 0, fat: int.tryParse(fatCtrl.text) ?? 0);
    final user = SupabaseService.currentUser;
    try {
      if (user != null) {
        await SupabaseService.client.from('user_nutrition_logs').insert(log.toMap(user.id));
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(source: 'nutrition_screen', error: e, stackTrace: st, customMessage: 'Nutrition log insert to Supabase failed');
    }
    // local cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final arr = _logs.map((e) => {'date': e.date.toIso8601String(), 'calories': e.calories, 'carbs': e.carbs, 'protein': e.protein, 'fat': e.fat}).toList()..add({'date': log.date.toIso8601String(), 'calories': log.calories, 'carbs': log.carbs, 'protein': log.protein, 'fat': log.fat});
      await prefs.setString(_kLocalKey, jsonEncode(arr));
    } catch (_) {}
    setState(() => _logs = [..._logs, log]);
  }

  @override
  Widget build(BuildContext context) {
    final last7 = _logs.length >= 7 ? _logs.sublist(_logs.length - 7) : _logs;
    final vals = last7.map((e) => e.calories).toList();
    if (vals.length < 7) vals.insertAll(0, List.filled(7 - vals.length, 0));
    final maxCal = vals.isEmpty ? 0 : vals.reduce((a,b)=> a>b?a:b);
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(backgroundColor: AppTheme.bg, foregroundColor: Colors.white, centerTitle: true, elevation: 0, leading: const GlassBackButton(), title: Text('Nutrition', style: _inter(17, weight: FontWeight.w600))),
      floatingActionButton: FloatingActionButton(onPressed: _add, backgroundColor: AppTheme.gold, child: const Icon(Icons.add, color: Colors.black)),
      body: _loading ? const Center(child: CircularProgressIndicator(color: AppTheme.gold)) : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('NUTRITION', style: _inter(11, weight: FontWeight.w600, color: AppTheme.gold, letterSpacing: 1.0)),
            const SizedBox(height: 8),
            Text('Calorie / Carbs / Protein — QRing NutritionActivity. Logged meals sync to Supabase user_nutrition_logs (offline cached).', style: _inter(13, color: AppTheme.textTertiary)),
          ])),
          const SizedBox(height: 12),
          MetricChartCard(headerLabel: 'CALORIES LAST 7 DAYS', rangeLabel: maxCal>0 ? 'max $maxCal' : '--', yLabels: const ['3000','2000','1000','0'], loadingAccent: AppTheme.gold, barCount: vals.length, xLabels: const ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'], child: CustomPaint(painter: MetricBarPainter(values: vals, maxY: 3000, yLines: const [3000,2000,1000,0], barColor: AppTheme.gold.withValues(alpha:0.88)), child: const SizedBox.expand())),
          const SizedBox(height: 12),
          if (_logs.isEmpty)
            GlassCard(child: Center(child: Padding(padding: const EdgeInsets.all(12), child: Text('No meals yet — tap + to log.', style: _inter(13, color: AppTheme.textTertiary)))))
          else
            ..._logs.reversed.take(10).map((l) => Padding(padding: const EdgeInsets.only(bottom: 8), child: GlassCard(child: Row(children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: AppTheme.gold.withValues(alpha:0.12), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.restaurant, color: AppTheme.gold, size: 18)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${l.calories} kcal', style: _inter(14, weight: FontWeight.w600)),
                Text('${l.carbs}g carbs · ${l.protein}g protein · ${l.fat}g fat', style: _inter(11, color: AppTheme.textTertiary)),
                Text('${l.date.month}/${l.date.day} ${l.date.hour}:${l.date.minute.toString().padLeft(2,'0')}', style: _inter(11, color: AppTheme.textTertiary)),
              ])),
            ])))),
        ],
      ),
    );
  }
}
