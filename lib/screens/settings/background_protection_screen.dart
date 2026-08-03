import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';

/// Explains why the OS needs to be told not to kill this app in the
/// background, and links out to the system app-settings page so the user
/// can actually act on it — same openAppSettings() call already used by
/// device_bind_screen.dart / ring_scan_sheet.dart for permission prompts.
class BackgroundProtectionScreen extends StatelessWidget {
  const BackgroundProtectionScreen({super.key});

  static const _steps = [
    (
      icon: Icons.battery_charging_full_rounded,
      title: 'Disable battery optimization',
      body:
          'Some phones aggressively "optimize" apps running in the background, '
          'which can pause your ring\'s connection and stop readings mid-day. '
          'Excluding this app from battery optimization keeps it awake.',
    ),
    (
      icon: Icons.lock_open_rounded,
      title: 'Allow autostart',
      body:
          'On some Android skins (MIUI, ColorOS, EMUI and similar), apps '
          'need "Autostart" permission to reconnect to your ring after a '
          'phone restart or a period of inactivity.',
    ),
    (
      icon: Icons.push_pin_rounded,
      title: 'Keep it out of the recent-apps cleaner',
      body:
          'If your phone has a "clean up background apps" feature, exclude '
          'or lock this app so swiping it away in recents doesn\'t disconnect '
          'the ring.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: const GlassBackButton(),
        title: Text(
          'Background Protection',
          style: AppTypography.inter(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Text(
              'Keep your ring connected',
              style: AppTypography.inter(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Phone manufacturers often kill background apps to save '
              'battery — that can silently stop your ring from syncing '
              'heart rate, sleep, and other readings. A few quick settings '
              'changes prevent that.',
              style: AppTypography.inter(
                color: AppTheme.textSec,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            for (final step in _steps) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.gold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(step.icon, color: AppTheme.gold, size: 18),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.title,
                            style: AppTypography.inter(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            step.body,
                            style: AppTypography.inter(
                              color: AppTheme.textSec,
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: openAppSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.gold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  'Open App Settings',
                  style: AppTypography.inter(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
