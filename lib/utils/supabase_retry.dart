import 'dart:async';
import 'package:flutter/foundation.dart';

/// Retries [fn] up to [attempts] times with exponential backoff.
///
/// Default delays: 2 s → 6 s → 18 s.
/// Returns the result of the first successful call, or rethrows the last error
/// if all attempts fail.
Future<T> supabaseRetry<T>(
  Future<T> Function() fn, {
  int attempts = 3,
  Duration initialDelay = const Duration(seconds: 2),
  String? label,
}) async {
  var delay = initialDelay;
  for (var i = 0; i < attempts; i++) {
    try {
      return await fn();
    } catch (e) {
      if (i == attempts - 1) rethrow;
      debugPrint(
        'supabaseRetry${label != null ? " ($label)" : ""}: '
        'attempt ${i + 1} failed ($e), retrying in ${delay.inSeconds}s',
      );
      await Future<void>.delayed(delay);
      delay *= 3;
    }
  }
  throw StateError('unreachable');
}

/// Fire-and-forget wrapper: runs [fn] with retry, logs errors via
/// [onError] (defaults to [debugPrint]).  Never throws.
Future<void> supabaseRetryFireAndForget(
  Future<void> Function() fn, {
  int attempts = 3,
  Duration initialDelay = const Duration(seconds: 2),
  String? label,
  void Function(Object error, StackTrace st)? onError,
}) async {
  try {
    await supabaseRetry(
      fn,
      attempts: attempts,
      initialDelay: initialDelay,
      label: label,
    );
  } catch (e, st) {
    if (onError != null) {
      onError(e, st);
    } else {
      debugPrint(
        'supabaseRetryFireAndForget${label != null ? " ($label)" : ""} '
        'failed after $attempts attempts: $e',
      );
    }
  }
}
