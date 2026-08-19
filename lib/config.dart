class AppConfig {
  AppConfig._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://wdmeriohkwlvsxyusgrp.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndkbWVyaW9oa3dsdnN4eXVzZ3JwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ3MzU0MTMsImV4cCI6MjEwMDMxMTQxM30.KLB2XrSE6Ofz_24KvARBOsfk78wCKkJ-e_X2TeIN7i0',
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
}
