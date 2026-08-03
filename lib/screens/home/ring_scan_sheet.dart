import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';

// ── Alphahuman ring detection ─────────────────────────────────────────────────
// Widened from a narrow allowlist of just 'R08_'/'R02_' (which only matched the
// two specific ring models this app had been tested with) to the full set of
// device name prefixes actually used across this manufacturer's ring/band
// lineup (confirmed against the QRing SDK's own BleScannerHelper prefix list),
// so any genuine ring shows up here — not just the ones we happened to test
// with — while still filtering out unrelated nearby Bluetooth devices
// (headphones, phones, etc.) that a fully unfiltered scan would otherwise show.
const _kAlphahumanPrefixes = [
  'R',
  'Q_',
  'q_',
  'O_',
  'o_',
  'QC',
  'qc',
  'R3L',
  'Wa',
  'T80',
  'T90',
  'T91',
  'T93',
  'T95',
  'TW68',
  'S9',
  'C60',
  'C66',
  'C67',
  'C68',
  'C80',
  'C86',
  'C88',
  'C96',
  'wxb_w4',
];

bool _isAlphahumanRing(String name) => _kAlphahumanPrefixes.any(
  (p) => name.toUpperCase().startsWith(p.toUpperCase()),
);

// ── Public entry point ────────────────────────────────────────────────────────

void showRingScanSheet(BuildContext context) {
  final ble = Provider.of<BleProvider>(context, listen: false);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.85),
    builder: (_) =>
        ChangeNotifierProvider.value(value: ble, child: const _RingScanSheet()),
  );
}

// ── Sheet ─────────────────────────────────────────────────────────────────────

class _RingScanSheet extends StatefulWidget {
  const _RingScanSheet();
  @override
  State<_RingScanSheet> createState() => _RingScanSheetState();
}

class _RingScanSheetState extends State<_RingScanSheet>
    with SingleTickerProviderStateMixin {
  late BleProvider _ble;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  Timer? _scanTimer;
  String? _connectingAddress;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 0.90,
      end: 1.10,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ble = context.read<BleProvider>();
      _startScan();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ble = context.read<BleProvider>();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _scanTimer?.cancel();
    _ble.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final denied = statuses.values.any(
      (s) => s.isDenied || s.isPermanentlyDenied,
    );

    if (denied) {
      if (mounted) setState(() => _permissionDenied = true);
      return;
    }
    if (!mounted) return;

    await _ble
        .startScan(); // scan all; Alphahuman filter applied at display level
    _scanTimer?.cancel();
    _scanTimer = Timer(const Duration(seconds: 20), () {
      if (mounted) _ble.stopScan();
    });
  }

  Future<void> _connect(ScannedDevice device) async {
    setState(() => _connectingAddress = device.address);
    final ok = await _ble.connect(device);
    if (!mounted) return;
    setState(() => _connectingAddress = null);
    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to ${device.name}'),
          backgroundColor: AppTheme.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connection failed — make sure the ring is nearby.'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  bool _connectingLast = false;

  Future<void> _connectLast() async {
    setState(() => _connectingLast = true);
    final ok = await _ble.connectLastDevice();
    if (!mounted) return;
    setState(() => _connectingLast = false);
    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to ${_ble.deviceName}'),
          backgroundColor: AppTheme.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not reach ring — try placing it on the charger to wake it.',
          ),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final rings = ble.scannedDevices
        .where((d) => _isAlphahumanRing(d.name))
        .toList();
    final screenH = MediaQuery.of(context).size.height;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          height: screenH * 0.70,
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0A).withValues(alpha: 0.90),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: AppTheme.gold.withValues(alpha: 0.22),
                width: 0.6,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 10),
                // Drag handle
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 18),
                // Title row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: const GlassBackButton(),
                      ),
                      Text(
                        'Pair Ring',
                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                // Body
                Expanded(
                  child: _permissionDenied
                      ? const _PermissionDeniedBody()
                      : rings.isNotEmpty
                      ? _RingsFoundBody(
                          rings: rings,
                          connectingAddress: _connectingAddress,
                          // So the already-connected ring shows a "Connected" state
                          // in this list instead of an active "Connect" button — the
                          // scan list was previously blind to current connection
                          // state entirely.
                          connectedAddress: ble.isConnected
                              ? ble.deviceAddress
                              : null,
                          isScanning: ble.isScanning,
                          onConnect: _connect,
                          onRescan: _startScan,
                        )
                      : _SearchingBody(
                          pulseAnim: _pulseAnim,
                          isScanning: ble.isScanning,
                          onRetry: _startScan,
                          lastDeviceName: ble.deviceName,
                          connectingLast: _connectingLast,
                          onConnectLast: _connectLast,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Searching state ───────────────────────────────────────────────────────────

class _SearchingBody extends StatelessWidget {
  final Animation<double> pulseAnim;
  final bool isScanning;
  final VoidCallback onRetry;
  final String lastDeviceName;
  final bool connectingLast;
  final VoidCallback onConnectLast;

  const _SearchingBody({
    required this.pulseAnim,
    required this.isScanning,
    required this.onRetry,
    required this.lastDeviceName,
    required this.connectingLast,
    required this.onConnectLast,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 44),
          child: Text(
            'Place your ring on the charger and check if your phone has Bluetooth on',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.white60,
              height: 1.6,
            ),
          ),
        ),
        const SizedBox(height: 36),
        // Pulsing ring with glow
        ScaleTransition(
          scale: pulseAnim,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.gold.withValues(alpha: 0.18),
                  blurRadius: 50,
                  spreadRadius: 12,
                ),
              ],
            ),
            child: Image.asset('ring.png', fit: BoxFit.contain),
          ),
        ),
        const SizedBox(height: 40),
        if (isScanning)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppTheme.gold.withValues(alpha: 0.70),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'SEARCHING FOR RING',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white30,
                  letterSpacing: 2.2,
                ),
              ),
            ],
          )
        else ...[
          Text(
            'No SUNDR rings found nearby',
            style: GoogleFonts.inter(fontSize: 13, color: Colors.white38),
          ),
          const SizedBox(height: 20),
          _GoldButton(label: 'Search Again', onTap: onRetry),
          // If a ring was previously paired, offer a direct-connect fallback.
          // This bypasses BLE advertising — useful when another app left a GATT
          // connection open or the ring stopped advertising.
          if (lastDeviceName.isNotEmpty) ...[
            const SizedBox(height: 14),
            connectingLast
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.gold,
                    ),
                  )
                : GestureDetector(
                    onTap: onConnectLast,
                    child: Text(
                      'Connect to "$lastDeviceName" directly',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppTheme.gold,
                        decoration: TextDecoration.underline,
                        decorationColor: AppTheme.gold,
                      ),
                    ),
                  ),
          ],
        ],
      ],
    );
  }
}

