import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'supabase_service.dart';

/// Central service for recording and forwarding application errors/incidents
/// to the Supabase `app_incidents` table.
///
/// Hardening (eval 05.4 / 08.4):
/// * **PII scrub** — phone numbers, e-mail addresses, JWT/API tokens and
///   `Bearer …` headers are redacted from messages and stack traces before
///   anything leaves the device.
/// * **Environment marker** — payloads carry `app_env` (production / staging /
///   development) so the table can be filtered and dev/test noise excluded.
/// * **Rate limit + dedupe** — per-source limits (default 10/min) and an
///   identical-message dedupe window (60 s) keep crash loops from flooding the
///   table; a tight cap on message/stack length bounds payload size.
class IncidentService {
  IncidentService._();

  /// Override via `--dart-define=APP_ENV=staging`; otherwise inferred from the
  /// build mode (debug/profile builds report as `development`).
  static const String _envOverride = String.fromEnvironment('APP_ENV');

  static String get environment {
    if (_envOverride.isNotEmpty) return _envOverride;
    return kReleaseMode ? 'production' : 'development';
  }

  static const Duration _rateWindow = Duration(seconds: 60);
  static const int _rateLimitPerSource = 10;
  static const Duration _dedupeWindow = Duration(seconds: 60);
  static const int _maxMessageLength = 2000;
  static const int _maxStackTraceLength = 8000;

  /// last report time per source (rate limiting)
  static final Map<String, List<DateTime>> _sourceTimestamps = {};

  /// recent `source|message` fingerprints (dedupe)
  static final List<({String fingerprint, DateTime at})> _recent = [];

  static final RegExp _phoneRegExp = RegExp(r'\+?\d[\d\s\-().]{7,}\d');
  static final RegExp _emailRegExp = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+');
  static final RegExp _jwtRegExp =
      RegExp(r'eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}');
  static final RegExp _bearerRegExp = RegExp(r'Bearer\s+[A-Za-z0-9_\-\.]+');

  /// Report an error or incident to Supabase.
  ///
  /// [source] describes the component originating the error:
  /// e.g. 'flutter_ui', 'flutter_async', 'android_native'.
  /// [error] is the exception or error object.
  /// [stackTrace] optional stacktrace associated with the error.
  /// [customMessage] optional descriptive message.
  static Future<void> reportIncident({
    required String source,
    required Object error,
    StackTrace? stackTrace,
String? customMessage,
    Map<String, dynamic>? extraInfo,
  }) async {
    // Never block UI / crash path on network; always log locally first.
    debugPrint('[IncidentService] $source: ${customMessage ?? error}');

    if (!_allow(source, customMessage ?? error.toString())) return;

    final message =
        _scrub(customMessage ?? error.toString()).substringSafe(_maxMessageLength);
    final stack = _scrub(stackTrace?.toString()).substringSafe(_maxStackTraceLength);

    String? userId;
    try {
      userId = SupabaseService.client.auth.currentUser?.id;
    } catch (_) {
      // Supabase may not be initialized yet during early bootstrap crashes.
    }

    final deviceInfo = <String, dynamic>{
      'platform': kIsWeb ? 'web' : Platform.operatingSystem,
      'os_version': kIsWeb ? 'browser' : Platform.operatingSystemVersion,
      'is_web': kIsWeb,
      'app_env': environment,
      ...?extraInfo,
    };

    final payload = <String, dynamic>{
      'source': source,
      'error_type': error.runtimeType.toString(),
      'message': message,
      'stack_trace': stack,
      'device_info': deviceInfo,
    };
    if (userId != null) {
      payload['user_id'] = userId;
    }

    try {
      await SupabaseService.client
          .from('app_incidents')
          .insert(payload)
          .timeout(const Duration(seconds: 5));
    } catch (e, st) {
      // Incident reporting itself must never throw or crash the host app.
      debugPrint('[IncidentService] Failed to record incident to Supabase: $e\n$st');
    }
  }

  /// Fire-and-forget variant for non-critical catch blocks that must not
  /// block the caller; failures inside reporting are swallowed internally.
  static void reportUnhandled({
    required String source,
    required Object error,
    StackTrace? stackTrace,
    String? customMessage,
    Map<String, dynamic>? extraInfo,
  }) {
    unawaited(
      reportIncident(
        source: source,
        error: error,
        stackTrace: stackTrace,
        customMessage: customMessage,
        extraInfo: extraInfo,
      ),
    );
  }

  /// Redact PII from any free-text payload (message / stack trace).
  static String _scrub(String? input) {
    if (input == null || input.isEmpty) return '';
    return input
        .replaceAll(_jwtRegExp, '[REDACTED_TOKEN]')
        .replaceAll(_bearerRegExp, '[REDACTED_TOKEN]')
        .replaceAll(_emailRegExp, '[REDACTED_EMAIL]')
        .replaceAll(_phoneRegExp, '[REDACTED_PHONE]');
  }

  /// Per-source rate limit + identical-message dedupe. Returns true when the
  /// incident should be reported.
  static bool _allow(String source, String message) {
    final now = DateTime.now();

    final hits = (_sourceTimestamps[source] ?? [])
        .where((t) => now.difference(t) < _rateWindow)
        .toList();
    if (hits.length >= _rateLimitPerSource) return false;
    hits.add(now);
    _sourceTimestamps[source] = hits;

    final fingerprint = '$source|$message';
    _recent.removeWhere((e) => now.difference(e.at) >= _dedupeWindow);
    if (_recent.any((e) => e.fingerprint == fingerprint)) return false;
    _recent.add((fingerprint: fingerprint, at: now));
    if (_recent.length > 64) _recent.removeRange(0, _recent.length - 64);

    return true;
  }
}

extension on String {
  String substringSafe(int max) => length <= max ? this : substring(0, max);
}
