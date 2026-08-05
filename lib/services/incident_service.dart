import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'supabase_service.dart';

/// Central service for recording and forwarding application errors/incidents
/// to the Supabase `app_incidents` table.
class IncidentService {
  IncidentService._();

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
    try {
      // Never block UI / crash path on network; always log locally first.
      debugPrint('[IncidentService] $source: ${customMessage ?? error}');

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
        ...?extraInfo,
      };

      final payload = <String, dynamic>{
        'source': source,
        'error_type': error.runtimeType.toString(),
        'message': customMessage ?? error.toString(),
        'stack_trace': stackTrace?.toString(),
        'device_info': deviceInfo,
      };
      if (userId != null) {
        payload['user_id'] = userId;
      }

      await SupabaseService.client
          .from('app_incidents')
          .insert(payload)
          .timeout(const Duration(seconds: 5));
    } catch (e, st) {
      // Incident reporting itself must never throw or crash the host app.
      debugPrint('[IncidentService] Failed to record incident to Supabase: $e\n$st');
    }
  }
}
