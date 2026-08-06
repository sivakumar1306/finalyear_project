import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'services/incident_service.dart';
import 'config.dart';
import 'app.dart';

const _bleChannel = MethodChannel(AppConfig.bleMethodChannel);

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

  final imageCache = PaintingBinding.instance.imageCache;
  imageCache.maximumSize = 80;
  imageCache.maximumSizeBytes = 40 << 20; // 40 MB

  // Capture Flutter UI / layout framework errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    IncidentService.reportIncident(
      source: 'flutter_ui',
      error: details.exception,
      stackTrace: details.stack,
      customMessage: details.summary.toString(),
    );
  };

  // Capture uncaught async / isolate errors
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    IncidentService.reportIncident(
      source: 'flutter_async',
      error: error,
      stackTrace: stack,
    );
    return true;
  };

  await Future.wait([SupabaseService.initialize(), _syncLoggedInFlag()]);
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
        ChangeNotifierProxyProvider<BleProvider, FallPredictionProvider>(
          create: (_) => FallPredictionProvider(),
          update: (_, ble, fall) => fall!..updateBleProvider(ble),
        ),
      ],
      child: const QRingApp(),
    ),
  );
  unawaited(_requestPermissionsAndStartService());
}
