import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/ble_provider.dart';
import 'providers/main_tab_provider.dart';
import 'providers/fall_prediction/fall_prediction_provider.dart';
import 'services/supabase_service.dart';
import 'services/incident_service.dart';
import 'services/ble_service.dart';
import 'services/health_engine/health_config.dart';
import 'config.dart';
import 'app.dart';
import 'theme/app_theme.dart';

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
  // POST_NOTIFICATIONS separately so denial can prompt settings (foreground service needs it on API 33+).
  try {
    final notif = await Permission.notification.status;
    if (notif.isDenied || notif.isLimited) {
      final res = await Permission.notification.request();
      if (res.isPermanentlyDenied) {
        debugPrint('_requestPermissions: notification permanently denied — Home will show battery/background prompt');
      }
    }
  } catch (e) {
    debugPrint('_requestPermissions notification check: $e');
  }
  await [
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.bluetoothAdvertise,
    Permission.locationWhenInUse,
  ].request();
  try {
    await _bleChannel.invokeMethod('startForegroundService');
  } on PlatformException catch (e) {
    // Android 12+ background-start restriction → non-foreground fallback (15m WorkManager interval).
    debugPrint('_requestPermissionsAndStartService FGS fallback: ${e.code} ${e.message}');
  } catch (e) {
    debugPrint('_requestPermissionsAndStartService: $e');
  }
}

/// Sets the native login flag only when a session is actually present.
/// A null currentUser during restore must not clear a flag that was true.
Future<void> _syncLoggedInFlag() async {
  try {
    if (!SupabaseService.isLoggedIn) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('user_logged_in', true);
  } catch (e) {
    debugPrint('_syncLoggedInFlag: $e');
  }
}

Future<void> _clearLoggedInFlag() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('user_logged_in', false);
  } catch (e) {
    debugPrint('_clearLoggedInFlag: $e');
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
    // Uploader returns immediately and no-ops until the network is validated.
    await _bleChannel.invokeMethod('forceSyncNow');
  } catch (e) {
    debugPrint('_configureNativeSync: $e');
  }
}

StreamSubscription? _authSub;
Timer? _nativeSyncRefreshTimer;

void main() async {
  // Zone guard: uncaught Dart errors (including from plugins) are reported but
  // must not tear down the isolate if we can keep the UI alive.
  await runZonedGuarded(
    () async {
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
        // Visible (but non-alarming) error tile instead of a blank section — users
        // must know a widget crashed. The incident itself is reported via onError.
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.danger.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppTheme.danger,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Something went wrong rendering this section.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        );
      };

      // Thresholds from disk, then the first frame. The remote config and the
      // native uploader continue after the UI is up.
      await HealthConfig.loadCached();
      try {
        await SupabaseService.initialize();
        unawaited(HealthConfig.load());
        unawaited(_configureNativeSync());
        unawaited(_syncLoggedInFlag());
      } catch (e, st) {
        debugPrint('Startup init failed (continuing offline): $e\n$st');
      }

      unawaited(_reportLastNativeCrash());

      _authSub?.cancel();
      try {
        _authSub = SupabaseService.client.auth.onAuthStateChange.listen((state) {
          if (state.event.name == 'signedOut') {
            unawaited(_clearLoggedInFlag());
          } else {
            unawaited(_syncLoggedInFlag());
          }
          unawaited(_configureNativeSync());
        });
      } catch (e) {
        debugPrint('Auth listener setup failed: $e');
      }

      // Periodic JWT refresh for native sync — Supabase JWTs expire after ~1 h;
      // re-push credentials to the native SupabaseSyncManager every 30 min so
      // background pushes never start failing with 401.
      _nativeSyncRefreshTimer?.cancel();
      _nativeSyncRefreshTimer = Timer.periodic(
        const Duration(minutes: 30),
        (_) => unawaited(_configureNativeSync()),
      );

      runApp(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => BleProvider()),
            ChangeNotifierProvider(create: (_) => MainTabProvider()),
            ChangeNotifierProxyProvider<BleProvider, FallPredictionProvider>(
              create: (_) => FallPredictionProvider(),
              update: (_, ble, fall) => fall!..updateBleProvider(ble),
            ),
          ],
          child: const VitalApp(),
        ),
      );
      unawaited(_requestPermissionsAndStartService());
    },
    (Object error, StackTrace stack) {
      debugPrint('Uncaught zone error: $error\n$stack');
      unawaited(
        IncidentService.reportIncident(
          source: 'flutter_zone',
          error: error,
          stackTrace: stack,
        ),
      );
    },
  );
}
