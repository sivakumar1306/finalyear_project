import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';
import '../../services/notification_prefs.dart';
import '../../models/womens_health_models.dart';
import '../../services/local_notification_service.dart';

class WomensHealthNotificationsScreen extends StatefulWidget {
  final PredictionResult? awheResult;
  const WomensHealthNotificationsScreen({super.key, this.awheResult});

  @override
  State<WomensHealthNotificationsScreen> createState() =>
      _WomensHealthNotificationsScreenState();
}

class _WomensHealthNotificationsScreenState
    extends State<WomensHealthNotificationsScreen> {
  bool _periodReminders = true;
  bool _fertileReminders = false;
  final String _schedule = '1 day before';
  final String _time = '12:00 pm';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await NotificationPrefs.load();
    setState(() {
      _periodReminders = prefs['Next Period Reminder'] ?? true;
      _fertileReminders = prefs['Fertility Window'] ?? true;
    });
  }

  TextStyle _inter(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = Colors.white,
    double? letterSpacing,
  }) => AppTypography.inter(
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
  );

  Widget _glassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppTheme.card2,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.div, width: 0.5),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildToggleRow({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: _inter(15, weight: FontWeight.w500)),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppTheme.gold,
            activeThumbColor: Colors.black,
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: _inter(15, weight: FontWeight.w500)),
            ),
            Text(value, style: _inter(14, color: AppTheme.textSec)),
            const SizedBox(width: 8),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppTheme.textSec,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: _inter(15, weight: FontWeight.w500)),
            ),
            Text(value, style: _inter(14, color: AppTheme.textSec)),
            const SizedBox(width: 8),
            const Icon(Icons.edit_outlined, color: AppTheme.textSec, size: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: const GlassBackButton(),
        title: Text(
          'Notifications',
          style: _inter(16, weight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select what notifications to recieve',
                      style: _inter(
                        24,
                        weight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Period Tracking ${_periodReminders ? 'active' : 'inactive'} · Ovulation Tracking ${_fertileReminders ? 'active' : 'inactive'}',
                      style: _inter(14, color: AppTheme.textSec),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'PERIOD',
                      style: _inter(
                        12,
                        weight: FontWeight.w600,
                        color: AppTheme.textSec,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _glassCard(
                      child: Column(
                        children: [
                          _buildToggleRow(
                            icon: Icons.notifications_none_rounded,
                            label: 'Get period reminders',
                            value: _periodReminders,
                            onChanged: (v) {
                              setState(() => _periodReminders = v);
                              NotificationPrefs.setEnabled(
                                'Next Period Reminder',
                                v,
                              );
                            },
                          ),
                          const Divider(height: 1, color: AppTheme.div),
                          _buildDropdownRow(
                            icon: Icons.schedule_rounded,
                            label: 'Schedule',
                            value: _schedule,
                            onTap: () {},
                          ),
                          const Divider(height: 1, color: AppTheme.div),
                          _buildTimeRow(
                            icon: Icons.access_time_rounded,
                            label: 'Time',
                            value: _time,
                            onTap: () {},
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'OVULATION',
                      style: _inter(
                        12,
                        weight: FontWeight.w600,
                        color: AppTheme.textSec,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _glassCard(
                      child: _buildToggleRow(
                        icon: Icons.notifications_none_rounded,
                        label: 'Get Fertile window reminders',
                        value: _fertileReminders,
                        onChanged: (v) {
                          setState(() => _fertileReminders = v);
                          NotificationPrefs.setEnabled('Fertility Window', v);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.gold,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () async {
                    await LocalNotificationService()
                        .syncWomensHealthNotifications(
                          nextPeriodDate: widget.awheResult?.finalPrediction,
                          fertileWindowStartDate:
                              widget.awheResult?.fertileWindowStart,
                          periodRemindersEnabled: _periodReminders,
                          fertileRemindersEnabled: _fertileReminders,
                          scheduleOffset: _schedule,
                          timeOfDay: _time,
                        );
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Text(
                    'Save changes',
                    style: _inter(
                      16,
                      weight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
