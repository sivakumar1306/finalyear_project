import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/alarm_mode_provider.dart';
import '../../providers/alarm_schedule_provider.dart';
import '../../services/prayer_schedule_prefs.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import 'focus_schedule_screen.dart';
import 'prayer_schedule_screen.dart';
import 'select_notifications_screen.dart';
import 'sleep_schedule_screen.dart';
import '../../widgets/app_typography.dart';

// Same "FlutterSharedPreferences" file / "flutter."-prefixed keys BleConnectionService
// already reads natively (device_address, user_logged_in) — the native 8s reconnect loop
// checks these directly to fire the daily sleep reminder without needing AlarmManager.
const _kSleepReminderEnabledKey = 'sleep_reminder_enabled';
const _kSleepReminderHourKey = 'sleep_reminder_hour';
const _kSleepReminderMinuteKey = 'sleep_reminder_minute';

class AlarmsNotificationsScreen extends StatefulWidget {
  const AlarmsNotificationsScreen({super.key});

  @override
  State<AlarmsNotificationsScreen> createState() =>
      _AlarmsNotificationsScreenState();
}

class _AlarmsNotificationsScreenState extends State<AlarmsNotificationsScreen> {
  bool _push = true;
  bool _sms = false;

  TimeOfDay? _sleepReminderTime;
  TimeOfDay _prayerEnd = PrayerSchedulePrefs.defaultEnd;

  static const _socialApps = ['Whatsapp'];

  @override
  void initState() {
    super.initState();
    _loadSleepReminder();
    _loadPrayerSchedule();
  }

  Future<void> _editFocusEndTime() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FocusScheduleScreen()),
    );
  }

  String _fmt24(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _loadPrayerSchedule() async {
    final (_, end) = await PrayerSchedulePrefs.load();
    if (!mounted) return;
    setState(() {
      _prayerEnd = end;
    });
  }

  Future<void> _editPrayerSchedule() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PrayerScheduleScreen()),
    );
    _loadPrayerSchedule();
  }

  Future<void> _loadSleepReminder() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    if (prefs.getBool(_kSleepReminderEnabledKey) ?? false) {
      setState(
        () => _sleepReminderTime = TimeOfDay(
          hour:
              int.tryParse(prefs.getString(_kSleepReminderHourKey) ?? '') ?? 22,
          minute:
              int.tryParse(prefs.getString(_kSleepReminderMinuteKey) ?? '') ??
              30,
        ),
      );
    }
  }

  Future<void> _scheduleSleepReminder() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SleepScheduleScreen()),
    );
    _loadSleepReminder();
  }

  Future<void> _setMode(AlarmModeProvider alarmMode, PhoneMode mode) async {
    await requestPhoneMode(context, alarmMode, mode);
  }

  @override
  Widget build(BuildContext context) {
    final alarmMode = context.watch<AlarmModeProvider>();
    final focusOn = alarmMode.mode == PhoneMode.focus;
    final prayerOn = alarmMode.mode == PhoneMode.prayer;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: const GlassBackButton(),
        title: Text(
          'Alarms & Notifications',
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
              'Personalize your day',
              style: AppTypography.inter(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Focus mode active · Notifications on for 2 metrics · 2 alarms',
              style: AppTypography.inter(
                color: AppTheme.textSec,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            _sectionLabel('MODES'),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Consumer<AlarmScheduleProvider>(
                    builder: (context, sched, _) => _AlarmRow(
                      showEditIcon: true,
                      onEditTap: _editFocusEndTime,
                      title: 'Focus Mode',
                      subtitle: focusOn
                          ? 'Active · ENDS ${_fmt24(sched.focusEnd)}'
                          : 'Off',
                      subtitleColor: focusOn ? AppTheme.gold : null,
                      trailing: _switch(
                        focusOn,
                        (v) => _setMode(
                          alarmMode,
                          v ? PhoneMode.focus : PhoneMode.base,
                        ),
                      ),
                    ),
                  ),
                  _divider(),
                  _AlarmRow(
                    showEditIcon: true,
                    onEditTap: _editPrayerSchedule,
                    title: 'Meditation',
                    subtitle: prayerOn
                        ? 'Active · ENDS ${_fmt24(_prayerEnd)}'
                        : 'Scheduled · ENDS ${_fmt24(_prayerEnd)}',
                    subtitleColor: prayerOn ? const Color(0xFF6BC99B) : null,
                    trailing: _switch(
                      prayerOn,
                      (v) => _setMode(
                        alarmMode,
                        v ? PhoneMode.prayer : PhoneMode.base,
                      ),
                    ),
                  ),
                  _divider(),
                  _AlarmRow(
                    title: 'Sleep',
                    subtitle: _sleepReminderTime != null
                        ? 'Reminder set · ${_sleepReminderTime!.format(context)}'
                        : 'Sleep times not set',
                    subtitleColor: _sleepReminderTime != null
                        ? AppTheme.sleepColor
                        : null,
                    onTap: _scheduleSleepReminder,
                    trailing: Text(
                      _sleepReminderTime != null ? 'Change' : 'Schedule now',
                      style: AppTypography.inter(
                        color: AppTheme.gold,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            _sectionLabel('NOTIFICATIONS'),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SelectNotificationsScreen(),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Select what notifications to recieve',
                          style: AppTypography.inter(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppTheme.textSec,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _AlarmRow(
                    title: 'Push',
                    trailing: _switch(_push, (v) => setState(() => _push = v)),
                  ),
                  _divider(),
                  _AlarmRow(
                    title: 'SMS',
                    trailing: _switch(_sms, (v) => setState(() => _sms = v)),
                  ),
                  for (final app in _socialApps) ...[
                    _divider(),
                    _AlarmRow(
                      title: app,
                      trailing: Text(
                        'set up',
                        style: AppTypography.inter(
                          color: AppTheme.textSec,
                          fontSize: 13,
                        ),
                      ),
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

  Widget _switch(bool value, ValueChanged<bool> onChanged) => Transform.scale(
    scale: 0.85,
    child: Switch(value: value, onChanged: onChanged),
  );

  Widget _sectionLabel(String text) => Text(
    text,
    style: AppTypography.inter(
      color: AppTheme.textSec,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.5,
    ),
  );

  Widget _divider() => const Divider(height: 1, color: AppTheme.div);
}

class _AlarmRow extends StatelessWidget {
  final bool showEditIcon;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final Widget trailing;
  final VoidCallback? onTap;
  final VoidCallback? onEditTap;

  const _AlarmRow({
    this.showEditIcon = false,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    required this.trailing,
    this.onTap,
    this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            if (showEditIcon) ...[
              InkWell(
                onTap: onEditTap,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppTheme.card2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.edit_outlined,
                    color: Color(0xFFAAAAAA),
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: AppTypography.inter(
                        color: subtitleColor ?? AppTheme.textSec,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }
}
