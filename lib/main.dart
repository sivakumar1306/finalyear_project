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
import 'services/ble_service.dart';
import 'config.dart';
import 'app.dart';

const _bleChannel = MethodChannel(AppConfig.bleMethodChannel);

Future<void> _reportLastNativeCrash() async {
  try {
    final crash = await BleService().getLastNativeCrash();
    if (crash == null) return;
    final message = crash['message']?.toString() ?? 'native crash';
    final source = crash['source']?.toString() ?? 'android_native';
    await IncidentService.reportIncident(
      source: 'android_native',
      error: message,
      customMessage: source,
      extraInfo: crash,
    );
    await BleService().clearLastNativeCrash();
  } catch (e) {
    debugPrint('_reportLastNativeCrash: $e');
  }
}

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
  // Zone guard: uncaught Dart errors (including from plugins) are reported but
  // must not tear down the isolate if we can keep the UI alive.
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.maximumSize = 80;
    imageCache.maximumSizeBytes = 40 << 20; // 40 MB

    // Capture Flutter UI / layout framework errors (e.g. missing assets) without
    // treating them as fatal process kills.
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      unawaited(
        IncidentService.reportIncident(
          source: 'flutter_ui',
          error: details.exception,
          stackTrace: details.stack,
          customMessage: details.summary.toString(),
        ),
      );
    };

    // Capture uncaught async / isolate errors — return true = "handled".
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      unawaited(
        IncidentService.reportIncident(
          source: 'flutter_async',
          error: error,
          stackTrace: stack,
        ),
      );
      return true;
    };

    ErrorWidget.builder = (FlutterErrorDetails details) {
      // Prefer a blank error tile over a red crash screen for production UX.
      return const SizedBox.shrink();
    };

    try {
      await Future.wait([SupabaseService.initialize(), _syncLoggedInFlag()]);
      await _configureNativeSync();
    } catch (e, st) {
      debugPrint('Startup init failed (continuing offline): $e\n$st');
    }

    unawaited(_reportLastNativeCrash());

    _authSub?.cancel();
    try {
      _authSub = SupabaseService.client.auth.onAuthStateChange.listen((_) {
        unawaited(_syncLoggedInFlag());
        unawaited(_configureNativeSync());
      });
    } catch (e) {
      debugPrint('Auth listener setup failed: $e');
    }

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
  }, (Object error, StackTrace stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
    unawaited(
      IncidentService.reportIncident(
        source: 'flutter_zone',
        error: error,
        stackTrace: stack,
      ),
    );
  });
}
