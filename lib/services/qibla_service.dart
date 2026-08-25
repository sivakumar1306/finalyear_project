import 'dart:math' as math;
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Qibla service — end-to-end wired.
/// QRing uses `Adhan` lib `calculateQiblaDirection` + `lastQiblaAngle`.
/// Sundr uses `Geolocator` for position + `flutter_compass` for heading.
class QiblaService {
  static const double kaabaLat = 21.4225;
  static const double kaabaLng = 39.8262;
  static const String _kLastLat = 'qibla_last_lat';
  static const String _kLastLng = 'qibla_last_lng';
  static const String _kLastBearing = 'qibla_last_bearing';

  static double bearing(double lat, double lng) {
    final phiK = kaabaLat * math.pi / 180.0;
    final lambdaK = kaabaLng * math.pi / 180.0;
    final phi = lat * math.pi / 180.0;
    final lambda = lng * math.pi / 180.0;
    final psi = math.atan2(
      math.sin(lambdaK - lambda),
      math.cos(phi) * math.tan(phiK) - math.sin(phi) * math.cos(lambdaK - lambda),
    );
    return (psi * 180 / math.pi + 360) % 360;
  }

  Future<Position?> getCurrentPosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kLastLat, pos.latitude);
      await prefs.setDouble(_kLastLng, pos.longitude);
      await prefs.setDouble(_kLastBearing, bearing(pos.latitude, pos.longitude));
      return pos;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, double>?> getLastKnown() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_kLastLat);
    final lng = prefs.getDouble(_kLastLng);
    final b = prefs.getDouble(_kLastBearing);
    if (lat == null || lng == null || b == null) return null;
    return {'lat': lat, 'lng': lng, 'bearing': b};
  }

  /// Compass heading stream (0-360, 0=north).
  Stream<double> compassStream() {
    try {
      final stream = FlutterCompass.events;
      if (stream == null) return Stream.value(0);
      return stream.map((e) => e.heading ?? 0).distinct();
    } catch (_) {
      return Stream.value(0);
    }
  }

  /// Qibla offset from current heading: (qiblaBearing - heading + 360) % 360
  Stream<double> qiblaOffsetStream(double qiblaBearing) {
    return compassStream().map((h) => (qiblaBearing - h + 360) % 360);
  }
}
