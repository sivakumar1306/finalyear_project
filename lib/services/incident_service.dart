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
      final user = SupabaseService.client.auth.currentUser;
      final userId = user?.id;

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

      debugPrint('[IncidentService] Reporting incident to Supabase: ${payload['message']}');

      await SupabaseService.client.from('app_incidents').insert(payload);
    } catch (e, st) {
      // Incident reporting itself must never throw or crash the host app.
      debugPrint('[IncidentService] Failed to record incident to Supabase: $e\n$st');
    }
  }
}
