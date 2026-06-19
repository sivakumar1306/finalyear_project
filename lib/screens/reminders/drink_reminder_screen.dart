import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';

class DrinkReminderScreen extends StatefulWidget {
  const DrinkReminderScreen({super.key});
  @override
  State<DrinkReminderScreen> createState() => _DrinkReminderScreenState();
}

class _DrinkReminderScreenState extends State<DrinkReminderScreen> {
  final _ble = BleService();
  bool _loading = false;
  bool _enabled = false;
  String _startTime = '08:00';
  String _endTime = '22:00';
  int _intervalMin = 60;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    if (!context.read<BleProvider>().isConnected) return;
    setState(() => _loading = true);
    try {
      final json = await _ble.getDrinkReminder();
      final m = jsonDecode(json) ?? {};
      setState(() {
        _enabled = m['enable'] ?? false;
        _startTime = m['startTime'] ?? '08:00';
        _endTime = m['endTime'] ?? '22:00';
        _intervalMin = m['interval'] ?? 60;
      });
    } catch (_) {} finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final data = {'enable': _enabled, 'startTime': _startTime, 'endTime': _endTime, 'interval': _intervalMin};
    try {
      await _ble.setDrinkReminder(jsonEncode(data));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Drink reminder saved')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final parts = (isStart ? _startTime : _endTime).split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
    );
    if (t != null) {
      final formatted = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      setState(() {
        if (isStart) { _startTime = formatted; } else { _endTime = formatted; }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drink Reminder'),
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
                SwitchListTile(
                  title: const Text('Drink Reminder'),
                  subtitle: const Text('Remind you to drink water regularly'),
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
                if (_enabled) ...[
                  const Divider(),
                  ListTile(
                    title: const Text('Start Time'),
                    trailing: Text(_startTime, style: const TextStyle(fontWeight: FontWeight.w600)),
                    onTap: () => _pickTime(true),
                  ),
                  ListTile(
                    title: const Text('End Time'),
                    trailing: Text(_endTime, style: const TextStyle(fontWeight: FontWeight.w600)),
                    onTap: () => _pickTime(false),
                  ),
                  ListTile(
                    title: const Text('Reminder Interval'),
                    trailing: DropdownButton<int>(
                      value: _intervalMin,
                      items: [30, 45, 60, 90, 120]
                          .map((e) => DropdownMenuItem(value: e, child: Text('$e min')))
                          .toList(),
                      onChanged: (v) => setState(() => _intervalMin = v ?? 60),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
