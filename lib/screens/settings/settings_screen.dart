import 'package:flutter/material.dart';
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
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final user = SupabaseService.currentUser;
      if (user != null) {
        final p = await SupabaseService.getProfile(user.id);
        if (mounted) setState(() => _profile = p);
      }
    } catch (_) {}
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Log out', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to log out?',
            style: TextStyle(color: AppTheme.textSec)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSec)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log out',
                style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await SupabaseService.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            const Text(
              'Settings',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            _buildDeviceCard(ble),
            const SizedBox(height: 16),
            _buildProfileCard(),
            const SizedBox(height: 24),
            _sectionLabel('DEVICE'),
            _buildSettingsGroup([
              _SettingsItem(
                icon: Icons.health_and_safety_rounded,
                color: AppTheme.hrColor,
                title: 'Health Monitoring',
                subtitle: 'Auto tracking intervals',
                onTap: () => Navigator.pushNamed(context, '/health-settings'),
              ),
              _SettingsItem(
                icon: Icons.settings_rounded,
                color: AppTheme.bpColor,
                title: 'Device Settings',
                subtitle: 'Ring preferences',
                onTap: () => Navigator.pushNamed(context, '/device-settings'),
              ),
              _SettingsItem(
                icon: Icons.system_update_rounded,
                color: AppTheme.spo2Color,
                title: 'Firmware Update',
                subtitle: ble.firmwareVersion['firmware'] ?? 'Check for updates',
                onTap: () => Navigator.pushNamed(context, '/ota'),
              ),
            ]),
            const SizedBox(height: 16),
            _sectionLabel('PREFERENCES'),
            _buildSettingsGroup([
              _SettingsItem(
                icon: Icons.notifications_rounded,
                color: AppTheme.stepsColor,
                title: 'Notifications',
                onTap: () => Navigator.pushNamed(context, '/notification-settings'),
              ),
              _SettingsItem(
                icon: Icons.display_settings_rounded,
                color: AppTheme.sleepColor,
                title: 'Display',
                onTap: () => Navigator.pushNamed(context, '/display-settings'),
              ),
              _SettingsItem(
                icon: Icons.tune_rounded,
                color: AppTheme.hrvColor,
                title: 'Advanced Settings',
                onTap: () => Navigator.pushNamed(context, '/advanced-settings'),
              ),
              _SettingsItem(
                icon: Icons.local_drink_rounded,
                color: AppTheme.tempColor,
                title: 'Drink Reminder',
                onTap: () => Navigator.pushNamed(context, '/drink-reminder'),
              ),
            ]),
            const SizedBox(height: 24),
            _buildLogoutButton(),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            color: AppTheme.textSec,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
      );

  Widget _buildDeviceCard(BleProvider ble) {
    final connected = ble.isConnected;
    final name = ble.deviceName.isNotEmpty ? ble.deviceName : 'No Device Paired';
    final mac = ble.deviceAddress;
    final battery = ble.battery;
    final firmware = ble.firmwareVersion['firmware'] ?? '--';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: connected
              ? AppTheme.gold.withValues(alpha: 0.3)
              : AppTheme.div,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                    if (mac.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(mac,
                          style: const TextStyle(
                              color: AppTheme.textSec, fontSize: 12)),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _Chip(
                          label: connected ? 'Connected' : 'Disconnected',
                          color: connected
                              ? AppTheme.success
                              : const Color(0xFF6B7280),
                          icon: Icons.bluetooth_rounded,
                        ),
                        if (battery >= 0) ...[
                          const SizedBox(width: 8),
                          _Chip(
                            label: '$battery%',
                            color: battery > 20
                                ? AppTheme.gold
                                : AppTheme.danger,
                            icon: Icons.battery_full_rounded,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('Firmware: $firmware',
                        style: const TextStyle(
                            color: AppTheme.textSec, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: AppTheme.card2,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppTheme.gold.withValues(alpha: 0.3), width: 1.5),
                ),
                child: const Icon(Icons.watch_rounded,
                    color: AppTheme.gold, size: 36),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: AppTheme.div, height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _DeviceButton(
                  label: 'Pair Ring',
                  icon: Icons.bluetooth_searching_rounded,
                  color: AppTheme.gold,
                  onTap: () => Navigator.pushNamed(context, '/device-bind'),
                ),
              ),
              const SizedBox(width: 10),
              if (connected)
                Expanded(
                  child: _DeviceButton(
                    label: 'Disconnect',
                    icon: Icons.bluetooth_disabled_rounded,
                    color: AppTheme.danger,
                    onTap: () async {
                      await context.read<BleProvider>().disconnect();
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    final user = SupabaseService.currentUser;
    final name = (_profile?['full_name'] as String?) ?? user?.email ?? 'User';
    final email = user?.email ?? '';
    final age = _profile?['age'] as int?;
    final gender = _profile?['gender'] as String?;
    final height = _profile?['height_cm'] as int?;
    final weight = _profile?['weight_kg'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.div),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.goldBorder,
              shape: BoxShape.circle,
              border: Border.all(
                  color: AppTheme.gold.withValues(alpha: 0.4), width: 1.5),
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'U',
                style: const TextStyle(
                    color: AppTheme.gold,
                    fontSize: 22,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                if (email.isNotEmpty)
                  Text(email,
                      style: const TextStyle(
                          color: AppTheme.textSec, fontSize: 12)),
                if (age != null || gender != null || height != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (age != null) '${age}y',
                      if (gender != null) gender,
                      if (height != null) '${height}cm',
                      if (weight != null) '${weight}kg',
                    ].join('  ·  '),
                    style: const TextStyle(
                        color: AppTheme.textSec, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: AppTheme.textSec, size: 18),
            onPressed: () => Navigator.pushNamed(context, '/target-profile'),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsGroup(List<_SettingsItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.div),
      ),
      child: Column(
        children: items.asMap().entries.map((e) {
          final item = e.value;
          final isLast = e.key == items.length - 1;
          return Column(
            children: [
              _SettingsTile(item: item),
              if (!isLast)
                const Divider(height: 1, indent: 56, color: AppTheme.div),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return GestureDetector(
      onTap: _confirmLogout,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: AppTheme.danger.withValues(alpha: 0.3), width: 1),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, color: AppTheme.danger, size: 20),
            SizedBox(width: 8),
            Text(
              'Log Out',
              style: TextStyle(
                color: AppTheme.danger,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _Chip({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _DeviceButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _DeviceButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _SettingsItem {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const _SettingsItem({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.onTap,
  });
}

class _SettingsTile extends StatelessWidget {
  final _SettingsItem item;

  const _SettingsTile({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(item.icon, color: item.color, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500)),
                  if (item.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(item.subtitle!,
                        style: const TextStyle(
                            color: AppTheme.textSec, fontSize: 12)),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppTheme.textSec, size: 20),
          ],
        ),
      ),
    );
  }
}
