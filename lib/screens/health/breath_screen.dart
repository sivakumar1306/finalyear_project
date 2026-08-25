// ignore_for_file: use_null_aware_elements
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/breath_model.dart';
import '../../providers/ble_provider.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/metric_chart_card.dart';
import '../../widgets/metric_bar_painter.dart';
import 'vital_note_screen.dart';
import '../../widgets/glass_menu.dart';
import '../../widgets/screenshot_share.dart';

TextStyle _inter(double size, {FontWeight weight = FontWeight.w400, Color color = Colors.white, double? letterSpacing, double? height}) =>
    AppTypography.inter(fontSize: size, fontWeight: weight, color: color, letterSpacing: letterSpacing, height: height);

class BreathScreen extends StatefulWidget {
  const BreathScreen({super.key});
  @override
  State<BreathScreen> createState() => _BreathScreenState();
}

class _BreathScreenState extends State<BreathScreen> {
  final _screenshotKey = GlobalKey();
  final _moreButtonKey = GlobalKey();
  String _selectedMethodId = BreathMethod.catalog.first.id;
  bool _breathing = false;
  int _elapsedS = 0;
  int _breaths = 0;
  Timer? _timer;
  List<int> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      final rows = await SupabaseService.client
          .from('user_breath_sessions')
          .select()
          .eq('user_id', user.id)
          .order('started_at', ascending: false)
          .limit(7);
      final list = (rows as List).map((r) => (r['duration_s'] as num? ?? 0).toInt()).toList();
      if (mounted && list.isNotEmpty) setState(() => _history = list.reversed.toList());
    } catch (_) {}
  }

  void _toggle() {
    if (_breathing) {
      _timer?.cancel();
      setState(() => _breathing = false);
      _saveSession();
    } else {
      setState(() { _breathing = true; _elapsedS = 0; _breaths = 0; });
      final method = BreathMethod.byId(_selectedMethodId);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _elapsedS++;
          if (_elapsedS % (method.cycleMs ~/ 1000) == 0) _breaths++;
        });
      });
    }
  }

  Future<void> _saveSession() async {
    final user = SupabaseService.currentUser;
    if (user == null || _elapsedS < 10) return;
    final now = DateTime.now();
    try {
      final ble = context.read<BleProvider>();
      final avgHr = ble.latestHr > 0 ? ble.latestHr : null;
      await SupabaseService.client.from('user_breath_sessions').insert({
        'user_id': user.id,
        'method_id': _selectedMethodId,
        'started_at': now.subtract(Duration(seconds: _elapsedS)).toUtc().toIso8601String(),
        'ended_at': now.toUtc().toIso8601String(),
        'duration_s': _elapsedS,
        if (avgHr != null) 'average_hr': avgHr,
      });
      _loadHistory();
    } catch (_) {}
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  void _openMenu() => showGlassMenu(context: context, anchorKey: _moreButtonKey, items: [
        GlassMenuItem(label: 'Share', onTap: () => shareScreenshot(_screenshotKey, text: 'My Breath — SUNDR')),
        GlassMenuItem(label: 'Note', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VitalNoteScreen(title: 'Breath', heading: 'About Breath Training', intro: 'Guided breathing helps HRV and stress. Follow the timer and breathe with the ring\'s HR overlay.', ranges: [], tips: [], didYouKnow: 'Box breathing is used by Navy SEALs for focus.')))),
      ]);

  @override
  Widget build(BuildContext context) {
    final method = BreathMethod.byId(_selectedMethodId);
    final connected = context.watch<BleProvider>().isConnected;
    return RepaintBoundary(
      key: _screenshotKey,
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(
          backgroundColor: AppTheme.bg,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
          leading: const GlassBackButton(),
          title: Text('Breath', style: _inter(17, weight: FontWeight.w600)),
          actions: [IconButton(key: _moreButtonKey, icon: const Icon(Icons.more_vert, color: Colors.white), onPressed: _openMenu)],
          bottom: PreferredSize(preferredSize: const Size.fromHeight(0.5), child: Container(color: AppTheme.div, height: 0.5)),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 16),
            Text('GUIDED BREATHING', style: _inter(11, weight: FontWeight.w600, color: AppTheme.gold, letterSpacing: 1.2)),
            const SizedBox(height: 2),
            Text(_breathing ? '${(_elapsedS ~/ 60).toString().padLeft(2,'0')}:${(_elapsedS % 60).toString().padLeft(2,'0')}' : method.name, style: _inter(52, weight: FontWeight.w300, height: 1.1)),
            Text(_breathing ? '$_breaths breaths · ${method.category}' : method.description, style: _inter(13, color: AppTheme.textTertiary)),
            const SizedBox(height: 16),
            GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('METHOD', style: _inter(11, weight: FontWeight.w600, color: AppTheme.textTertiary, letterSpacing: 1.0)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: BreathMethod.catalog.map((m) {
                  final sel = m.id == _selectedMethodId;
                  return ChoiceChip(
                    label: Text(m.name, style: _inter(12, color: sel ? Colors.black : Colors.white)),
                    selected: sel,
                    selectedColor: AppTheme.gold,
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    onSelected: _breathing ? null : (v) { if (v) setState(() => _selectedMethodId = m.id); },
                  );
                }).toList()),
              ]),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _toggle,
                style: ElevatedButton.styleFrom(backgroundColor: _breathing ? AppTheme.danger : AppTheme.gold, foregroundColor: _breathing ? Colors.white : Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))),
                child: Text(_breathing ? 'Stop' : connected ? 'Start Training' : 'Start (offline)', style: _inter(14, weight: FontWeight.w600, color: _breathing ? Colors.white : Colors.black)),
              ),
            ),
            const SizedBox(height: 20),
            MetricChartCard(
              headerLabel: 'LAST SESSIONS',
              rangeLabel: _history.isEmpty ? '-- --' : '${_history.reduce((a,b)=> a<b?a:b)} - ${_history.reduce((a,b)=> a>b?a:b)} s',
              yLabels: const ['300','200','100','0'],
              loadingAccent: AppTheme.hrvColor,
              barCount: _history.length,
              xLabels: List.generate(_history.length, (i) => '${i+1}'),
              child: CustomPaint(painter: MetricBarPainter(values: _history, maxY: 300, yLines: const [300,200,100,0], barColor: AppTheme.hrvColor.withValues(alpha: 0.88)), child: const SizedBox.expand()),
            ),
            const SizedBox(height: 80),
          ]),
        ),
      ),
    );
  }
}
