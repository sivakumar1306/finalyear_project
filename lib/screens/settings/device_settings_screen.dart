import 'package:flutter/material.dart';
import '../../widgets/section_tile.dart';
import '../../theme/app_theme.dart';

class DeviceSettingsScreen extends StatelessWidget {
  const DeviceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Device Settings')),
      body: ListView(
        children: [
          _header('Health Monitoring'),
          SectionTile(
            title: 'Health Settings',
            subtitle: 'Heart rate, BP, SpO2, HRV, pressure, temperature',
            icon: Icons.health_and_safety,
            iconColor: Colors.green,
            onTap: () => Navigator.pushNamed(context, '/health-settings'),
          ),
          SectionTile(
            title: 'Sugar & Lipids',
            subtitle: 'Blood sugar and lipid settings',
            icon: Icons.science,
            iconColor: Colors.teal,
            onTap: () => Navigator.pushNamed(context, '/sugar-lipids'),
          ),
          const Divider(),
          _header('Reminders'),
          SectionTile(
            title: 'Drink Reminder',
            subtitle: 'Hydration reminder settings',
            icon: Icons.water_drop,
            iconColor: Colors.blue,
            onTap: () => Navigator.pushNamed(context, '/drink-reminder'),
          ),
          SectionTile(
            title: 'Sedentary Reminder',
            subtitle: 'Movement reminder settings',
            icon: Icons.directions_walk,
            iconColor: Colors.orange,
            onTap: () => Navigator.pushNamed(context, '/sedentary-reminder'),
          ),
          const Divider(),
          _header('Device & Display'),
          SectionTile(
            title: 'Target & Profile',
            subtitle: 'Steps, calories, sleep goals & user info',
            icon: Icons.person,
            iconColor: Colors.purple,
            onTap: () => Navigator.pushNamed(context, '/target-profile'),
          ),
          SectionTile(
            title: 'Notification Settings',
            subtitle: 'ANCS, DND, music, app notifications',
            icon: Icons.notifications,
            iconColor: Colors.red,
            onTap: () => Navigator.pushNamed(context, '/notification-settings'),
          ),
          SectionTile(
            title: 'Display & Device',
            subtitle: 'Brightness, clock style, orientation',
            icon: Icons.display_settings,
            iconColor: Colors.indigo,
            onTap: () => Navigator.pushNamed(context, '/display-settings'),
          ),
          SectionTile(
            title: 'Gesture & Touch Controls',
            subtitle: 'Wrist-flip wake, answer calls, camera shutter, tap mapping',
            icon: Icons.touch_app_rounded,
            iconColor: AppTheme.gold,
            onTap: () => Navigator.pushNamed(context, '/gesture-settings'),
          ),
          SectionTile(
            title: 'Advanced Settings',
            subtitle: 'AGPS, battery saving, touch control',
            icon: Icons.tune,
            iconColor: Colors.grey.shade700,
            onTap: () => Navigator.pushNamed(context, '/advanced-settings'),
          ),
          const Divider(),
          _header('Firmware'),
          SectionTile(
            title: 'OTA Firmware Update',
            icon: Icons.system_update,
            iconColor: Colors.blue.shade700,
            onTap: () => Navigator.pushNamed(context, '/ota'),
          ),
        ],
      ),
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
      );
}
