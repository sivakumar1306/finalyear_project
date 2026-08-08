import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config.dart';
import '../services/prayer_schedule_prefs.dart';

int _msUntil(TimeOfDay target) {
  final now = DateTime.now();
  var targetTime =
      DateTime(now.year, now.month, now.day, target.hour, target.minute);
  if (targetTime.isBefore(now)) {
    targetTime = targetTime.add(const Duration(days: 1));
  }
  return targetTime.difference(now).inMilliseconds;
}

enum PhoneMode { focus, base, prayer }

enum PhoneModeResult { applied, needsDndAccess, unsupported }

/// Shared Focus / Base / Prayer mode state.
///
/// On Android, Focus mode puts the phone into Silent ringer mode and Prayer
/// mode enables system Do Not Disturb, via [_channel]. Both require the user
/// to have granted "Do Not Disturb access" in system settings first — Android
/// blocks ringer/notification-policy changes without it. iOS has no public
/// API for a third-party app to control system DND or Silent mode, so there
/// [setMode] only updates local state.
///
/// Prayer mode's "auto turn DND back off after 1 minute" timer is implemented
/// natively (PhoneModePlugin), not with a Dart Timer — a Dart Timer lives in
/// the Flutter engine's isolate, which Android can destroy when the app is
/// closed/swiped away even though the app's foreground service keeps the
/// process itself alive, so it would silently never fire.
class AlarmModeProvider extends ChangeNotifier {
  static const _channel = MethodChannel(AppConfig.phoneModeChannel);

  PhoneMode _mode = PhoneMode.focus;
  PhoneMode get mode => _mode;

  Future<bool> get isDndAccessGranted async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isDndAccessGranted') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openDndAccessSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openDndAccessSettings');
    } catch (_) {}
  }

  Future<PhoneModeResult> setMode(PhoneMode mode) async {
    if (!Platform.isAndroid) {
      _mode = mode;
      notifyListeners();
      return PhoneModeResult.unsupported;
    }
    if (!await isDndAccessGranted) {
      return PhoneModeResult.needsDndAccess;
    }
    try {
      switch (mode) {
        case PhoneMode.focus:
          await _channel.invokeMethod('setSilentMode', {'enabled': true});
          await _channel.invokeMethod('setDoNotDisturb', {'enabled': false});
          break;
        case PhoneMode.prayer:
          await _channel.invokeMethod('setSilentMode', {'enabled': false});
          final (_, end) = await PrayerSchedulePrefs.load();
          final ms = _msUntil(end);
          await _channel.invokeMethod('setDoNotDisturb', {
            'enabled': true,
            'autoOffDurationMs': ms,
          });
          break;
        case PhoneMode.base:
          await _channel.invokeMethod('setDoNotDisturb', {'enabled': false});
          await _channel.invokeMethod('setSilentMode', {'enabled': false});
          break;
      }
      // Ongoing, colorized notification mirroring the mode: a live stopwatch for Focus,
      // a countdown tied to the real DND auto-off timer for Prayer, none for Base.
      await _channel.invokeMethod('syncModeNotification', {'mode': mode.name});
    } catch (_) {}
    _mode = mode;
    notifyListeners();
    return PhoneModeResult.applied;
  }
}

/// Applies [mode] through [provider]; if the OS-level change needs the
/// Do Not Disturb permission first, prompts the user to grant it.
Future<void> requestPhoneMode(
  BuildContext context,
  AlarmModeProvider provider,
  PhoneMode mode,
) async {
  final result = await provider.setMode(mode);
  if (result == PhoneModeResult.needsDndAccess && context.mounted) {
    await _promptDndAccess(context, provider);
  }
}

Future<void> _promptDndAccess(BuildContext context, AlarmModeProvider provider) async {
  final openSettings = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF111111),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Do Not Disturb access needed',
        style: TextStyle(color: Colors.white),
      ),
      content: const Text(
        'Focus and Meditation modes change your phone\'s ringer and Do Not '
        'Disturb settings. Allow this app to manage Do Not Disturb to '
        'enable them.',
        style: TextStyle(color: Colors.white70),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Open Settings'),
        ),
      ],
    ),
  );

  if (openSettings == true) {
    await provider.openDndAccessSettings();
  }
}

