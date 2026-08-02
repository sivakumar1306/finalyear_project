import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/ble_provider.dart';
import 'providers/workout_provider.dart';
import 'providers/alarm_mode_provider.dart';
import 'providers/prayer_session_provider.dart';
import 'providers/main_tab_provider.dart';
import 'providers/home_card_provider.dart';
import 'providers/fall_prediction/fall_prediction_provider.dart';
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
    Permission.sms,
    Permission.phone,
  ].request();
  try {
    await _bleChannel.invokeMethod('startForegroundService');
  } catch (e) {
    debugPrint('_requestPermissionsAndStartService: $e');
  }
}

Future<void> _syncLoggedInFlag() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('user_logged_in', SupabaseService.isLoggedIn);
  } catch (e) {
    debugPrint('_syncLoggedInFlag: $e');
  }
}

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
  } catch (e) {
    debugPrint('_configureNativeSync: $e');
  }
}

StreamSubscription? _authSub;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // All four families are bundled in pubspec (fonts/) — never fetch at runtime.
  GoogleFonts.config.allowRuntimeFetching = false;
  await Future.wait([
    SupabaseService.initialize(),
    _syncLoggedInFlag(),
  ]);
  await _configureNativeSync();
  _authSub?.cancel();
  _authSub = SupabaseService.client.auth.onAuthStateChange.listen((_) {
    _syncLoggedInFlag();
    _configureNativeSync();
  });
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BleProvider()),
        ChangeNotifierProvider(create: (_) => WorkoutProvider()),
        ChangeNotifierProvider(create: (_) => AlarmModeProvider()),
        ChangeNotifierProvider(create: (_) => PrayerSessionProvider()),
        ChangeNotifierProvider(create: (_) => MainTabProvider()),
        ChangeNotifierProvider(create: (_) => HomeCardProvider()..load()),
        ChangeNotifierProvider(create: (_) => FallPredictionProvider()),
      ],
      child: const QRingApp(),
    ),
  );
  unawaited(_requestPermissionsAndStartService());
}
