import 'package:flutter/material.dart';

/// True if [error] looks like a network-connectivity failure (no wifi/data,
/// DNS lookup failed, connection refused/timed out) rather than a genuine
/// "no rows for this query" result — lets screens tell "you're offline" apart
/// from "there's nothing here" instead of collapsing both into a blank state.
bool isNetworkError(Object error) {
  final s = error.toString().toLowerCase();
  return s.contains('socketexception') ||
      s.contains('failed host lookup') ||
      s.contains('network is unreachable') ||
      s.contains('connection refused') ||
      s.contains('connection reset') ||
      s.contains('connection closed') ||
      s.contains('clientexception') ||
      s.contains('timeoutexception') ||
      s.contains('handshakeexception');
}

/// Compact "connect to wifi to load this" banner for history/trend sections
/// that depend on Supabase and have nothing cached locally to fall back to.
class OfflineNotice extends StatelessWidget {
  final String message;
  const OfflineNotice({super.key, this.message = 'Connect to WiFi to load'});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, color: Colors.white.withValues(alpha: 0.4), size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
