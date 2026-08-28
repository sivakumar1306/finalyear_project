import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/ecg_model.dart';
import '../../providers/ble_provider.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/metric_chart_card.dart';
import '../../widgets/glass_card.dart';
import 'vital_note_screen.dart';
import '../../widgets/glass_menu.dart';
import '../../widgets/screenshot_share.dart';

TextStyle _inter(double size, {FontWeight weight = FontWeight.w400, Color color = Colors.white, double? letterSpacing, double? height}) =>
    AppTypography.inter(fontSize: size, fontWeight: weight, color: color, letterSpacing: letterSpacing, height: height);

class EcgScreen extends StatefulWidget {
  const EcgScreen({super.key});
  @override
  State<EcgScreen> createState() => _EcgScreenState();
}

class _EcgScreenState extends State<EcgScreen> {
  final _screenshotKey = GlobalKey();
  final _moreButtonKey = GlobalKey();
  bool _measuring = false;
  EcgSample? _last;
  List<EcgSample> _history = [];

  @override
  void initState() { super.initState(); _loadHistory(); }

  Future<void> _loadHistory() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      final rows = await SupabaseService.client.from('user_ecg').select().eq('user_id', user.id).order('measured_at', ascending: false).limit(7);
      final list = (rows as List).map((r) => EcgSample.fromMap(Map<String,dynamic>.from(r))).toList();
      if (mounted) setState(() { _history = list.reversed.toList(); if (_history.isNotEmpty) _last = _history.last; });
    } catch (_) {}
  }

  Future<void> _measure() async {
    if (_measuring) return;
    setState(() => _measuring = true);
    await Future.delayed(const Duration(seconds: 2));
    final rnd = Random();
    final data = List.generate(120, (_) => 512 + rnd.nextInt(80) + (rnd.nextBool()? 120: -60));
    final sample = EcgSample(measuredAt: DateTime.now(), avgHeartRate: 68 + rnd.nextInt(12), dataList: data);
    setState(() { _measuring = false; _last = sample; _history = [..._history, sample].take(7).toList(); });
    final user = SupabaseService.currentUser;
    if (user != null) {
      try { await SupabaseService.client.from('user_ecg').insert(sample.toMap(user.id)); } catch (_) {}
    }
  }

  void _openMenu() => showGlassMenu(context: context, anchorKey: _moreButtonKey, items: [
        GlassMenuItem(label: 'Share', onTap: () => shareScreenshot(_screenshotKey, text: 'My ECG — SUNDR')),
        GlassMenuItem(label: 'Note', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VitalNoteScreen(title: 'ECG', heading: 'About ECG', intro: 'Single-lead ECG preview from the ring. Not a medical diagnosis.', ranges: [], tips: [], didYouKnow: 'ECG needs dry fingers and still hand.')))),
      ]);

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;
    final hr = _last?.avgHeartRate;
    return RepaintBoundary(
      key: _screenshotKey,
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(backgroundColor: AppTheme.bg, foregroundColor: Colors.white, centerTitle: true, elevation: 0, leading: const GlassBackButton(), title: Text('ECG', style: _inter(17, weight: FontWeight.w600)), actions: [IconButton(key: _moreButtonKey, icon: const Icon(Icons.more_vert, color: Colors.white), onPressed: _openMenu)], bottom: PreferredSize(preferredSize: const Size.fromHeight(0.5), child: Container(color: AppTheme.div, height: 0.5))),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 16),
            Text('CURRENT ECG', style: _inter(11, weight: FontWeight.w600, color: AppTheme.gold, letterSpacing: 1.2)),
            const SizedBox(height: 2),
            Text(hr != null ? '$hr' : '--', style: _inter(52, weight: FontWeight.w300, height: 1.1)),
            Text('bpm · ${_last != null ? 'measured now' : 'no data'}', style: _inter(13, color: AppTheme.textTertiary)),
            const SizedBox(height: 16),
            GlassCard(
              child: SizedBox(height: 120, child: _last == null
                  ? Center(child: Text('No ECG yet', style: _inter(13, color: AppTheme.textTertiary)))
                  : CustomPaint(painter: _EcgPainter(_last!.dataList), child: const SizedBox.expand())),
            ),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, height: 52, child: ElevatedButton(onPressed: _measuring ? null : _measure, style: ElevatedButton.styleFrom(backgroundColor: AppTheme.gold, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))), child: Text(_measuring ? 'Measuring…' : connected ? 'Start 30s ECG' : 'Simulate ECG', style: _inter(14, weight: FontWeight.w600, color: Colors.black)))),
            const SizedBox(height: 20),
            if (_history.isNotEmpty)
              MetricChartCard(
                headerLabel: 'HISTORY',
                rangeLabel: '${_history.map((e)=> e.avgHeartRate).reduce((a,b)=> a<b?a:b)} - ${_history.map((e)=> e.avgHeartRate).reduce((a,b)=> a>b?a:b)} bpm',
                yLabels: const ['100','80','60','40'],
                loadingAccent: AppTheme.hrColor,
                barCount: _history.length,
                xLabels: List.generate(_history.length, (i) => '${i+1}'),
                child: CustomPaint(painter: _MiniBar(_history.map((e)=> e.avgHeartRate).toList()), child: const SizedBox.expand()),
              ),
            const SizedBox(height: 80),
          ]),
        ),
      ),
    );
  }
}

class _EcgPainter extends CustomPainter {
  final List<int> data;
  _EcgPainter(this.data);
  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final paint = Paint()..color = const Color(0xFFFF4757).withValues(alpha: 0.9)..strokeWidth = 1.4..style = PaintingStyle.stroke;
    final path = Path();
    final dx = size.width / (data.length - 1);
    final minVal = data.reduce((a,b)=> a<b?a:b).toDouble();
    final maxVal = data.reduce((a,b)=> a>b?a:b).toDouble();
    final range = (maxVal - minVal).clamp(1, 1000);
    for (int i = 0; i < data.length; i++) {
      final x = i * dx;
      final y = size.height - ((data[i] - minVal) / range) * size.height * 0.8 - size.height * 0.1;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _MiniBar extends CustomPainter {
  final List<int> values;
  _MiniBar(this.values);
  @override
  void paint(Canvas c, Size s) {
    if (values.isEmpty) return;
    final paint = Paint()..color = const Color(0xFFFF4757).withValues(alpha:0.88)..style=PaintingStyle.fill;
    final w = s.width / values.length;
    for(int i=0;i<values.length;i++){
      final h = (values[i]/120)*s.height;
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(i*w+ w*0.2, s.height-h, w*0.6, h), const Radius.circular(4)), paint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter old)=> false;
}
