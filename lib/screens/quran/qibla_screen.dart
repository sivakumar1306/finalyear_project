import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/glass_card.dart';
import '../../services/qibla_service.dart';

TextStyle _inter(double size, {FontWeight weight = FontWeight.w400, Color color = Colors.white, double? letterSpacing}) =>
    AppTypography.inter(fontSize: size, fontWeight: weight, color: color, letterSpacing: letterSpacing);

class QiblaScreen extends StatefulWidget {
  const QiblaScreen({super.key});
  @override
  State<QiblaScreen> createState() => _QiblaScreenState();
}

class _QiblaScreenState extends State<QiblaScreen> {
  final _qibla = QiblaService();
  double? _qiblaBearing;
  double? _lat, _lng;
  String _locationLabel = 'Locating…';
  double _heading = 0;
  StreamSubscription<double>? _compassSub;
  bool _loadingLocation = true;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _initCompass();
  }

  Future<void> _initLocation() async {
    setState(() => _loadingLocation = true);
    final pos = await _qibla.getCurrentPosition();
    if (!mounted) return;
    if (pos != null) {
      final b = QiblaService.bearing(pos.latitude, pos.longitude);
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _qiblaBearing = b;
        _locationLabel = '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
        _loadingLocation = false;
      });
    } else {
      final last = await _qibla.getLastKnown();
      if (last != null) {
        setState(() {
          _lat = last['lat'];
          _lng = last['lng'];
          _qiblaBearing = last['bearing'];
          _locationLabel = 'Last known · ${last['lat']!.toStringAsFixed(4)}, ${last['lng']!.toStringAsFixed(4)}';
          _loadingLocation = false;
        });
      } else {
        // Fallback Riyadh
        final b = QiblaService.bearing(24.7136, 46.6753);
        setState(() {
          _qiblaBearing = b;
          _locationLabel = 'Riyadh (fallback) — enable location';
          _loadingLocation = false;
        });
      }
    }
  }

  void _initCompass() {
    _compassSub = _qibla.compassStream().listen((h) {
      if (mounted) setState(() => _heading = h);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bearing = _qiblaBearing;
    final offset = bearing != null ? (bearing - _heading + 360) % 360 : 0.0;
    final aligned = offset < 5 || offset > 355;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(backgroundColor: AppTheme.bg, foregroundColor: Colors.white, centerTitle: true, elevation: 0, leading: const GlassBackButton(), title: Text('Qibla', style: _inter(17, weight: FontWeight.w600))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('QIBLA COMPASS', style: _inter(11, weight: FontWeight.w600, color: AppTheme.gold, letterSpacing: 1.0)),
              const SizedBox(height: 12),
              Container(
                height: 260,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.08))),
                child: Stack(alignment: Alignment.center, children: [
                  // Outer ring
                  Container(width: 180, height: 180, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1))),
                  // North marker
                  Positioned(top: 18, child: Text('N', style: _inter(12, weight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.6)))),
                  // Qibla arrow (rotates with offset)
                  Transform.rotate(
                    angle: -offset * math.pi / 180,
                    child: Icon(Icons.navigation, color: aligned ? AppTheme.gold : Colors.white, size: 52),
                  ),
                  // Center dot
                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFC9A86E), shape: BoxShape.circle)),
                  if (_loadingLocation)
                    Positioned(bottom: 12, child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.gold))),
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(bearing != null ? 'Bearing ${bearing.toStringAsFixed(1)}°' : '—', style: _inter(16, weight: FontWeight.w600)),
                  Text(_locationLabel, style: _inter(12, color: AppTheme.textTertiary)),
                  Text('Heading ${ _heading.toStringAsFixed(1)}° · offset ${offset.toStringAsFixed(1)}°', style: _inter(11, color: AppTheme.textTertiary)),
                ])),
                if (aligned) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: AppTheme.gold, borderRadius: BorderRadius.circular(99)), child: Text('Aligned', style: _inter(11, weight: FontWeight.w600, color: Colors.black))),
              ]),
              const SizedBox(height: 8),
              Text('Rotate phone until arrow points up. Bearing from Adhan calc (QRing lastQiblaAngle).', style: _inter(12, color: AppTheme.textTertiary)),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: OutlinedButton(onPressed: _initLocation, style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.white.withValues(alpha: 0.12)), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text('Refresh location', style: _inter(13)))),
            ]),
          ),
          const SizedBox(height: 12),
          GlassCard(
            child: Row(children: [
              const Icon(Icons.info_outline, color: AppTheme.gold, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('Uses Geolocator + flutter_compass. Last bearing cached in SharedPreferences.', style: _inter(12, color: AppTheme.textTertiary))),
            ]),
          ),
        ],
      ),
    );
  }
}
