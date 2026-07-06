import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'providers/ble_provider.dart';
import 'providers/workout_provider.dart';
import 'providers/alarm_mode_provider.dart';
import 'services/supabase_service.dart';
import 'app.dart';

const _bleChannel = MethodChannel('com.medxai.qring/ble');

Future<void> _requestPermissionsAndStartService() async {
  await [
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.bluetoothAdvertise,
    Permission.locationWhenInUse,
    Permission.notification,
  ].request();
  // Start the BLE foreground service now that permissions are granted.
  // Safe to call repeatedly — the service is sticky and ignores duplicate starts.
  try {
    await _bleChannel.invokeMethod('startForegroundService');
  } catch (_) {}
}

// Caches Supabase config natively so the background MeasurementLoopManager/
// SupabaseSyncManager (running inside BleConnectionService) can push local Room data
// independent of whether the Dart engine is currently running. Re-called on every auth
// state change since native code can't refresh the session token on its own.
Future<void> _configureNativeSync() async {
  final user = SupabaseService.currentUser;
  if (user == null) return;
  try {
    await _bleChannel.invokeMethod('configureSync', {
      'url': SupabaseService.url,
      'anonKey': SupabaseService.anonKey,
      'userId': user.id,
      'accessToken': SupabaseService.accessToken,
    });
    await _bleChannel.invokeMethod('setMasterLoopEnabled', {'enabled': true});
    await _bleChannel.invokeMethod('setSyncEnabled', {'enabled': true});
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _requestPermissionsAndStartService();
  await SupabaseService.initialize();
  await _configureNativeSync();
  SupabaseService.client.auth.onAuthStateChange.listen((_) => _configureNativeSync());
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BleProvider()),
        ChangeNotifierProvider(create: (_) => WorkoutProvider()),
        ChangeNotifierProvider(create: (_) => AlarmModeProvider()),
      ],
      child: const QRingApp(),
    ),
  );
}