// ── Rings found state ─────────────────────────────────────────────────────────

class _RingsFoundBody extends StatelessWidget {
  final List<ScannedDevice> rings;
  final String? connectingAddress;
  final String? connectedAddress;
  final bool isScanning;
  final void Function(ScannedDevice) onConnect;
  final VoidCallback onRescan;

  const _RingsFoundBody({
    required this.rings,
    required this.connectingAddress,
    required this.connectedAddress,
    required this.isScanning,
    required this.onConnect,
    required this.onRescan,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'RINGS NEARBY',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.gold.withValues(alpha: 0.85),
                  letterSpacing: 1.8,
                ),
              ),
              const Spacer(),
              if (isScanning)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppTheme.gold.withValues(alpha: 0.55),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView.separated(
              itemCount: rings.length,
              separatorBuilder: (_, idx) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final dev = rings[i];
                return _RingTile(
                  device: dev,
                  isConnecting: connectingAddress == dev.address,
                  isAlreadyConnected:
                      connectedAddress != null &&
                      connectedAddress == dev.address,
                  onConnect: () => onConnect(dev),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: GestureDetector(
              onTap: onRescan,
              child: Text(
                'Search Again',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.white30,
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white30,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Ring tile ─────────────────────────────────────────────────────────────────

class _RingTile extends StatelessWidget {
  final ScannedDevice device;
  final bool isConnecting;
  final bool isAlreadyConnected;
  final VoidCallback onConnect;

  const _RingTile({
    required this.device,
    required this.isConnecting,
    required this.isAlreadyConnected,
    required this.onConnect,
  });

  Color _rssiColor(int rssi) {
    if (rssi >= -60) return AppTheme.success;
    if (rssi >= -80) return AppTheme.gold;
    return AppTheme.danger;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Image.asset('ring.png', fit: BoxFit.contain),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      Icons.signal_cellular_alt,
                      size: 11,
                      color: _rssiColor(device.rssi),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${device.rssi} dBm',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: _rssiColor(device.rssi),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isConnecting)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.gold,
              ),
            )
          else if (isAlreadyConnected)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: AppTheme.success,
                ),
                const SizedBox(width: 5),
                Text(
                  'Connected',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.success,
                  ),
                ),
              ],
            )
          else
            _GoldButton(label: 'Connect', onTap: onConnect),
        ],
      ),
    );
  }
}

// ── Permission denied state ───────────────────────────────────────────────────

class _PermissionDeniedBody extends StatelessWidget {
  const _PermissionDeniedBody();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.bluetooth_disabled, color: Colors.white30, size: 56),
          const SizedBox(height: 18),
          Text(
            'Bluetooth permission is required to scan for rings.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.white54,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          _GoldButton(label: 'Open Settings', onTap: openAppSettings),
        ],
      ),
    );
  }
}

// ── Shared gold button ────────────────────────────────────────────────────────

class _GoldButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _GoldButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.gold.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.gold.withValues(alpha: 0.45)),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.gold,
          ),
        ),
      ),
    );
  }
}
