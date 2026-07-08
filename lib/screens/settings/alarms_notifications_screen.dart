import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/alarm_mode_provider.dart';
import '../../providers/ble_provider.dart';
import '../../theme/app_theme.dart';
import 'select_notifications_screen.dart';

// Same "FlutterSharedPreferences" file / "flutter."-prefixed keys BleConnectionService
// already reads natively (device_address, user_logged_in) — the native 8s reconnect loop
// checks these directly to fire the daily sleep reminder without needing AlarmManager.
const _kSleepReminderEnabledKey = 'sleep_reminder_enabled';
const _kSleepReminderHourKey = 'sleep_reminder_hour';
const _kSleepReminderMinuteKey = 'sleep_reminder_minute';

class AlarmsNotificationsScreen extends StatefulWidget {
  const AlarmsNotificationsScreen({super.key});

  @override
  State<AlarmsNotificationsScreen> createState() => _AlarmsNotificationsScreenState();
}

class _AlarmsNotificationsScreenState extends State<AlarmsNotificationsScreen> {
  bool _push = true;
  bool _call = false;
  bool _sms = false;

  List<Map<String, dynamic>> _modeSessions = [];
  TimeOfDay? _sleepReminderTime;

  static const _socialApps = [
    'QQ', 'Wechat', 'Facebook', 'Whatsapp', 'Twitter',
    'Skype', 'Line', 'Linkedin', 'TIM', 'Instagram', 'Snapchat',
  ];

  @override
  void initState() {
    super.initState();
    _loadUsage();
    _loadSleepReminder();
  }

  Future<void> _loadUsage() async {
    final sessions = await context.read<BleProvider>().getPhoneModeSessionsToday();
    if (!mounted) return;
    setState(() => _modeSessions = sessions);
  }

