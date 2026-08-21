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
import 'screens/workouts/workouts_screen.dart';
import 'screens/settings/device_settings_screen.dart';
import 'screens/settings/health_settings_screen.dart';
import 'screens/settings/notification_settings_screen.dart';
import 'screens/settings/target_profile_screen.dart';
import 'screens/settings/display_settings_screen.dart';
import 'screens/settings/advanced_settings_screen.dart';
import 'screens/settings/touch_control_screen.dart';
import 'screens/settings/gesture_settings_screen.dart';
import 'screens/settings/alarms_notifications_screen.dart';
import 'screens/settings/select_notifications_screen.dart';
import 'screens/settings/fall_detection_screen.dart';
import 'screens/reminders/ring_reminder_screen.dart';
import 'screens/ota/ota_screen.dart';
import 'screens/sugar_lipids/sugar_lipids_screen.dart';
import 'screens/settings/account_system_settings_screen.dart';
import 'screens/settings/profile_edit_screen.dart';
import 'screens/settings/faq_screen.dart';
import 'screens/prayer/prayer_session_screen.dart';
import 'screens/companion/companion_alert_screen.dart';
import 'theme/app_theme.dart';
import 'theme/app_scroll_behavior.dart';

class SundrApp extends StatelessWidget {
  const SundrApp({super.key});

  /// Global navigator key — lets headless services (FCM push, background
  /// handlers) navigate without a BuildContext.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SUNDR',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme(),
      scrollBehavior: const AppScrollBehavior(),
      navigatorKey: navigatorKey,
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
        '/workouts': (_) => const WorkoutsScreen(),
        '/device-settings': (_) => const DeviceSettingsScreen(),
        '/health-settings': (_) => const HealthSettingsScreen(),
        '/notification-settings': (_) => const NotificationSettingsScreen(),
        '/target-profile': (_) => const TargetProfileScreen(),
        '/display-settings': (_) => const DisplaySettingsScreen(),
        '/advanced-settings': (_) => const AdvancedSettingsScreen(),
        '/touch-control': (_) => const TouchControlScreen(),
        '/gesture-settings': (_) => const GestureSettingsScreen(),
        '/alarms-notifications': (_) => const AlarmsNotificationsScreen(),
        '/select-notifications': (_) => const SelectNotificationsScreen(),
        '/fall-detection': (_) => const FallDetectionScreen(),
        '/drink-reminder': (_) =>
            const RingReminderScreen(type: RingReminderType.drink),
        '/sedentary-reminder': (_) =>
            const RingReminderScreen(type: RingReminderType.sedentary),
        '/ota': (_) => const OtaScreen(),
        '/sugar-lipids': (_) => const SugarLipidsScreen(),
        '/womens-health': (_) => const WomensHealthScreen(),
        '/account-system-settings': (_) => const AccountSystemSettingsScreen(),
        '/profile-edit': (_) => const ProfileEditScreen(),
        '/faq': (_) => const FaqScreen(),
        '/prayer-session': (_) => const PrayerSessionScreen(),
        '/companion-alert': (_) => const CompanionAlertScreen(),
      },
    );
  }
}
