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

  // The AI agent runs on a laptop on the same Wi-Fi. Set the address at
  // build time, or from the server button in AI Assist (saved on device).
  static const String chatApiBaseUrl = String.fromEnvironment(
    'CHAT_API_BASE_URL',
    defaultValue: '',
  );
  static const String packagePrefix = 'com.sundr.myapp';
  static const String bleMethodChannel = '$packagePrefix/ble';
  static const String bleEventChannel = '$packagePrefix/ble_events';

  static const bool includeMeasurementLog = bool.fromEnvironment(
    'INCLUDE_MEASUREMENT_LOG',
    defaultValue: false,
  );
}
