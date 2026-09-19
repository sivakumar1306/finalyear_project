import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/glass_card.dart';

TextStyle _inter(double size, {FontWeight weight = FontWeight.w400, Color color = Colors.white}) =>
    AppTypography.inter(fontSize: size, fontWeight: weight, color: color);

/// GPS route for one workout. Accepts raw phone-GPS fixes
/// (`[{lat, lng, ...}]`) and normalizes them to the painter's 0..1 space.
/// The ring reports no coordinates (SportPlusEntity.mLocations carries only
/// per-point heart rate), so traces only exist for phone-tracked sessions.
class GpsTraceScreen extends StatelessWidget {
  const GpsTraceScreen({super.key, this.points = const [], this.locations = const []});
  final List<Offset> points;
  final List<Map<String, dynamic>> locations;

  static List<Offset> normalize(List<Map<String, dynamic>> fixes) {
    final pts = <Offset>[];
    for (final f in fixes) {
      final lat = (f['lat'] as num?)?.toDouble();
      final lng = (f['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      pts.add(Offset(lng, lat));
    }
    if (pts.length < 2) return pts;
    var minX = pts.first.dx, maxX = pts.first.dx;
    var minY = pts.first.dy, maxY = pts.first.dy;
    for (final p in pts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final spanX = (maxX - minX) == 0 ? 1.0 : (maxX - minX);
    final spanY = (maxY - minY) == 0 ? 1.0 : (maxY - minY);
    // Flip latitude so north is up.
    return pts
        .map((p) => Offset((p.dx - minX) / spanX, 1.0 - (p.dy - minY) / spanY))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final normalized =
        points.isNotEmpty ? points : normalize(locations);
    final hasTrace = normalized.length >= 2;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(backgroundColor: AppTheme.bg, foregroundColor: Colors.white, centerTitle: true, elevation: 0, leading: const GlassBackButton(), title: Text('GPS Trace', style: _inter(17, weight: FontWeight.w600))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            child: SizedBox(
              height: 220,
              child: hasTrace
                  ? CustomPaint(painter: _TracePainter(normalized), child: const SizedBox.expand())
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No GPS recorded for this session.\nRoutes record on phone GPS during manually started workouts when location is allowed.',
                          textAlign: TextAlign.center,
                          style: _inter(13, color: AppTheme.textSec),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          GlassCard(child: Row(children: [
            const Icon(Icons.route, color: AppTheme.gold, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasTrace
                    ? '${normalized.length} GPS points recorded on this phone during the workout.'
                    : 'Ring auto-detected sessions carry no coordinates — only phone-tracked workouts have a route.',
                style: _inter(12, color: AppTheme.textTertiary),
              ),
            ),
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
