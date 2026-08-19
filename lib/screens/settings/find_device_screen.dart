import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/incident_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';

/// Premium interactive screen to locate your paired Vital Smart Ring.
/// Triggers real-time ring vibration/flashing via SDK [findDevice], displays
/// live battery percentage, MAC address, and firmware details.
class FindDeviceScreen extends StatefulWidget {
  const FindDeviceScreen({super.key});

  @override
  State<FindDeviceScreen> createState() => _FindDeviceScreenState();
}

class _FindDeviceScreenState extends State<FindDeviceScreen>
    with SingleTickerProviderStateMixin {
  bool _isRinging = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  Timer? _ringTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Initial battery refresh
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BleProvider>().refreshBattery();
    });
  }

  @override
  void dispose() {
    _ringTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _toggleFindRing(bool enable) async {
    final ble = context.read<BleProvider>();
    if (!ble.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ring is not connected. Move closer and try again.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    _ringTimer?.cancel();

    if (!enable) {
      _ringTimer = null;
      _pulseController.stop();
      _pulseController.reset();
      setState(() => _isRinging = false);
      try {
        await ble.findDevice(enable: false);
      } catch (e, st) {
        IncidentService.reportUnhandled(
          source: 'find_device_screen',
          error: e,
          stackTrace: st,
          customMessage: 'findDevice disable failed',
        );
      }
      return;
    }

    setState(() => _isRinging = true);
    _pulseController.repeat(reverse: true);

    final success = await ble.findDevice(enable: true);
    if (!mounted) return;

    if (success) {
      _ringTimer?.cancel();
      _ringTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
        if (_isRinging && ble.isConnected) {
          await ble.findDevice(enable: true);
        } else {
          _ringTimer?.cancel();
        }
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Alerting ring continuously! Check for flashing LED or vibration.',
          ),
          backgroundColor: AppTheme.card2,
        ),
      );
    } else {
      _pulseController.stop();
      _pulseController.reset();
      setState(() => _isRinging = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to communicate with ring.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final hasDevice = ble.deviceName.isNotEmpty;
    final batteryPct = ble.battery >= 0 ? ble.battery : 0;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: const GlassBackButton(),
        title: Text(
          'Find My Ring',
          style: AppTypography.inter(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ble.refreshBattery();
          await ble.refreshFirmwareVersion();
        },
        color: AppTheme.gold,
        backgroundColor: AppTheme.card,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),

              // ── Interactive Ring Pulse Banner ──────────────────────────────
              Center(
                child: SizedBox(
                  width: 180,
                  height: 180,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer 2 Pulsing Rings
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          final scale = _isRinging ? _pulseAnimation.value : 1.0;
                          return Transform.scale(scale: scale, child: child);
                        },
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Outer Glow Ring
                            Container(
                              width: 170,
                              height: 170,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _isRinging
                                      ? AppTheme.gold.withValues(alpha: 0.6)
                                      : AppTheme.white15,
                                  width: _isRinging ? 2.0 : 1.0,
                                ),
                                boxShadow: _isRinging
                                    ? [
                                        BoxShadow(
                                          color: AppTheme.gold.withValues(
                                            alpha: 0.35,
                                          ),
                                          blurRadius: 40,
                                          spreadRadius: 10,
                                        ),
                                      ]
                                    : [],
                              ),
                            ),
                            // Mid Ring
                            Container(
                              width: 130,
                              height: 130,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _isRinging
                                      ? AppTheme.gold.withValues(alpha: 0.8)
                                      : const Color(0x38FFFFFF),
                                  width: 1.0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Core Ring Button / Still Bluetooth Symbol
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: _isRinging
                                ? [
                                    const Color(0xFFFFF0D0),
                                    AppTheme.gold,
                                    const Color(0xFF987A46),
                                  ]
                                : [
                                    const Color(0x33FFFFFF),
                                    AppTheme.white10,
                                  ],
                          ),
                          boxShadow: _isRinging
                              ? [
                                  BoxShadow(
                                    color: AppTheme.gold.withValues(
                                      alpha: 0.85,
                                    ),
                                    blurRadius: 28,
                                    spreadRadius: 6,
                                  ),
                                ]
                              : [],
                        ),
                        child: Icon(
                          Icons.bluetooth_searching_rounded,
                          size: 40,
                          color: _isRinging
                              ? const Color(0xFF0D0C0A)
                              : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              Text(
                _isRinging ? 'Locating your ring' : 'Locate Your Ring',
                style: AppTypography.inter(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _isRinging
                      ? 'The ring is flashing and vibrating. Follow the light or vibration to locate it.'
                      : 'Tap the button below to trigger the ring\'s LED light and vibration alert.',
                  textAlign: TextAlign.center,
                  style: AppTypography.inter(
                    color: AppTheme.textSec,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ── Main Action Button ─────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => _toggleFindRing(!_isRinging),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRinging
                        ? Colors.redAccent
                        : AppTheme.gold,
                    foregroundColor: _isRinging ? Colors.white : Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: _isRinging ? 0 : 4,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isRinging
                            ? Icons.stop_circle_rounded
                            : Icons.vibration_rounded,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isRinging ? 'Locating Your Ring' : 'Make Ring Flash',
                        style: AppTypography.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // ── Live Battery Card ──────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppTheme.white10,
                    width: 0.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              batteryPct > 20
                                  ? Icons.battery_std_rounded
                                  : Icons.battery_alert_rounded,
                              color: batteryPct > 20
                                  ? AppTheme.gold
                                  : Colors.redAccent,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Battery Level',
                              style: AppTypography.inter(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          ble.battery >= 0 ? '$batteryPct%' : 'Checking...',
                          style: AppTypography.inter(
                            color: batteryPct > 20
                                ? AppTheme.gold
                                : Colors.redAccent,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Battery Bar Indicator
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: ble.battery >= 0
                            ? (batteryPct / 100).clamp(0.0, 1.0)
                            : 0.0,
                        minHeight: 8,
                        backgroundColor: AppTheme.white10,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          batteryPct > 20 ? AppTheme.gold : Colors.redAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Device Details Card ────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppTheme.white10,
                    width: 0.5,
                  ),
                ),
                child: Column(
                  children: [
                    _DetailRow(
                      label: 'Device Name',
                      value: hasDevice ? ble.deviceName : 'Not Paired',
                      isFirst: true,
                    ),
                    _DetailRow(
                      label: 'MAC Address',
                      value: ble.deviceAddress.isNotEmpty
                          ? ble.deviceAddress
                          : '—',
                      onCopy: ble.deviceAddress.isNotEmpty
                          ? () {
                              Clipboard.setData(
                                ClipboardData(text: ble.deviceAddress),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'MAC address copied to clipboard.',
                                  ),
                                ),
                              );
                            }
                          : null,
                    ),
                    _DetailRow(
                      label: 'Connection Status',
                      value: ble.isConnected ? 'Connected' : 'Disconnected',
                      valueColor: ble.isConnected
                          ? Colors.greenAccent
                          : Colors.redAccent,
                    ),
                    _DetailRow(
                      label: 'Firmware Version',
                      value: ble.firmwareVersion['firmware'] ?? 'v1.0.0.55',
                      isLast: true,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onCopy;
  final bool isFirst;
  final bool isLast;

  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.onCopy,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : const BorderSide(color: AppTheme.glassButtonBorder, width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTypography.inter(color: AppTheme.textSec, fontSize: 13),
          ),
          Row(
            children: [
              Text(
                value,
                style: AppTypography.inter(
                  color: valueColor ?? Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (onCopy != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onCopy,
                  child: const Icon(
                    Icons.copy_rounded,
                    size: 14,
                    color: AppTheme.gold,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
