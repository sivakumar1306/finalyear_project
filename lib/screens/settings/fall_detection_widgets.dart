import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_typography.dart';

// Tier labels for display only — the actual score comes from the native
// FallRiskAnalyzer (see BleProvider.getFallRiskScore), not computed here.
enum FallTier { low, medium, high }

class EmergencyContact {
  final int? id;
  final String name;
  final String phone;
  EmergencyContact({this.id, required this.name, required this.phone});
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: AppTypography.inter(
          color: Colors.white.withValues(alpha: 0.35),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class HeroCard extends StatelessWidget {
  final FallTier tier;
  final String message;
  final int? smsSecondsRemaining;
  final bool smsHasPermission;
  final VoidCallback onPrimaryAction;

  const HeroCard({
    super.key,
    required this.tier,
    required this.message,
    this.smsSecondsRemaining,
    this.smsHasPermission = true,
    required this.onPrimaryAction,
  });

  @override
  Widget build(BuildContext context) {
    final countdown = smsSecondsRemaining;
    final isHigh = tier == FallTier.high || countdown != null;
    final accent = isHigh ? AppTheme.hrColor : AppTheme.tempColor;
    final title = countdown != null
        ? 'Emergency SMS in ${countdown}s'
        : (isHigh ? 'You might fall soon...' : 'We are concerned ...');
    final body = countdown != null
        ? (!smsHasPermission
              ? 'SMS permission is missing. Grant SEND_SMS so contacts can be alerted automatically.'
              : 'SMS will be sent to all emergency contacts in $countdown seconds unless you cancel. '
                    'You can also alert them immediately below.')
        : (isHigh
              ? 'We have detected multiple signs that you might fall down in the next 2-3 minutes. '
                    'Take a seat and contact your caretaker.'
              : message);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.25), width: 0.5),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.30), AppTheme.card],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                countdown != null ? 'EMERGENCY SMS' : 'FALL PREDICTION',
                style: AppTypography.inter(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: AppTypography.inter(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: AppTypography.inter(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          if (isHigh)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onPrimaryAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.14),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: Text(
                  countdown != null
                      ? 'Alert now (all contacts)'
                      : 'Alert emergency contact',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            )
          else
            Center(
              child: TextButton(
                onPressed: onPrimaryAction,
                child: Text(
                  'ignore',
                  style: AppTypography.inter(
                    color: AppTheme.danger,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const ActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.div),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: AppTypography.inter(color: Colors.white, fontSize: 14),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.3),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class ContactRow extends StatelessWidget {
  final EmergencyContact contact;
  final VoidCallback? onTap;
  const ContactRow({super.key, required this.contact, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.div),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_hospital_outlined,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                contact.name,
                style: AppTypography.inter(color: Colors.white, fontSize: 14),
              ),
            ),
            Text(
              contact.phone,
              style: AppTypography.inter(color: AppTheme.textSec, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class EditableRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  const EditableRow({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.div),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.edit_outlined,
                color: Colors.white,
                size: 15,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: AppTypography.inter(color: Colors.white, fontSize: 14),
              ),
            ),
            Flexible(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.inter(
                  color: AppTheme.textSec,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FormDialog extends StatelessWidget {
  final String title;
  final List<Widget> fields;
  final VoidCallback? onDelete;
  const FormDialog({super.key, required this.title, required this.fields, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.card2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      content: Column(mainAxisSize: MainAxisSize.min, children: fields),
      actions: [
        if (onDelete != null)
          TextButton(
            onPressed: () {
              Navigator.pop(context, false);
              onDelete!();
            },
            child: Text(
              'Delete',
              style: AppTypography.inter(color: AppTheme.danger),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            'Cancel',
            style: AppTypography.inter(color: AppTheme.textSec),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            'Save',
            style: AppTypography.inter(
              color: AppTheme.gold,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class AlertContactSheet extends StatelessWidget {
  final EmergencyContact contact;
  final int contactCount;
  const AlertContactSheet({super.key, required this.contact, this.contactCount = 1});

  @override
  Widget build(BuildContext context) {
    final smsLabel = contactCount > 1
        ? 'Message all $contactCount contacts'
        : 'Message ${contact.name}';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Alert emergency contacts',
              style: AppTypography.inter(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Call opens the dialer for ${contact.name}. Message sends SMS to every saved contact.',
              style: AppTypography.inter(
                color: AppTheme.textSec,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            ActionRow(
              icon: Icons.call_rounded,
              label: 'Call ${contact.name}',
              onTap: () => Navigator.pop(context, 'call'),
            ),
            const SizedBox(height: 8),
            ActionRow(
              icon: Icons.message_rounded,
              label: smsLabel,
              onTap: () => Navigator.pop(context, 'message'),
            ),
          ],
        ),
      ),
    );
  }
}

class FallHistorySheet extends StatelessWidget {
  final List<Map<String, dynamic>> events;
  const FallHistorySheet({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, HH:mm');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fall history',
              style: AppTypography.inter(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Logged by the on-device motion detector — real events only.',
              style: AppTypography.inter(color: AppTheme.textSec, fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (events.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No fall events logged yet.',
                  style: AppTypography.inter(
                    color: AppTheme.textSec,
                    fontSize: 13,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: events.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final e = events[i];
                    final detectedAt = (e['detectedAt'] as num?)?.toInt() ?? 0;
                    final confidence = ((e['confidence'] as num?) ?? 0)
                        .toDouble();
                    final corroborated = e['corroborated'] as bool? ?? false;
                    final source =
                        e['corroborationSource'] as String? ?? 'none';
                    final eventType = e['eventType'] as String? ?? 'DETECTED';
                    final isPrediction = eventType == 'PREDICTED';
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.div),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isPrediction
                                ? Icons.trending_up_rounded
                                : (corroborated
                                      ? Icons.warning_amber_rounded
                                      : Icons.help_outline_rounded),
                            color: isPrediction
                                ? AppTheme.tempColor
                                : (corroborated
                                      ? AppTheme.hrColor
                                      : AppTheme.textSec),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  detectedAt > 0
                                      ? fmt.format(
                                          DateTime.fromMillisecondsSinceEpoch(
                                            detectedAt,
                                          ),
                                        )
                                      : 'Unknown time',
                                  style: AppTypography.inter(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  isPrediction
                                      ? 'Predicted fall risk'
                                      : (corroborated
                                            ? 'Confirmed by $source'
                                            : 'Not confirmed'),
                                  style: AppTypography.inter(
                                    color: AppTheme.textSec,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${(confidence * 100).toInt()}%',
                            style: AppTypography.inter(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ToggleRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const ToggleRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.div),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.card2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppTheme.iconFaint, size: 17),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Transform.scale(
              scale: 0.85,
              child: Switch(value: value, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}