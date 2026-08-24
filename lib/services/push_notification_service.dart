import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app.dart';
import '../config.dart';
import '../theme/app_theme.dart';
import '../widgets/app_typography.dart';
import 'supabase_service.dart';

/// Background isolate handler — must be a top-level function.
/// The send-emergency-alert function always includes a notification payload, so
/// while backgrounded/terminated the system tray displays the alert itself; this
/// handler only keeps data-only messages from crashing the background isolate.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[Push] background message: ${message.messageId}');
}

/// Part 3 of the emergency-alerting plan (docs/sms/emergency-alerting-system.md):
/// registers this device's FCM token so linked companions can be alerted instantly,
/// and routes incoming companion alerts to the in-app alert screen.
///
/// Firebase is initialized manually from [AppConfig] values (no
/// google-services.json / gradle plugin). While those constants are empty the
/// whole service stays gracefully dormant — no crashes, no behavior change.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  bool _initialized = false;
  StreamSubscription<AuthState>? _authSub;

  bool get enabled => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    if (!AppConfig.firebaseConfigured) {
      debugPrint('[Push] Firebase not configured — companion alerts dormant');
      return;
    }
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: AppConfig.firebaseApiKey,
          appId: AppConfig.firebaseAppId,
          messagingSenderId: AppConfig.firebaseMessagingSenderId,
          projectId: AppConfig.firebaseProjectId,
        ),
      );
    } catch (e) {
      debugPrint('[Push] Firebase init failed (companion alerts dormant): $e');
      return;
    }
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Token registration + refresh → user_push_tokens (upsert).
    FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) => unawaited(_registerToken(token)),
    );
    await syncToken();

    // Re-register whenever the user signs in (token is user-scoped server-side).
    try {
      _authSub?.cancel();
      _authSub = SupabaseService.client.auth.onAuthStateChange.listen((state) {
        if (state.event == AuthChangeEvent.signedIn) {
          unawaited(syncToken());
        }
      });
    } catch (e) {
      debugPrint('[Push] auth listener failed: $e');
    }

    // Foreground: system tray does not auto-show — surface an in-app dialog.
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Tapped tray notification while app was backgrounded / terminated.
    FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _openAlert(message.data),
    );
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _openAlert(initial.data);
    } catch (_) {}
  }

  /// Fetches (or re-fetches) the current FCM token and registers it for the
  /// signed-in user. Safe to call repeatedly.
  Future<void> syncToken() async {
    if (!_initialized) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _registerToken(token);
    } catch (e) {
      debugPrint('[Push] getToken failed: $e');
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      final client = SupabaseService.client;
      final user = client.auth.currentUser;
      if (user == null) return; // logged out — nothing to attach to
      await client.from('user_push_tokens').upsert({
        'user_id': user.id,
        'fcm_token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      }, onConflict: 'user_id,fcm_token');
      debugPrint('[Push] token registered');
    } catch (e) {
      debugPrint('[Push] token registration failed: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final context = SundrApp.navigatorKey.currentContext;
    if (context == null) return;
    final data = Map<String, dynamic>.from(message.data);
    final name = (data['wearerName'] as String?) ?? 'A friend';
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.card2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.emergency_rounded, color: AppTheme.danger, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Text('$name needs help', style: AppTypography.inter(fontSize: 16, weight: FontWeight.w600))),
          ],
        ),
        content: Text(
          message.notification?.body ??
              'An emergency alert was triggered. Open it for details and location.',
          style: AppTypography.inter(fontSize: 13, color: AppTheme.textSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Dismiss', style: AppTypography.inter(fontSize: 13, color: AppTheme.textTertiary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _openAlert(data);
            },
            child: Text('View', style: AppTypography.inter(fontSize: 13, weight: FontWeight.w600, color: AppTheme.gold)),
          ),
        ],
      ),
    );
  }

  void _openAlert(Map<String, dynamic> data) {
    SundrApp.navigatorKey.currentState?.pushNamed(
      '/companion-alert',
      arguments: Map<String, dynamic>.from(data),
    );
  }
}
