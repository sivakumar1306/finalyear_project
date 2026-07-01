import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/alarm_mode_provider.dart';
import '../../theme/app_theme.dart';
import 'select_notifications_screen.dart';

class AlarmsNotificationsScreen extends StatefulWidget {
  const AlarmsNotificationsScreen({super.key});

  @override
  State<AlarmsNotificationsScreen> createState() => _AlarmsNotificationsScreenState();
}

class _AlarmsNotificationsScreenState extends State<AlarmsNotificationsScreen> {
  bool _push = true;
  bool _call = false;
  bool _sms = false;

  static const _socialApps = [
    'QQ', 'Wechat', 'Facebook', 'Whatsapp', 'Twitter',
    'Skype', 'Line', 'Linkedin', 'TIM', 'Instagram', 'Snapchat',
  ];

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
                      (v) => requestPhoneMode(
                          context, alarmMode, v ? PhoneMode.focus : PhoneMode.base),
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
                      (v) => requestPhoneMode(
                          context, alarmMode, v ? PhoneMode.prayer : PhoneMode.base),
                    ),
                  ),
                  _divider(),
                  _AlarmRow(
                    title: 'Sleep',
                    subtitle: 'Sleep times not set',
                    trailing: Text(
                      'Schedule now',
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

  const _AlarmRow({
    this.showEditIcon = false,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
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
    );
  }
}
