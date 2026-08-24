class AppConfig {
  AppConfig._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://eixcdjvfbwrziudieodr.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVpeGNkanZmYndyeml1ZGllb2RyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAzMTUzOTcsImV4cCI6MjA5NTg5MTM5N30.7rxoCLO39zQv1ExFL3IXp0JWySt-_p1iq7CEScufdXA',
  );

  static const String chatApiBaseUrl = String.fromEnvironment(
    'CHAT_API_BASE_URL',
    defaultValue:
        'https://vtialringbackendversion1-production-a3e4.up.railway.app/api/v1',
  );
  static const String packagePrefix = 'com.sundr.myapp';
  static const String bleMethodChannel = '$packagePrefix/ble';
  static const String bleEventChannel = '$packagePrefix/ble_events';
  static const String phoneModeChannel = '$packagePrefix/phone_mode';

  // ── Firebase Cloud Messaging (companion in-app alerts, Part 3 of the
  // emergency-alerting plan) ─────────────────────────────────────────────────
  // Initialized manually (no google-services.json / gradle plugin needed): the
  // client supplies these values from the Firebase project settings, either via
  // --dart-define or by editing the defaults here. While empty, FCM stays
  // gracefully dormant — everything else keeps working.
  static const String firebaseApiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: '',
  );
  static const String firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: '',
  );
  static const String firebaseMessagingSenderId = String.fromEnvironment(
    'FIREBASE_SENDER_ID',
    defaultValue: '',
  );
  static const String firebaseAppId = String.fromEnvironment(
    'FIREBASE_APP_ID',
    defaultValue: '',
  );

  static bool get firebaseConfigured =>
      firebaseApiKey.isNotEmpty &&
      firebaseProjectId.isNotEmpty &&
      firebaseMessagingSenderId.isNotEmpty &&
      firebaseAppId.isNotEmpty;
}
