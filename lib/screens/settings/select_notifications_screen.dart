import 'package:flutter/material.dart';
import '../../services/notification_prefs.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';

class SelectNotificationsScreen extends StatefulWidget {
  const SelectNotificationsScreen({super.key});

  @override
  State<SelectNotificationsScreen> createState() => _SelectNotificationsScreenState();
}

class _SelectNotificationsScreenState extends State<SelectNotificationsScreen> {
  Map<String, bool> _alerts = Map.of(NotificationPrefs.defaults);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loaded = await NotificationPrefs.load();
    if (mounted) setState(() => _alerts = loaded);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: const GlassBackButton(),
        title: Text(
          'Notifications',
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
              'Choose your alerts',
              style: AppTypography.inter(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select what metrics you would like to be notified about',
              style: AppTypography.inter(
                color: AppTheme.textSec,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'NOTIFICATIONS',
              style: AppTypography.inter(
                color: AppTheme.textSec,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  for (final entry in _alerts.entries) ...[
                    if (entry.key != _alerts.keys.first) const Divider(height: 1, color: AppTheme.div),
                    _AlertRow(
                      title: entry.key,
                      value: entry.value,
                      onChanged: (v) {
                        setState(() => _alerts[entry.key] = v);
                        NotificationPrefs.setEnabled(entry.key, v);
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _AlertRow({required this.title, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTypography.inter(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Transform.scale(
            scale: 0.85,
            child: Switch(value: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}
