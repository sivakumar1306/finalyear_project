import '../../providers/alarm_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/supabase_service.dart';
import '../../services/unit_prefs.dart';
import '../../theme/app_theme.dart';
import '../../widgets/footer_spacer.dart';
import '../ota/ota_screen.dart';
import 'background_protection_screen.dart';
import 'find_device_screen.dart';
import 'health_connect_screen.dart';
import 'profile_edit_screen.dart';
import 'ring_camera_screen.dart';
import '../main_shell.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _firstName = '';
  UnitSystem _unitSystem = UnitSystem.metric;
  TempUnit _tempUnit = TempUnit.celsius;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _loadUnitPrefs();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ble = context.read<BleProvider>();
      ble.loadAutoCallOnFallSetting();
      // Gesture Controls (PalmScreenReq) is read from the ring on connect (see
      // BleProvider._initThenSync), but also refresh here in case this screen
      // opens after that already ran. Low battery prompt is phone-side only
      // (SharedPreferences) and loaded once in BleProvider's constructor —
      // refreshed here too in case the value changed elsewhere.
      ble.loadGestureSetting();
      ble.loadLowBatteryPromptSetting();
    });
  }

  Future<void> _loadUnitPrefs() async {
    final system = await UnitPrefs.loadSystem();
    final temp = await UnitPrefs.loadTempUnit();
    if (!mounted) return;
    setState(() {
      _unitSystem = system;
      _tempUnit = temp;
    });
  }

  Future<void> _showUnitSystemPicker() async {
    final picked = await _showChoiceSheet<UnitSystem>(
      title: 'Unit format',
      options: const [
        (value: UnitSystem.metric, label: 'Metric', hint: 'kg, cm'),
        (value: UnitSystem.us, label: 'US', hint: 'lbs, ft/in'),
      ],
      current: _unitSystem,
    );
    if (picked == null) return;
    await UnitPrefs.saveSystem(picked);
    if (!mounted) return;
    setState(() => _unitSystem = picked);
  }

  Future<void> _showTempUnitPicker() async {
    final picked = await _showChoiceSheet<TempUnit>(
      title: 'Temperature Unit',
      options: const [
        (value: TempUnit.celsius, label: 'Celsius', hint: '°C'),
        (value: TempUnit.fahrenheit, label: 'Fahrenheit', hint: '°F'),
      ],
      current: _tempUnit,
    );
    if (picked == null) return;
    await UnitPrefs.saveTempUnit(picked);
    if (!mounted) return;
    setState(() => _tempUnit = picked);
  }

  Future<T?> _showChoiceSheet<T>({
    required String title,
    required List<({T value, String label, String hint})> options,
    required T current,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: AppTheme.card2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                title,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final o in options)
              InkWell(
                onTap: () => Navigator.pop(ctx, o.value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        o.value == current
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: o.value == current
                            ? AppTheme.gold
                            : AppTheme.textSec,
                        size: 20,
                      ),
                      const SizedBox(width: 14),
                      Text(
                        o.label,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        o.hint,
                        style: GoogleFonts.inter(
                          color: AppTheme.textSec,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
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

  Future<void> _onAutoCallToggle(
    BuildContext context,
    BleProvider ble,
    bool enabled,
  ) async {
    if (enabled) {
      final status = await Permission.phone.request();
      if (!status.isGranted) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Phone permission is required to auto-call your emergency contact',
            ),
          ),
        );
        // Still leave toggle off.
        await ble.setAutoCallOnFallEnabled(false);
        return;
      }
    }
    await ble.setAutoCallOnFallEnabled(enabled);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? 'Auto-call on fall detection enabled'
              : 'Auto-call on fall detection disabled',
        ),
      ),
    );
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
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Text(
              'Settings',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
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
                          Text(
                            ble.deviceName,
                            style: GoogleFonts.inter(
                              color: AppTheme.textSec,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        if (mac.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            mac,
                            style: GoogleFonts.inter(
                              color: AppTheme.textSec,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          firmware,
                          style: GoogleFonts.inter(
                            color: AppTheme.textSec,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          connected ? 'Connected' : 'Disconnected',
                          style: GoogleFonts.inter(
                            color: AppTheme.textSec,
                            fontSize: 12,
                          ),
                        ),
                        if (battery >= 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Battery $battery%',
                            style: GoogleFonts.inter(
                              color: AppTheme.textSec,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Image.asset(
                    'ring.png',
                    width: 72,
                    height: 72,
                    fit: BoxFit.contain,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Connect/Disconnect button
            GestureDetector(
              onTap: () => connected
                  ? _confirmUnbind(context)
                  : Navigator.pushNamed(context, '/device-bind'),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    connected ? 'Disconnect' : 'Connect',
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
                  // Profile now lives here instead of as its own bottom-nav tab —
                  // pushed with showBackButton: true so it can pop back to Settings
                  // (the old IndexedStack tab usage used showBackButton: false
                  // since there was no route to pop to there).
                  _SettingsRow.arrow(
                    icon: Icons.person_outline_rounded,
                    title: 'User Profile',
                    onTap: () =>
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const ProfileEditScreen(showBackButton: true),
                          ),
                        ).then((_) {
                          // Refresh the ring-card first name in case it was edited.
                          if (mounted) _loadUserProfile();
                        }),
                  ),
                  _divider(),
                  // Ring-side wrist-flip/palm-screen wake gesture (PalmScreenReq).
                  // See BleProvider.gestureEnabled/setGestureEnabled() and
                  // BlePlugin.kt's getGestureSetting/setGestureSetting.
                  _SettingsRow.toggle(
                    icon: Icons.pan_tool_alt_outlined,
                    title: 'Gesture Controls',
                    subtitle: 'Enable gesture controls',
                    value: ble.gestureEnabled,
                    onChanged: (v) =>
                        context.read<BleProvider>().setGestureEnabled(v),
                  ),
                  _divider(),
                  _SettingsRow.arrow(
                    icon: Icons.gps_fixed_rounded,
                    title: 'Find Device',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FindDeviceScreen(),
                      ),
                    ),
                  ),
                  _divider(),
                  _SettingsRow.arrow(
                    icon: Icons.auto_awesome_rounded,
                    title: 'AI Analysis',
                    onTap: () =>
                        Navigator.of(context).push(buildAiAssistRoute()),
                  ),
                  _divider(),
                  // Ring photo control — puts the ring into its camera UI so its
                  // physical shutter gesture can trigger the phone's camera.
                  // See ble_provider.dart's enterRingCameraMode()/cameraShutterEvents
                  // and BlePlugin.kt's takePicture()/exitCameraMode().
                  _SettingsRow.arrow(
                    icon: Icons.camera_alt_outlined,
                    title: 'Take picture',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RingCameraScreen(),
                      ),
                    ),
                  ),
                  _divider(),
                  _SettingsRow.value(
                    icon: Icons.straighten_rounded,
                    title: 'Unit format',
                    value: _unitSystem == UnitSystem.us ? 'US' : 'Metric',
                    onTap: _showUnitSystemPicker,
                  ),
                  _divider(),
                  _SettingsRow.value(
                    icon: Icons.thermostat_rounded,
                    title: 'Temperature Unit',
                    value: _tempUnit == TempUnit.fahrenheit ? 'F' : 'C',
                    onTap: _showTempUnitPicker,
                  ),
                  _divider(),
                  // Phone-side only — no ring command involved. Driven by the ring's
                  // own proactive battery push (BlePlugin.kt "batteryPush" event,
                  // native dataType 0x0c); see BleProvider._onBatteryPushEvent().
                  _SettingsRow.toggle(
                    icon: Icons.battery_alert_outlined,
                    title: 'Low battery prompt',
                    value: ble.lowBatteryPromptEnabled,
                    onChanged: (v) => context
                        .read<BleProvider>()
                        .setLowBatteryPromptEnabled(v),
                  ),
                  _divider(),
                  _SettingsRow.arrow(
                    icon: Icons.monitor_heart_outlined,
                    title: 'Health connect',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const HealthConnectScreen(),
                      ),
                    ),
                  ),
                  _divider(),
                  _SettingsRow.toggle(
                    icon: Icons.self_improvement_rounded,
                    title: 'Prayer Mode',
                    subtitle: 'Silences calls and enables Do Not Disturb',
                    value:
                        context.watch<AlarmModeProvider>().mode ==
                        PhoneMode.prayer,
                    onChanged: (v) => requestPhoneMode(
                      context,
                      context.read<AlarmModeProvider>(),
                      v ? PhoneMode.prayer : PhoneMode.base,
                    ),
                  ),
                  _divider(),
                  _SettingsRow.arrow(
                    icon: Icons.security_rounded,
                    title: 'Background operation protection guide',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BackgroundProtectionScreen(),
                      ),
                    ),
                  ),
                  _divider(),
                  // Auto-measurement cadence + per-vital ring monitoring toggles.
                  // Uses the '/health-settings' named route already registered in app.dart.
                  _SettingsRow.arrow(
                    icon: Icons.monitor_heart_rounded,
                    title: 'Measurement Intervals',
                    onTap: () =>
                        Navigator.pushNamed(context, '/health-settings'),
                  ),
                  _divider(),
                  _SettingsRow.arrow(
                    icon: Icons.alarm_rounded,
                    title: 'Alarms & Notifications',
                    onTap: () =>
                        Navigator.pushNamed(context, '/alarms-notifications'),
                  ),
                  _divider(),
                  _SettingsRow.arrow(
                    icon: Icons.health_and_safety_rounded,
                    title: 'Fall Prediction',
                    onTap: () =>
                        Navigator.pushNamed(context, '/fall-detection'),
                  ),
                  _divider(),
                  _SettingsRow.toggle(
                    icon: Icons.phone_in_talk_rounded,
                    title: 'Auto-call on fall detection',
                    subtitle:
                        'Immediately call your emergency contact when a fall is detected (not for fall prediction)',
                    value: ble.autoCallOnFallEnabled,
                    onChanged: (v) => _onAutoCallToggle(context, ble, v),
                  ),
                  _divider(),
                  _SettingsRow.arrow(
                    icon: Icons.system_update_outlined,
                    title: 'Firmware upgrade',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OtaScreen()),
                    ),
                  ),
                  _divider(),
                  _SettingsRow.arrow(
                    icon: Icons.manage_accounts_rounded,
                    title: 'Account & System settings',
                    onTap: () => Navigator.pushNamed(
                      context,
                      '/account-system-settings',
                    ),
                  ),
                  _divider(),
                  _SettingsRow.arrow(
                    icon: Icons.help_outline_rounded,
                    title: "FAQ's",
                    onTap: () => Navigator.pushNamed(context, '/faq'),
                  ),
                ],
              ),
            ),
            const FooterSpacer(),
          ],
        ),
      ),
    );
  }

  Widget _divider() =>
      const Divider(height: 1, color: AppTheme.div, indent: 0, endIndent: 0);

  Future<void> _confirmUnbind(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Disconnect ring',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'This will disconnect and remove the pairing with your ring.',
          style: GoogleFonts.inter(color: AppTheme.textSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AppTheme.textSec),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Disconnect',
              style: GoogleFonts.inter(
                color: AppTheme.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
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
  }) => _SettingsRow._(
    icon: icon,
    title: title,
    type: _RowType.arrow,
    onTap: onTap,
  );

  factory _SettingsRow.value({
    required IconData icon,
    required String title,
    required String value,
    VoidCallback? onTap,
  }) => _SettingsRow._(
    icon: icon,
    title: title,
    type: _RowType.value,
    value: value,
    onTap: onTap,
  );

  factory _SettingsRow.toggle({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => _SettingsRow._(
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
        trailing = const Icon(
          Icons.chevron_right_rounded,
          color: AppTheme.textSec,
          size: 20,
        );
      case _RowType.value:
        trailing = Text(
          value ?? '',
          style: GoogleFonts.inter(color: AppTheme.textSec, fontSize: 13),
        );
      case _RowType.toggle:
        trailing = Transform.scale(
          scale: 0.85,
          child: Switch(value: toggleValue ?? false, onChanged: onChanged),
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
                      style: GoogleFonts.inter(
                        color: AppTheme.textSec,
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

enum _RowType { arrow, value, toggle }
