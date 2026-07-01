import 'package:flutter/material.dart';
import 'screens/auth/splash_screen.dart';
import 'screens/main_shell.dart';
import 'screens/device_bind/device_bind_screen.dart';
import 'screens/health/heart_rate_screen.dart';
import 'screens/health/blood_pressure_screen.dart';
import 'screens/health/blood_oxygen_screen.dart';
import 'screens/health/steps_screen.dart';
import 'screens/health/sleep_screen.dart';
import 'screens/health/hrv_screen.dart';
import 'screens/health/pressure_screen.dart';
import 'screens/health/temperature_screen.dart';
import 'screens/health/womens_health_screen.dart';
import 'screens/health/sport_record_screen.dart';
import 'screens/workouts/workouts_screen.dart';
import 'screens/settings/device_settings_screen.dart';
import 'screens/settings/health_settings_screen.dart';
import 'screens/settings/notification_settings_screen.dart';
import 'screens/settings/target_profile_screen.dart';
import 'screens/settings/display_settings_screen.dart';
import 'screens/settings/advanced_settings_screen.dart';
import 'screens/settings/touch_control_screen.dart';
import 'screens/reminders/drink_reminder_screen.dart';
import 'screens/reminders/sedentary_reminder_screen.dart';
import 'screens/ota/ota_screen.dart';
import 'screens/sugar_lipids/sugar_lipids_screen.dart';
import 'screens/settings/account_system_settings_screen.dart';
import 'screens/settings/profile_edit_screen.dart';
import 'theme/app_theme.dart';

class QRingApp extends StatelessWidget {
  const QRingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QRing',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme(),
      initialRoute: '/',
      routes: {
        '/': (_) => const SplashScreen(),
        '/home': (_) => const MainShell(),
        '/device-bind': (_) => const DeviceBindScreen(),
        '/heart-rate': (_) => const HeartRateScreen(),
        '/blood-pressure': (_) => const BloodPressureScreen(),
        '/blood-oxygen': (_) => const BloodOxygenScreen(),
        '/steps': (_) => const StepsScreen(),
        '/sleep': (_) => const SleepScreen(),
        '/hrv': (_) => const HrvScreen(),
        '/pressure': (_) => const PressureScreen(),
        '/temperature': (_) => const TemperatureScreen(),
        '/sport-record': (_) => const SportRecordScreen(),
        '/workouts': (_) => const WorkoutsScreen(),
        '/device-settings': (_) => const DeviceSettingsScreen(),
        '/health-settings': (_) => const HealthSettingsScreen(),
        '/notification-settings': (_) => const NotificationSettingsScreen(),
        '/target-profile': (_) => const TargetProfileScreen(),
        '/display-settings': (_) => const DisplaySettingsScreen(),
        '/advanced-settings': (_) => const AdvancedSettingsScreen(),
        '/touch-control': (_) => const TouchControlScreen(),
        '/drink-reminder': (_) => const DrinkReminderScreen(),
        '/sedentary-reminder': (_) => const SedentaryReminderScreen(),
        '/ota': (_) => const OtaScreen(),
        '/sugar-lipids': (_) => const SugarLipidsScreen(),
        '/womens-health': (_) => const WomensHealthScreen(),
        '/account-system-settings': (_) => const AccountSystemSettingsScreen(),
        '/profile-edit': (_) => const ProfileEditScreen(),
      },
    );
  }
}
