import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _gestureControls = false;
  bool _lowBatteryPrompt = false;

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final connected = ble.isConnected;
    final deviceName = ble.deviceName.isNotEmpty ? ble.deviceName : 'No Device Paired';
    final mac = ble.deviceAddress;
    final battery = ble.battery;
    final firmware = ble.firmwareVersion['firmware'] ?? '--';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Settings',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Icon(Icons.add, color: Colors.white, size: 26),
              ],
            ),
            const SizedBox(height: 20),

            // Ring info card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          deviceName,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (mac.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(mac,
                              style: GoogleFonts.inter(
                                  color: AppTheme.textSec, fontSize: 12)),
                        ],
                        const SizedBox(height: 4),
                        Text(firmware,
                            style: GoogleFonts.inter(
                                color: AppTheme.textSec, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(
                          connected ? 'Connected' : 'Disconnected',
                          style: GoogleFonts.inter(
                              color: AppTheme.textSec, fontSize: 12),
                        ),
                        if (battery >= 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Battery $battery%',
                            style: GoogleFonts.inter(
                                color: AppTheme.textSec, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Image.asset('ring.png', width: 72, height: 72, fit: BoxFit.contain),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Unbind button
            GestureDetector(
              onTap: () {},
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    'Unbind',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 28),

            Text(
              'SETTINGS',
              style: GoogleFonts.inter(
                color: AppTheme.textSec,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),

            const SizedBox(height: 10),

            // Settings list
            Container(
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _SettingsRow.arrow(
                    icon: Icons.manage_accounts_rounded,
                    title: 'Account & System settings',
                    onTap: () => Navigator.pushNamed(context, '/account-system-settings'),
                  ),
                  _divider(),
                  _SettingsRow.toggle(
                    icon: Icons.swipe_rounded,
                    title: 'Gesture Controls',
                    subtitle: 'Enable gesture controls',
                    value: _gestureControls,
                    onChanged: (v) => setState(() => _gestureControls = v),
                  ),
                  _divider(),
                  _SettingsRow.arrow(icon: Icons.gps_fixed_rounded, title: 'Find Device'),
                  _divider(),
                  _SettingsRow.arrow(icon: Icons.notifications_outlined, title: 'Notifications'),
                  _divider(),
                  _SettingsRow.arrow(icon: Icons.auto_awesome_rounded, title: 'AI Analysis'),
                  _divider(),
                  _SettingsRow.arrow(icon: Icons.camera_alt_outlined, title: 'Take picture'),
                  _divider(),
                  _SettingsRow.arrow(icon: Icons.sports_esports_outlined, title: 'Ring Games'),
                  _divider(),
                  _SettingsRow.value(
                    icon: Icons.straighten_rounded,
                    title: 'Unit format',
                    value: 'metric system',
                  ),
                  _divider(),
                  _SettingsRow.value(
                    icon: Icons.thermostat_rounded,
                    title: 'Temperature Unit',
                    value: 'C',
                  ),
                  _divider(),
                  _SettingsRow.toggle(
                    icon: Icons.battery_alert_rounded,
                    title: 'Low battery prompt',
                    value: _lowBatteryPrompt,
                    onChanged: (v) => setState(() => _lowBatteryPrompt = v),
                  ),
                  _divider(),
                  _SettingsRow.arrow(icon: Icons.monitor_heart_outlined, title: 'Health connect'),
                  _divider(),
                  _SettingsRow.arrow(
                    icon: Icons.security_rounded,
                    title: 'Background operation protection guide',
                  ),
                  _divider(),
                  _SettingsRow.arrow(icon: Icons.system_update_outlined, title: 'Firmware upgrade'),
                  _divider(),
                  _SettingsRow.arrow(icon: Icons.help_outline_rounded, title: "FAQ's"),
                ],
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, color: AppTheme.div, indent: 0, endIndent: 0);
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final _RowType type;
  final String? value;
  final bool? toggleValue;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onTap;

  const _SettingsRow._({
    required this.icon,
    required this.title,
    required this.type,
    this.subtitle,
    this.value,
    this.toggleValue,
    this.onChanged,
    this.onTap,
  });

  factory _SettingsRow.arrow({
    required IconData icon,
    required String title,
    VoidCallback? onTap,
  }) =>
      _SettingsRow._(
        icon: icon,
        title: title,
        type: _RowType.arrow,
        onTap: onTap,
      );

  factory _SettingsRow.value({
    required IconData icon,
    required String title,
    required String value,
  }) =>
      _SettingsRow._(
        icon: icon,
        title: title,
        type: _RowType.value,
        value: value,
      );

  factory _SettingsRow.toggle({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      _SettingsRow._(
        icon: icon,
        title: title,
        type: _RowType.toggle,
        subtitle: subtitle,
        toggleValue: value,
        onChanged: onChanged,
      );

  @override
  Widget build(BuildContext context) {
    Widget trailing;
    switch (type) {
      case _RowType.arrow:
        trailing = const Icon(Icons.chevron_right_rounded, color: AppTheme.textSec, size: 20);
      case _RowType.value:
        trailing = Text(
          value ?? '',
          style: GoogleFonts.inter(color: AppTheme.textSec, fontSize: 13),
        );
      case _RowType.toggle:
        trailing = Transform.scale(
          scale: 0.85,
          child: Switch(
            value: toggleValue ?? false,
            onChanged: onChanged,
          ),
        );
    }

    return InkWell(
      onTap: type == _RowType.toggle ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
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
              child: Icon(icon, color: const Color(0xFFAAAAAA), size: 17),
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
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: GoogleFonts.inter(color: AppTheme.textSec, fontSize: 11),
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

enum _RowType { arrow, value, toggle }
