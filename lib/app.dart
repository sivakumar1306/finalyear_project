import 'package:flutter/material.dart';
import 'screens/auth/splash_screen.dart';
import 'screens/main_shell.dart';
import 'screens/device_bind/device_bind_screen.dart';
import 'screens/fall_prediction/fall_prediction_screen.dart';
import 'screens/health/heart_rate_screen.dart';
import 'screens/health/blood_pressure_screen.dart';
import 'screens/health/blood_oxygen_screen.dart';
import 'screens/health/sleep_screen.dart';
import 'screens/health/hrv_screen.dart';
import 'screens/health/stress_screen.dart';
import 'screens/health/temperature_screen.dart';
import 'screens/health/womens_health_screen.dart';
import 'theme/app_theme.dart';
import 'theme/app_scroll_behavior.dart';

class VitalApp extends StatelessWidget {
  const VitalApp({super.key});

  /// Global navigator key — lets headless services navigate without a
  /// BuildContext.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vital Monitoring',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme(),
      scrollBehavior: const AppScrollBehavior(),
      navigatorKey: navigatorKey,
      initialRoute: '/',
      routes: {
        '/': (_) => const SplashScreen(),
        '/home': (_) => const MainShell(),
        '/device-bind': (_) => const DeviceBindScreen(),
        '/fall-prediction': (_) => const FallPredictionScreen(),
        '/heart-rate': (_) => const HeartRateScreen(),
        '/blood-pressure': (_) => const BloodPressureScreen(),
        '/blood-oxygen': (_) => const BloodOxygenScreen(),
        '/sleep': (_) => const SleepScreen(),
        '/hrv': (_) => const HrvScreen(),
        '/pressure': (_) => const StressScreen(),
        '/stress': (_) => const StressScreen(),
        '/temperature': (_) => const TemperatureScreen(),
        '/womens-health': (_) => const WomensHealthScreen(),
      },
    );
  }
}
