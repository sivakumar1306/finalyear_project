import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/glass_back_button.dart';

/// Full-screen view of a companion emergency alert (Part 3 of the alerting plan).
/// Opened when a linked companion taps an FCM notification, or from the
/// foreground alert dialog. Payload keys come from the send-emergency-alert
/// edge function: {wearerName, reason, mapsUrl, wearerPhone, alertId}.
class CompanionAlertScreen extends StatelessWidget {
  const CompanionAlertScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ??
            const {};
    final wearerName = (args['wearerName'] as String?) ?? 'A friend';
    final reason = (args['reason'] as String?) ?? 'manual';
    final mapsUrl = (args['mapsUrl'] as String?) ?? '';
    final wearerPhone = (args['wearerPhone'] as String?) ?? '';

    final reasonLabel = switch (reason) {
      'fall' => 'POSSIBLE FALL DETECTED',
      'prediction' => 'FALL RISK ALERT',
      _ => 'NEEDS HELP',
    };

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const GlassBackButton(),
                  const SizedBox(width: 12),
                  Text(
                    'Emergency Alert',
                    style: AppTypography.inter(fontSize: 20, weight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.glassCard,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppTheme.danger.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppTheme.danger.withValues(alpha: 0.14),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.emergency_rounded,
                                  color: AppTheme.danger,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$wearerName needs help',
                                      style: AppTypography.inter(
        fontSize: 18,
                                        weight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      reasonLabel,
                                      style: AppTypography.inter(
        fontSize: 11,
                                        weight: FontWeight.w700,
                                        color: AppTheme.danger,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'SUNDR detected a possible emergency for $wearerName. '
                            'Please reach out and check on them as soon as possible.',
                            style: AppTypography.inter(
        fontSize: 13,
                              height: 1.5,
                              color: AppTheme.textSec,
                            ),
                          ),
                          if (mapsUrl.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _ActionRow(
                              icon: Icons.map_rounded,
                              label: 'Open live location',
                              onTap: () async {
                                final uri = Uri.parse(mapsUrl);
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                }
                              },
                            ),
                          ],
                          if (wearerPhone.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _ActionRow(
                              icon: Icons.phone_rounded,
                              label: 'Call $wearerName',
                              onTap: () async {
                                final uri = Uri(
                                  scheme: 'tel',
                                  path: wearerPhone,
                                );
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri);
                                }
                              },
                            ),
                          ],
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              DateFormat(
                                'd MMM yyyy · h:mm a',
                              ).format(DateTime.now()),
                              style: AppTypography.inter(
        fontSize: 11,
                                color: AppTheme.textTertiary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppTheme.glassButton,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppTheme.glassButtonBorder),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.gold, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label, style: AppTypography.inter(fontSize: 13, weight: FontWeight.w500)),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.textTertiary,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
