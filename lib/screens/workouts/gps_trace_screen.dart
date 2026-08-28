import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/glass_card.dart';

TextStyle _inter(double size, {FontWeight weight = FontWeight.w400, Color color = Colors.white}) =>
    AppTypography.inter(fontSize: size, fontWeight: weight, color: color);

class GpsTraceScreen extends StatelessWidget {
  const GpsTraceScreen({super.key, this.points = const []});
  final List<Offset> points;

  @override
  Widget build(BuildContext context) {
    final demo = points.isEmpty
        ? List.generate(30, (i) => Offset(i / 29, 0.5 + 0.3 * (i % 5 - 2) / 5))
        : points;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(backgroundColor: AppTheme.bg, foregroundColor: Colors.white, centerTitle: true, elevation: 0, leading: const GlassBackButton(), title: Text('GPS Trace', style: _inter(17, weight: FontWeight.w600))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            child: SizedBox(
              height: 220,
              child: CustomPaint(painter: _TracePainter(demo), child: const SizedBox.expand()),
            ),
          ),
          const SizedBox(height: 12),
          GlassCard(child: Row(children: [
            const Icon(Icons.route, color: AppTheme.gold, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('QRing gps_detail polyline — stored in user_workouts.locations. Real trace from SportPlusHandle/ReadDetailSportDataReq.', style: _inter(12, color: AppTheme.textTertiary))),
          ])),
        ],
      ),
    );
  }
}

class _TracePainter extends CustomPainter {
  final List<Offset> points;
  _TracePainter(this.points);
  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) {
      return;
    }
    final paint = Paint()..color = const Color(0xFFC9A86E)..strokeWidth = 2.5..style = PaintingStyle.stroke..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (int i = 0; i < points.length; i++) {
      final p = Offset(points[i].dx * size.width, points[i].dy * size.height);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, paint);
    // start/end dots
    canvas.drawCircle(Offset(points.first.dx * size.width, points.first.dy * size.height), 4, Paint()..color = AppTheme.success);
    canvas.drawCircle(Offset(points.last.dx * size.width, points.last.dy * size.height), 4, Paint()..color = AppTheme.danger);
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
