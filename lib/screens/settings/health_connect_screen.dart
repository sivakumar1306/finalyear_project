import 'dart:ui';

import 'package:flutter/material.dart';

import '../../services/health_connect_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';

/// Health Connect — connects Google Health Connect to the app.
///
/// Lets the user pick which metric groups to sync, authorize them through the
/// native Health Connect permission sheet, and previews today's aggregated
/// readings (steps, HR, HRV, SpO2, sleep, blood pressure, temperature).
class HealthConnectScreen extends StatefulWidget {
  const HealthConnectScreen({super.key});

  @override
  State<HealthConnectScreen> createState() => _HealthConnectScreenState();
}

class _HealthConnectScreenState extends State<HealthConnectScreen> {
  final HealthConnectService _service = HealthConnectService.instance;

  bool? _available;
  bool _connected = false;
  bool _busy = false;
  Set<HealthSyncType> _enabled = {};
  Set<HealthSyncType> _granted = {};
  HealthConnectToday? _today;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _enabled = await _service.loadEnabledTypes();
    _connected = await _service.loadConnected();
    final available = await _service.isAvailable();
    if (!mounted) return;
    setState(() => _available = available);
    if (available) await _refreshGrantedAndToday();
  }

  Future<void> _refreshGrantedAndToday() async {
    final granted = await _service.refreshWriteGrants(_enabled);
    if (!mounted) return;
    setState(() {
      _granted = granted;
      _connected = _connected || granted.isNotEmpty;
    });

    final enabledGranted = _enabled.intersection(granted);
    if (enabledGranted.isEmpty) return;
    final today = await _service.fetchToday(enabledGranted);
    if (!mounted) return;
    setState(() => _today = today);
  }

  Future<void> _connect() async {
    if (_enabled.isEmpty) {
      _showSnack('Select at least one data type to sync.');
      return;
    }
    setState(() => _busy = true);
    final ok = await _service.requestAuthorization(_enabled);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _showSnack('Health Connect connected.');
      await _refreshGrantedAndToday();
    } else {
      _showSnack('Authorization incomplete — some permissions were not granted.');
    }
  }

  Future<void> _install() async {
    if (!mounted) return;
    setState(() => _busy = true);
    await _service.installHealthConnect();
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _toggle(HealthSyncType type, bool value) async {
    setState(() {
      if (value) {
        _enabled = {..._enabled, type};
      } else {
        _enabled = {..._enabled}..remove(type);
      }
    });
    await _service.saveEnabledTypes(_enabled);

    if (value && !_granted.contains(type)) {
      // Invoke Google's native Health Connect permission grant screen for the
      // newly enabled type (also covers the "Connect" first-run flow).
      setState(() => _busy = true);
      final ok = await _service.requestAuthorization(_enabled);
      if (!mounted) return;
      setState(() => _busy = false);
      if (ok) {
        _showSnack('${type.label} permission granted.');
      } else {
        _showSnack('${type.label} permission not granted — nothing will sync.');
      }
      await _refreshGrantedAndToday();
    } else {
      // Turning a type off (or re-enabling an already-granted one) needs no
      // native sheet — just refresh what's synced.
      await _refreshGrantedAndToday();
    }
  }

  Future<void> _disconnect() async {
    if (!mounted) return;
    setState(() => _busy = true);
    await _service.revokeAll();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _connected = false;
      _granted = {};
      _today = null;
    });
    _showSnack('Disconnected from Health Connect.');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.card2,
        content: Text(
          message,
          style: AppTypography.inter(color: Colors.white, fontSize: 13),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: const Padding(
          padding: EdgeInsets.only(left: 16),
          child: GlassBackButton(),
        ),
        title: Text(
          'Health Connect',
          style: AppTypography.inter(
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
            if (_available != null && !_available!) ...[
              _AvailabilityBanner(
                busy: _busy,
                onInstall: _install,
              ),
              const SizedBox(height: 20),
            ],
            Text(
              'Sync health data with other apps',
              style: AppTypography.inter(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose what to sync, then allow read & write access. Sundr '
              'sends the measurements it takes and pulls in your other apps\' '
              'core health data.',
              style: AppTypography.inter(
                color: AppTheme.textSec,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            _buildDataTypesCard(),
            const SizedBox(height: 20),
            _buildConnectButton(),
            if (_connected) ...[
              const SizedBox(height: 28),
              _buildTodaySection(),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : _disconnect,
                  child: Text(
                    'Disconnect Health Connect',
                    style: AppTypography.inter(
                      color: AppTheme.danger.withValues(alpha: 0.9),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── Data types list ─────────────────────────────────────────────────────────

  Widget _buildDataTypesCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (final type in HealthSyncType.values) ...[
            if (type != HealthSyncType.values.first)
              const Divider(height: 1, color: AppTheme.div),
            _buildTypeRow(type),
          ],
        ],
      ),
    );
  }

  Widget _buildTypeRow(HealthSyncType type) {
    final enabled = _enabled.contains(type);
    final granted = _granted.contains(type);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _colorFor(type).withValues(alpha: 0.14),
            ),
            child: Icon(_iconFor(type), color: _colorFor(type), size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type.label,
                  style: AppTypography.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  granted ? 'Sending & syncing' : type.subtitle,
                  style: AppTypography.inter(
                    color: granted ? AppTheme.gold : AppTheme.textSec,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (granted)
            const Icon(
              Icons.check_circle_rounded,
              color: AppTheme.gold,
              size: 18,
            )
          else if (_available == true)
            Switch(
              value: enabled,
              onChanged: _busy ? null : (v) => _toggle(type, v),
            )
          else
            Switch(value: false, onChanged: null),
        ],
      ),
    );
  }

  // ── Connect CTA ─────────────────────────────────────────────────────────────

  Widget _buildConnectButton() {
    final connected = _connected && _granted.isNotEmpty;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _busy ? null : _connect,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.gold,
          foregroundColor: Colors.black,
          disabledBackgroundColor: AppTheme.gold.withValues(alpha: 0.5),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    connected
                        ? Icons.sync_rounded
                        : Icons.monitor_heart_rounded,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    connected ? 'Update Permissions' : 'Connect Health Connect',
                    style: AppTypography.inter(
                      color: Colors.black,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ── Today's data ────────────────────────────────────────────────────────────

  Widget _buildTodaySection() {
    final shown = _enabled.intersection(_granted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Today',
                style: AppTypography.inter(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.refresh_rounded,
                color: _busy ? AppTheme.textSec : AppTheme.gold,
                size: 20,
              ),
              onPressed:
                  _busy ? null : () => _refreshGrantedAndToday(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: AppTheme.textSec,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Enable a data type above and connect to see today\'s '
                    'readings here.',
                    style: AppTypography.inter(
                      color: AppTheme.textSec,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.35,
            children: [
              for (final type in HealthSyncType.values)
                if (shown.contains(type)) _buildTodayTile(type),
            ],
          ),
      ],
    );
  }

  Widget _buildTodayTile(HealthSyncType type) {
    final t = _today;
    final color = _colorFor(type);
    final (value, unit) = _valueFor(type, t);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.09),
          width: 0.5,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -60,
            right: -60,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(_iconFor(type), color: color, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        type.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.inter(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.inter(
                          fontSize: 30,
                          fontWeight: FontWeight.w300,
                          height: 1.1,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                      ),
                    ),
                    if (unit.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        unit,
                        style: AppTypography.inter(
                          fontSize: 12,
                          color: AppTheme.textSec,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Formatting & lookup helpers ─────────────────────────────────────────────

  (String, String) _valueFor(HealthSyncType type, HealthConnectToday? t) {
    switch (type) {
      case HealthSyncType.steps:
        return (t?.steps != null ? '${t!.steps}' : '--', '');
      case HealthSyncType.heartRate:
        return (t?.avgHeartRate != null ? '${t!.avgHeartRate!.round()}' : '--', 'bpm');
      case HealthSyncType.hrv:
        return (t?.avgHrv != null ? '${t!.avgHrv!.round()}' : '--', 'ms');
      case HealthSyncType.bloodOxygen:
        return (t?.avgSpo2 != null ? '${t!.avgSpo2!.round()}' : '--', '%');
      case HealthSyncType.sleep:
        if (t?.sleepMinutes == null || t!.sleepMinutes == 0) return ('--', 'h');
        final h = t.sleepMinutes! ~/ 60;
        final m = t.sleepMinutes! % 60;
        return (h > 0 ? '$h h $m m' : '$m m', '');
      case HealthSyncType.bloodPressure:
        return (t?.bpSystolic != null ? '${t!.bpSystolic}/${t.bpDiastolic}' : '--', 'mmHg');
      case HealthSyncType.temperature:
        return (
          t?.avgTemperatureC != null ? t!.avgTemperatureC!.toStringAsFixed(1) : '--',
          '°C',
        );
      case HealthSyncType.menstruation:
        return (
          t?.hasMenstruationData == true ? (t!.daysSinceLastPeriod != null ? '${t.daysSinceLastPeriod}' : 'Active') : '--',
          'days ago',
        );
    }
  }

  static Color _colorFor(HealthSyncType type) {
    switch (type) {
      case HealthSyncType.steps:
        return AppTheme.stepsColor;
      case HealthSyncType.heartRate:
        return AppTheme.hrColor;
      case HealthSyncType.hrv:
        return AppTheme.hrvColor;
      case HealthSyncType.bloodOxygen:
        return AppTheme.spo2Color;
      case HealthSyncType.sleep:
        return AppTheme.sleepColor;
      case HealthSyncType.bloodPressure:
        return AppTheme.bpColor;
      case HealthSyncType.temperature:
        return AppTheme.tempColor;
      case HealthSyncType.menstruation:
        return Colors.pink;
    }
  }

  static IconData _iconFor(HealthSyncType type) {
    switch (type) {
      case HealthSyncType.steps:
        return Icons.directions_walk_rounded;
      case HealthSyncType.heartRate:
        return Icons.favorite_rounded;
      case HealthSyncType.hrv:
        return Icons.show_chart_rounded;
      case HealthSyncType.bloodOxygen:
        return Icons.bloodtype_rounded;
      case HealthSyncType.sleep:
        return Icons.bedtime_rounded;
      case HealthSyncType.bloodPressure:
        return Icons.speed_rounded;
      case HealthSyncType.temperature:
        return Icons.thermostat_rounded;
      case HealthSyncType.menstruation:
        return Icons.water_drop_rounded;
    }
  }
}

/// Shown when Google Health Connect is missing on the device.
class _AvailabilityBanner extends StatelessWidget {
  final bool busy;
  final VoidCallback onInstall;

  const _AvailabilityBanner({required this.busy, required this.onInstall});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppTheme.gold,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Health Connect not found',
                  style: AppTypography.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Install it from the Play Store to sync your health data.',
                  style: AppTypography.inter(
                    color: AppTheme.textSec,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 36,
            child: ElevatedButton(
              onPressed: busy ? null : onInstall,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.gold,
                foregroundColor: Colors.black,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : Text(
                      'Install',
                      style: AppTypography.inter(
                        color: Colors.black,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