  Future<void> _loadSleepReminder() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    if (prefs.getBool(_kSleepReminderEnabledKey) ?? false) {
      setState(() => _sleepReminderTime = TimeOfDay(
            hour: int.tryParse(prefs.getString(_kSleepReminderHourKey) ?? '') ?? 22,
            minute: int.tryParse(prefs.getString(_kSleepReminderMinuteKey) ?? '') ?? 30,
          ));
    }
  }

  Future<void> _scheduleSleepReminder() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _sleepReminderTime ?? const TimeOfDay(hour: 22, minute: 30),
    );
    if (picked == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSleepReminderEnabledKey, true);
    // Stored as strings, not setInt — the Android shared_preferences backend stores Dart
    // ints as Long (to support 64-bit values), so a native getInt() read would crash with
    // a ClassCastException. Strings round-trip exactly like device_name/device_address do.
    await prefs.setString(_kSleepReminderHourKey, picked.hour.toString());
    await prefs.setString(_kSleepReminderMinuteKey, picked.minute.toString());
    if (!mounted) return;
    setState(() => _sleepReminderTime = picked);
  }

  Future<void> _setMode(AlarmModeProvider alarmMode, PhoneMode mode) async {
    await requestPhoneMode(context, alarmMode, mode);
    await _loadUsage();
  }

  Duration _totalForMode(String mode) {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    var total = Duration.zero;
    for (final s in _modeSessions) {
      if (s['mode'] != mode) continue;
      final startedAt = DateTime.fromMillisecondsSinceEpoch((s['startedAt'] as num).toInt());
      final endedAtRaw = s['endedAt'] as num?;
      final endedAt = endedAtRaw != null
          ? DateTime.fromMillisecondsSinceEpoch(endedAtRaw.toInt())
          : now;
      final clippedStart = startedAt.isBefore(dayStart) ? dayStart : startedAt;
      if (endedAt.isAfter(clippedStart)) total += endedAt.difference(clippedStart);
    }
    return total;
  }

  List<String> _rangesForMode(String mode) {
    final fmt = DateFormat('HH:mm');
    final ranges = <String>[];
    // Native returns sessions ordered startedAt DESC — reverse for chronological display.
    for (final s in _modeSessions.reversed) {
      if (s['mode'] != mode) continue;
      final startedAt = DateTime.fromMillisecondsSinceEpoch((s['startedAt'] as num).toInt());
      final endedAtRaw = s['endedAt'] as num?;
      final end = endedAtRaw != null
          ? fmt.format(DateTime.fromMillisecondsSinceEpoch(endedAtRaw.toInt()))
          : 'now';
      ranges.add('${fmt.format(startedAt)}–$end');
    }
    return ranges;
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Alarms & Notifications',
          style: GoogleFonts.inter(
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
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Focus mode active · Notifications on for 2 metrics · 2 alarms',
              style: GoogleFonts.inter(
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
                  _AlarmRow(
                    showEditIcon: true,
                    title: 'Focus Mode',
                    subtitle: focusOn ? 'Active · ENDS 13:00' : 'Off',
                    subtitleColor: focusOn ? AppTheme.gold : null,
                    trailing: _switch(
                      focusOn,
                      (v) => _setMode(alarmMode, v ? PhoneMode.focus : PhoneMode.base),
                    ),
                  ),
                  _divider(),
                  _AlarmRow(
                    showEditIcon: true,
                    title: 'Prayer Mode',
                    subtitle: prayerOn ? 'Active · Dhuhr 13:14' : 'Scheduled · 22:30-06:30',
                    subtitleColor: prayerOn ? const Color(0xFF6BC99B) : null,
                    trailing: _switch(
                      prayerOn,
                      (v) => _setMode(alarmMode, v ? PhoneMode.prayer : PhoneMode.base),
                    ),
                  ),
                  _divider(),
                  _AlarmRow(
                    title: 'Sleep',
                    subtitle: _sleepReminderTime != null
                        ? 'Reminder set · ${_sleepReminderTime!.format(context)}'
                        : 'Sleep times not set',
                    subtitleColor: _sleepReminderTime != null ? AppTheme.sleepColor : null,
                    onTap: _scheduleSleepReminder,
                    trailing: Text(
                      _sleepReminderTime != null ? 'Change' : 'Schedule now',
                      style: GoogleFonts.inter(
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
            _sectionLabel("TODAY'S USAGE"),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _UsageRow(
                    icon: Icons.adjust_rounded,
                    color: AppTheme.focus,
                    title: 'Focus',
                    duration: _totalForMode('focus'),
                    ranges: _rangesForMode('focus'),
                  ),
                  _divider(),
                  _UsageRow(
                    icon: Icons.self_improvement_rounded,
                    color: AppTheme.success,
                    title: 'Prayer',
                    duration: _totalForMode('prayer'),
                    ranges: _rangesForMode('prayer'),
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
                  MaterialPageRoute(builder: (_) => const SelectNotificationsScreen()),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Select what notifications to recieve',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: AppTheme.textSec, size: 20),
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
                    title: 'Call',
                    trailing: _switch(_call, (v) => setState(() => _call = v)),
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
                        style: GoogleFonts.inter(color: AppTheme.textSec, fontSize: 13),
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
        style: GoogleFonts.inter(
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

  const _AlarmRow({
    this.showEditIcon = false,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    required this.trailing,
    this.onTap,
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
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.card2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.edit_outlined, color: Color(0xFFAAAAAA), size: 16),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: GoogleFonts.inter(
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

class _UsageRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final Duration duration;
  final List<String> ranges;

  const _UsageRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.duration,
    required this.ranges,
  });

  String get _durationLabel {
    if (duration.inMinutes <= 0) return 'Not used today';
    final h = duration.inHours;
    final m = duration.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m today' : '${m}m today';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _durationLabel,
                  style: GoogleFonts.inter(color: color, fontSize: 11, fontWeight: FontWeight.w500),
                ),
                if (ranges.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    ranges.join('  ·  '),
                    style: GoogleFonts.inter(color: AppTheme.textSec, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
