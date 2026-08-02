import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../screens/prayer/prayer_session_screen.dart';
import '../theme/app_theme.dart';

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
  static const _channel = MethodChannel('com.medxai.qring/phone_mode');

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
          // autoOffAfterOneMinute tells the native side to schedule its own
          // (process-lifetime) timer to flip DND back off — see class doc.
          await _channel.invokeMethod('setDoNotDisturb', {
            'enabled': true,
            'autoOffAfterOneMinute': true,
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
  if (mode == PhoneMode.prayer) {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF161616),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.gold.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.gold.withValues(alpha: 0.6)),
                  ),
                  child: const Icon(Icons.self_improvement_rounded, color: AppTheme.gold, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Prayer Mode Session',
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Select your preferred Prayer Session style. Both modes activate Do Not Disturb and track 13 dynamic vitals:',
              style: GoogleFonts.inter(color: AppTheme.textSec, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 20),

            // Option 1: Sedentary Prayer Mode
            InkWell(
              onTap: () => Navigator.pop(ctx, 'track'),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.gold.withValues(alpha: 0.7), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: AppTheme.gold.withValues(alpha: 0.15), blurRadius: 10),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.gold.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.chair_rounded, color: AppTheme.gold, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sedentary Prayer Mode',
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Stillness meditation & deep calm tracking',
                            style: GoogleFonts.inter(color: AppTheme.textSec, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.gold, size: 16),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Option 2: Freestyle Prayer Mode
            InkWell(
              onTap: () => Navigator.pop(ctx, 'track'),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x33FFFFFF)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.directions_walk_rounded, color: Colors.white70, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Freestyle Prayer Mode',
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Active motion & vitals prayer tracking',
                            style: GoogleFonts.inter(color: AppTheme.textSec, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 16),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white38)),
              ),
            ),
          ],
        ),
      ),
    );

    if (choice == 'cancel' || choice == null || !context.mounted) return;

    final result = await provider.setMode(PhoneMode.prayer);
    if (result == PhoneModeResult.needsDndAccess && context.mounted) {
      await _promptDndAccess(context, provider);
      return;
    }

    if (choice == 'track' && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const _PrayerSessionRouteWrapper(),
        ),
      );
    }
    return;
  }

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
        'Focus and Prayer modes change your phone\'s ringer and Do Not '
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

class _PrayerSessionRouteWrapper extends StatelessWidget {
  const _PrayerSessionRouteWrapper();

  @override
  Widget build(BuildContext context) {
    return const PrayerSessionScreen();
  }
}
