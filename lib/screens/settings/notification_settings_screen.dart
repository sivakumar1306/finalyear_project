import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/incident_service.dart';
import '../../widgets/glass_pill.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  final _ble = BleService();
  bool _loading = false;
  Map<String, dynamic> _settings = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    if (!context.read<BleProvider>().isConnected) return;
    setState(() => _loading = true);
    try {
      final json = await _ble.getNotificationSettings();
      if (!mounted) return;
      setState(() => _settings = jsonDecode(json) ?? {});
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'notification_settings_screen',
        error: e,
        stackTrace: st,
        customMessage: '_loadSettings failed',
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    try {
      await _ble.setNotificationSetting(jsonEncode(_settings));
      if (mounted) showGlassPill(context, 'Notification settings saved', type: GlassPillType.success);
    } catch (e) {
      if (mounted) showGlassPill(context, 'Error: $e', type: GlassPillType.error);
    }
  }

  Widget _switchTile(String key, String title, {String? subtitle}) {
    final val = _settings[key] as bool? ?? false;
    return SwitchListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(fontSize: 12)) : null,
      value: val,
      onChanged: (v) => setState(() => _settings[key] = v),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Settings'),
        actions: [
          TextButton(
            onPressed: connected ? _save : null,
            child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _sectionHeader('Apple Notification Center Service'),
                _switchTile('ancsEnable', 'ANCS', subtitle: 'Forward iOS notifications to ring'),
                const Divider(),
                _sectionHeader('Do Not Disturb'),
                _switchTile('dndEnable', 'Do Not Disturb'),
                ListTile(
                  title: const Text('DND Start Time'),
                  trailing: Text(_settings['dndStart'] ?? '22:00'),
                  onTap: () async {
                    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 22, minute: 0));
                    if (t != null) setState(() => _settings['dndStart'] = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
                  },
                ),
                ListTile(
                  title: const Text('DND End Time'),
                  trailing: Text(_settings['dndEnd'] ?? '07:00'),
                  onTap: () async {
                    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 7, minute: 0));
                    if (t != null) setState(() => _settings['dndEnd'] = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
                  },
                ),
                const Divider(),
                _sectionHeader('App Notifications'),
                _switchTile('callEnable', 'Incoming Call'),
                _switchTile('smsEnable', 'SMS'),
                _switchTile('wechatEnable', 'WeChat'),
                _switchTile('qqEnable', 'QQ'),
                _switchTile('facebookEnable', 'Facebook'),
                _switchTile('twitterEnable', 'Twitter / X'),
                _switchTile('whatsappEnable', 'WhatsApp'),
                _switchTile('instagramEnable', 'Instagram'),
                const Divider(),
                _sectionHeader('Music Control'),
                _switchTile('musicEnable', 'Music Control'),
                const SizedBox(height: 80),
              ],
            ),
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
      );
}
