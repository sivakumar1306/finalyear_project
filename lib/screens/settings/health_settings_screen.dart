import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_typography.dart';

class HealthSettingsScreen extends StatefulWidget {
  const HealthSettingsScreen({super.key});
  @override
  State<HealthSettingsScreen> createState() => _HealthSettingsScreenState();
}

class _HealthSettingsScreenState extends State<HealthSettingsScreen> {
  final _ble = BleService();
  bool _loading = false;
  bool _saving = false;

  // Ring-side monitoring settings. Loaded from / written to the ring via the per-vital
  // SDK setting commands (getHeartRateSetting, setBloodOxygenSetting, ...). These used to
  // go through getHealthSettings/setHealthSettings, which were stubs natively — every load
  // silently failed and every save threw, so nothing on this screen reached the ring.
  // The per-vital commands below are wired to real SDK req/rsp pairs; getHealthSettings
  // is now also implemented natively and powers the Sugar & Lipids screen.
  Map<String, dynamic> _settings = {};

  // Phone-side auto-measurement cadence (SharedPreferences via MeasurementConfig), kept
  // separate from _settings because it is not part of the ring's settings and applies
  // whether or not the ring is currently connected.
  int _cycleCooldownMs = 180000;

  // Per-command timeouts. Some ring setting commands are dispatched by the SDK as NO_ACK
  // (no response parser registered, e.g. TemperatureSettingReq / notifyKey=116), so their
  // callback never fires and the corresponding Dart Future would otherwise never complete.
  // Bounding each call keeps one dead command from freezing the whole screen.
  static const _readTimeout = Duration(seconds: 5);
  static const _writeTimeout = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadCycleCooldown();
  }

  // ── Phone-side auto-measurement interval ────────────────────────────────

  Future<void> _loadCycleCooldown() async {
    try {
      final ms = await _ble.getCycleCooldownMs();
      if (mounted) setState(() => _cycleCooldownMs = ms);
    } catch (_) {}
  }

  Future<void> _setCycleCooldown(int ms) async {
    setState(() => _cycleCooldownMs = ms);
    try {
      await _ble.setCycleCooldownMs(ms);
      if (mounted) _snack('Measurement interval set to ${ms ~/ 60000} min');
    } catch (e) {
      if (mounted) _snack('Error: $e');
    }
  }

  // ── Ring-side per-vital settings ────────────────────────────────────────

  // Each get*Setting returns the SDK response serialised to JSON; the enable/interval
  // fields follow the same convention the individual vital screens already rely on.
  // Every read is independently timed out and independently caught — see _readTimeout.
  Future<void> _loadSettings() async {
    if (!context.read<BleProvider>().isConnected) return;
    setState(() => _loading = true);

    final loaded = <String, dynamic>{};

    Future<void> read(
      String enableKey,
      Future<String> Function() getter, {
      String? intervalKey,
      int defaultInterval = 5,
    }) async {
      try {
        final m = jsonDecode(await getter().timeout(_readTimeout));
        if (m is Map) {
          loaded[enableKey] = (m['enable'] as bool?) ?? false;
          if (intervalKey != null) {
            loaded[intervalKey] =
                (m['interval'] as num?)?.toInt() ?? defaultInterval;
          }
        }
      } catch (_) {
        // Timed out, unsupported, or malformed — leave unset and fall back to defaults.
      }
    }

    try {
      await read(
        'hrEnable',
        _ble.getHeartRateSetting,
        intervalKey: 'hrInterval',
        defaultInterval: 5,
      );
      await read(
        'bpEnable',
        _ble.getBloodPressureSetting,
        intervalKey: 'bpInterval',
        defaultInterval: 30,
      );
      await read(
        'spo2Enable',
        _ble.getBloodOxygenSetting,
        intervalKey: 'spo2Interval',
        defaultInterval: 5,
      );
      await read('hrvEnable', _ble.getHrvSetting);
      await read('pressureEnable', _ble.getPressureSetting);
      await read(
        'tempEnable',
        _ble.getTemperatureSetting,
        intervalKey: 'tempInterval',
        defaultInterval: 5,
      );
    } finally {
      // Always clear the spinner, even if something above threw unexpectedly.
      if (mounted) {
        setState(() {
          _settings = loaded;
          _loading = false;
        });
      }
    }
  }

  int _interval(String key, int fallback) =>
      (_settings[key] as int?) ?? fallback;
  bool _enabled(String key) => (_settings[key] as bool?) ?? false;

  // Writes every vital's setting. Failures are collected rather than aborting on the first
  // one, so an unsupported vital doesn't silently prevent the others from being applied.
  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final failed = <String>[];

    // Same NO_ACK caveat as _loadSettings: setTemperatureSetting in particular is
    // dispatched NO_ACK by the SDK, so without a timeout Save would sit on "Saving…"
    // forever. A timeout here means the command was still sent to the ring — we just
    // stop waiting for an acknowledgement that will never arrive, and report it.
    Future<void> write(String label, Future<void> Function() setter) async {
      try {
        await setter().timeout(_writeTimeout);
      } catch (_) {
        failed.add(label);
      }
    }

    await write('Heart Rate', () async {
      await _ble.setHeartRateSetting(
        enable: _enabled('hrEnable'),
        interval: _interval('hrInterval', 5),
      );
    });
    await write('Blood Pressure', () async {
      await _ble.setBloodPressureSetting(
        enable: _enabled('bpEnable'),
        interval: _interval('bpInterval', 30),
      );
    });
    await write('SpO2', () async {
      await _ble.setBloodOxygenSetting(
        enable: _enabled('spo2Enable'),
        interval: _interval('spo2Interval', 5),
      );
    });
    await write('HRV', () async {
      await _ble.setHrvSetting(enable: _enabled('hrvEnable'));
    });
    await write('Stress', () async {
      await _ble.setPressureSetting(enable: _enabled('pressureEnable'));
    });
    await write('Temperature', () async {
      await _ble.setTemperatureSetting(
        enable: _enabled('tempEnable'),
        interval: _interval('tempInterval', 5),
      );
    });

    if (!mounted) return;
    setState(() => _saving = false);
    _snack(
      failed.isEmpty
          ? 'Health settings saved'
          : 'Saved — no confirmation from: ${failed.join(", ")}',
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.card2,
        content: Text(
          message,
          style: AppTypography.inter(color: Colors.white, fontSize: 13),
        ),
      ),
    );
  }

  // ── Styled building blocks (mirrors settings_screen.dart's visual language) ──

  Widget _sectionHeader(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
    child: Text(
      text.toUpperCase(),
      style: AppTypography.inter(
        color: AppTheme.textSec,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
      ),
    ),
  );

  Widget _card(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(children: children),
  );

  Widget _divider() =>
      const Divider(height: 1, color: AppTheme.div, indent: 0, endIndent: 0);

  Widget _rowShell({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget trailing,
  }) {
    return Padding(
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
            child: Icon(icon, color: AppTheme.iconFaint, size: 17),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: AppTypography.inter(
                      color: AppTheme.textSec,
                      fontSize: 11,
                      height: 1.4,
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

  Widget _toggleRow(
    String key,
    IconData icon,
    String title, {
    String? subtitle,
  }) {
    return _rowShell(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Transform.scale(
        scale: 0.85,
        child: Switch(
          value: _enabled(key),
          onChanged: (v) => setState(() => _settings[key] = v),
        ),
      ),
    );
  }

  Widget _intervalRow(
    String key,
    IconData icon,
    String title,
    List<int> options, {
    String unit = 'min',
    String? subtitle,
  }) {
    final val = _interval(key, options.first);
    return _rowShell(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: _dropdown<int>(
        value: options.contains(val) ? val : options.first,
        items: options
            .map((e) => DropdownMenuItem(value: e, child: Text('$e $unit')))
            .toList(),
        onChanged: (v) {
          if (v != null) setState(() => _settings[key] = v);
        },
      ),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButton<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      dropdownColor: AppTheme.card2,
      borderRadius: BorderRadius.circular(12),
      underline: const SizedBox(),
      isDense: true,
      icon: const Icon(
        Icons.keyboard_arrow_down_rounded,
        color: AppTheme.textSec,
        size: 18,
      ),
      style: AppTypography.inter(
        color: AppTheme.gold,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<BleProvider>().isConnected;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text(
          'Measurement Intervals',
          style: AppTypography.inter(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: (connected && !_saving) ? _save : null,
            child: Text(
              _saving ? 'Saving…' : 'Save',
              style: AppTypography.inter(
                color: (connected && !_saving)
                    ? AppTheme.gold
                    : AppTheme.textSec,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppTheme.gold,
                strokeWidth: 2,
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
              children: [
                _sectionHeader('Automatic Measurement'),
                _card([
                  _rowShell(
                    icon: Icons.timelapse_rounded,
                    title: 'Measurement Interval',
                    subtitle:
                        'How long the app waits after finishing one full measurement '
                        'cycle before starting the next. Longer intervals use less battery.',
                    trailing: _dropdown<int>(
                      value:
                          const [
                            60000,
                            180000,
                            300000,
                            600000,
                            900000,
                          ].contains(_cycleCooldownMs)
                          ? _cycleCooldownMs
                          : 180000,
                      items: const [
                        DropdownMenuItem(value: 60000, child: Text('1 min')),
                        DropdownMenuItem(value: 180000, child: Text('3 min')),
                        DropdownMenuItem(value: 300000, child: Text('5 min')),
                        DropdownMenuItem(value: 600000, child: Text('10 min')),
                        DropdownMenuItem(value: 900000, child: Text('15 min')),
                      ],
                      onChanged: (v) {
                        if (v != null) _setCycleCooldown(v);
                      },
                    ),
                  ),
                ]),

                if (!connected)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 18, 4, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: AppTheme.textSec,
                          size: 15,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Connect your ring to view and change the monitoring '
                            'settings below.',
                            style: AppTypography.inter(
                              color: AppTheme.textSec,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                _sectionHeader('Heart Rate'),
                _card([
                  _toggleRow(
                    'hrEnable',
                    Icons.favorite_rounded,
                    'Heart Rate Monitoring',
                  ),
                  _divider(),
                  _intervalRow(
                    'hrInterval',
                    Icons.timer_outlined,
                    'Measurement Interval',
                    [1, 5, 10, 15, 30],
                  ),
                ]),

                _sectionHeader('Blood Pressure'),
                _card([
                  _toggleRow(
                    'bpEnable',
                    Icons.monitor_heart_rounded,
                    'Blood Pressure Monitoring',
                  ),
                  _divider(),
                  _intervalRow(
                    'bpInterval',
                    Icons.timer_outlined,
                    'Measurement Interval',
                    [5, 10, 15, 30, 60],
                  ),
                ]),

                _sectionHeader('Blood Oxygen'),
                _card([
                  _toggleRow(
                    'spo2Enable',
                    Icons.bloodtype_rounded,
                    'SpO2 Monitoring',
                  ),
                  _divider(),
                  _intervalRow(
                    'spo2Interval',
                    Icons.timer_outlined,
                    'Measurement Interval',
                    [1, 5, 10, 15, 30],
                  ),
                ]),

                _sectionHeader('HRV'),
                _card([
                  _toggleRow(
                    'hrvEnable',
                    Icons.ssid_chart_rounded,
                    'HRV Monitoring',
                  ),
                ]),

                _sectionHeader('Stress'),
                _card([
                  _toggleRow(
                    'pressureEnable',
                    Icons.psychology_rounded,
                    'Stress Monitoring',
                  ),
                ]),

                _sectionHeader('Temperature'),
                _card([
                  _toggleRow(
                    'tempEnable',
                    Icons.thermostat_rounded,
                    'Temperature Monitoring',
                  ),
                  _divider(),
                  _intervalRow(
                    'tempInterval',
                    Icons.timer_outlined,
                    'Measurement Interval',
                    [2, 5, 10, 30, 60, 120],
                    unit: 's',
                  ),
                ]),
              ],
            ),
    );
  }
}
