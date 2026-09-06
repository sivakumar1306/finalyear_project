import 'package:flutter/widgets.dart';

/// Mixin to guard async gaps in health screens.
/// Prevents `setState() called after dispose()` floods seen in app_incidents
/// (`_SleepScreenState._loadDayFromDb:225` 18 rows).
mixin MountedGuard<T extends StatefulWidget> on State<T> {
  /// Returns false when disposed; call before every setState after await.
  bool get isAlive => mounted;

  /// Safe setState — no-op when disposed.
  void safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }
}
