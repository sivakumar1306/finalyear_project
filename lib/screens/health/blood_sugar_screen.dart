import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/blood_sugar_model.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/metric_chart_card.dart';
import '../../widgets/metric_bar_painter.dart';
import '../../widgets/glass_card.dart';
import 'vital_note_screen.dart';
import '../../widgets/glass_menu.dart';
import '../../widgets/screenshot_share.dart';
import '../../widgets/date_scroll_row.dart';

TextStyle _inter(double size, {FontWeight weight = FontWeight.w400, Color color = Colors.white, double? letterSpacing, double? height}) =>
    AppTypography.inter(fontSize: size, fontWeight: weight, color: color, letterSpacing: letterSpacing, height: height);

class BloodSugarScreen extends StatefulWidget {
  const BloodSugarScreen({super.key});
  @override
  State<BloodSugarScreen> createState() => _BloodSugarScreenState();
}

class _BloodSugarScreenState extends State<BloodSugarScreen> {
  final _ble = BleService();
  final _screenshotKey = GlobalKey();
  final _moreButtonKey = GlobalKey();
  bool _loading = false;
  DateTime _selectedDate = DateTime.now();
  List<int> _hourMin = List.filled(24, 0);
  List<int> _hourMax = List.filled(24, 0);
  int _avgMin = 0, _avgMax = 0;
  List<BloodSugarReading> _readings = [];

  @override
  void initState() { super.initState(); _fetch(); }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final user = SupabaseService.currentUser;
    if (user != null) {
      try {
        final rows = await SupabaseService.client.from('user_blood_sugar').select().eq('user_id', user.id).gte('measured_at', DateTime(_selectedDate.year,_selectedDate.month,_selectedDate.day).toUtc().toIso8601String()).lte('measured_at', DateTime(_selectedDate.year,_selectedDate.month,_selectedDate.day,23,59,59).toUtc().toIso8601String()).order('measured_at');
        final list = (rows as List).map((r)=> BloodSugarReading.fromMap(Map<String,dynamic>.from(r))).toList();
        _readings = list;
        _hourMin = List.filled(24, 0);
        _hourMax = List.filled(24, 0);
        for (final r in list) { final h=r.hour; _hourMin[h]= _hourMin[h]==0? r.minSugar : (_hourMin[h]+r.minSugar)~/2; _hourMax[h]= _hourMax[h]==0? r.maxSugar : (_hourMax[h]+r.maxSugar)~/2; }
        if (list.isNotEmpty) { _avgMin = list.map((e)=> e.minSugar).reduce((a,b)=> a<b?a:b); _avgMax = list.map((e)=> e.maxSugar).reduce((a,b)=> a>b?a:b); }
      } catch (_) {}
    }
    // Fallback: try ring health settings stub values for demo
    if (_readings.isEmpty) {
      try {
        final json = await _ble.getHealthSettings();
        jsonDecode(json);
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  void _onDateSelected(DateTime d) { setState(() => _selectedDate = d); _fetch(); }

  void _openMenu() => showGlassMenu(context: context, anchorKey: _moreButtonKey, items: [
        GlassMenuItem(label: 'Share', onTap: () => shareScreenshot(_screenshotKey, text: 'My Blood Sugar — SUNDR')),
        GlassMenuItem(label: 'Note', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VitalNoteScreen(title: 'Blood Sugar', heading: 'About Blood Sugar', intro: 'Continuous glucose preview 1/h from ring (premium). Not medical diagnosis.', ranges: [], tips: [], didYouKnow: 'Sugar varies with meals and activity.')))),
      ]);

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;
    final hasData = _hourMin.any((v)=> v>0) || _hourMax.any((v)=> v>0);
    return RepaintBoundary(
      key: _screenshotKey,
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(backgroundColor: AppTheme.bg, foregroundColor: Colors.white, centerTitle: true, elevation: 0, leading: const GlassBackButton(), title: Text('Blood Sugar', style: _inter(17, weight: FontWeight.w600)), actions: [IconButton(key: _moreButtonKey, icon: const Icon(Icons.more_vert, color: Colors.white), onPressed: _openMenu)], bottom: PreferredSize(preferredSize: const Size.fromHeight(0.5), child: Container(color: AppTheme.div, height: 0.5))),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 16),
            DateScrollRow(selectedDate: _selectedDate, onDateSelected: _onDateSelected),
            const SizedBox(height: 22),
            Text('CURRENT RANGE', style: _inter(11, weight: FontWeight.w600, color: AppTheme.gold, letterSpacing: 1.2)),
            const SizedBox(height: 2),
            Text(hasData ? '$_avgMin – $_avgMax' : '--', style: _inter(52, weight: FontWeight.w300, height: 1.1)),
            Text('mmol/L', style: _inter(13, color: AppTheme.textTertiary)),
            const SizedBox(height: 16),
            GlassCard(
              child: Row(children: [
                Icon(Icons.science, color: AppTheme.gold, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(connected ? 'Ring continuous (1/h) — premium ring required' : 'Connect premium ring for live CGM', style: _inter(12, color: AppTheme.textTertiary))),
              ]),
            ),
            const SizedBox(height: 10),
            MetricChartCard(
              headerLabel: hasData ? 'TODAY' : 'NO DATA YET',
              rangeLabel: hasData ? '$_avgMin – $_avgMax mmol/L' : '-- --',
              yLabels: const ['15','10','5','0'],
              loadingAccent: AppTheme.gold,
              barCount: 24,
              xLabels: const ['12am','6am','12pm','6pm',''],
              loading: _loading,
              child: CustomPaint(painter: MetricBarPainter(values: _hourMax, maxY: 15, yLines: const [15,10,5,0], barColor: AppTheme.gold.withValues(alpha: 0.88)), child: const SizedBox.expand()),
            ),
            const SizedBox(height: 10),
            if (hasData)
              MetricChartCard(
                headerLabel: 'MIN',
                rangeLabel: '$_avgMin mmol/L',
                yLabels: const ['15','10','5','0'],
                loadingAccent: AppTheme.hrvColor,
                barCount: 24,
                xLabels: const ['12am','6am','12pm','6pm',''],
                child: CustomPaint(painter: MetricBarPainter(values: _hourMin, maxY: 15, yLines: const [15,10,5,0], barColor: AppTheme.hrvColor.withValues(alpha:0.88)), child: const SizedBox.expand()),
              ),
            const SizedBox(height: 80),
          ]),
        ),
      ),
    );
  }
}
