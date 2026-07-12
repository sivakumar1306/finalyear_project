import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _gestureControls = false;
  bool _lowBatteryPrompt = false;
  String _firstName = '';

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return;
      final profile = await SupabaseService.getProfile(user.id);
      if (!mounted || profile == null) return;
      final fullName = profile['full_name'] as String? ?? '';
      if (fullName.trim().isNotEmpty) {
        setState(() => _firstName = fullName.trim().split(' ').first);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final connected = ble.isConnected;
    final hasDevice = ble.deviceName.isNotEmpty;
    // "Andrea's Ring" instead of the raw device name up top — the raw name (e.g.
    // R02_B406) still shows underneath, just demoted to secondary/muted text.
    final ringTitle = !hasDevice
        ? 'No Device Paired'
        : (_firstName.isNotEmpty ? "$_firstName's Ring" : 'My Ring');
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
                          ringTitle,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (hasDevice) ...[
                          const SizedBox(height: 4),
                          Text(ble.deviceName,
                              style: GoogleFonts.inter(
                                  color: AppTheme.textSec, fontSize: 12)),
                        ],
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
              onTap: () => _confirmUnbind(context),
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
                  _SettingsRow.arrow(
                    icon: Icons.touch_app_rounded,
                    title: 'Touch Control',
                    onTap: () => Navigator.pushNamed(context, '/touch-control'),
                  ),
                  _divider(),
                  _SettingsRow.arrow(
                    icon: Icons.alarm_rounded,
                    title: 'Alarms & Notifications',
                    onTap: () => Navigator.pushNamed(context, '/alarms-notifications'),
                  ),
                  _divider(),
                  _SettingsRow.arrow(
                    icon: Icons.health_and_safety_rounded,
                    title: 'Fall Detection',
                    onTap: () => Navigator.pushNamed(context, '/fall-detection'),
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

  Future<void> _confirmUnbind(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Unbind ring',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
        content: Text('This will disconnect and remove the pairing with your ring.',
            style: GoogleFonts.inter(color: AppTheme.textSec)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textSec)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Unbind',
                style: GoogleFonts.inter(
                    color: AppTheme.danger, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<BleProvider>().disconnect();
    }
  }
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
