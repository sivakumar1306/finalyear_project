import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/ble_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';

/// Full-featured OTA Firmware Update Screen for the Vital Smart Ring.
/// Simplified UI as requested.
class OtaScreen extends StatefulWidget {
  const OtaScreen({super.key});

  @override
  State<OtaScreen> createState() => _OtaScreenState();
}

class _OtaScreenState extends State<OtaScreen> {
  final _ble = BleService();
  final _customUrlController = TextEditingController();

  List<Map<String, dynamic>> _supabaseReleases = [];
  Map<String, dynamic>? _selectedRelease;

  String? _selectedFilePath;
  String? _selectedFileName;
  bool _isDownloading = false;
  bool _isUpdating = false;

  int _downloadProgress = 0;
  int _flashProgress = 0;
  String _statusMessage = '';
  String _firstName = '';
  StreamSubscription? _eventSub;

  String _simplifyVersion(String raw) {
    if (raw.isEmpty || raw == '--') return 'V1';
    final cleaned = raw.replaceAll(RegExp(r'^[vV]'), '').trim();
    final parts = cleaned.split(RegExp(r'[.\-]'));
    if (parts.isEmpty) return 'V1';
    final major = int.tryParse(parts[0]) ?? 1;
    if (parts.length == 1) return 'V$major';
    final minor = int.tryParse(parts[1]) ?? 0;
    if (minor == 0) return 'V$major';
    return 'V$major.$minor';
  }

  @override
  void initState() {
    super.initState();
    _eventSub = _ble.events.listen((event) {
      if (event['type'] == 'otaProgress') {
        final data = event['data'] as Map;
        if (mounted) {
          setState(() {
            _flashProgress = (data['progress'] as num? ?? 0).toInt();
            if (_flashProgress > 0 && _flashProgress < 100) {
              _statusMessage = 'Updating firmware... $_flashProgress%';
            } else if (_flashProgress == 100) {
              _statusMessage = 'Finishing update...';
            }
          });
        }
      }
    });

    _fetchSupabaseReleases();
    _loadUserName();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BleProvider>().refreshFirmwareVersion();
    });
  }

  Future<void> _loadUserName() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return;
      final profile = await SupabaseService.getProfile(user.id);
      final fullName = profile?['full_name'] as String? ?? '';
      if (!mounted || fullName.trim().isEmpty) return;
      setState(() => _firstName = fullName.trim().split(' ').first);
    } catch (_) {}
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _customUrlController.dispose();
    super.dispose();
  }

  Future<void> _fetchSupabaseReleases() async {
    try {
      final releases = await SupabaseService.getFirmwareUpdates();
      if (mounted) {
        setState(() {
          _supabaseReleases = releases;
          if (releases.isNotEmpty) {
            _selectedRelease = releases.first;
          }
        });
      }
    } catch (_) {}
  }



  Future<void> _startUpdateProcess({String? targetUrl, String? targetVersion}) async {
    final messenger = ScaffoldMessenger.of(context);
    final ble = context.read<BleProvider>();
    if (!ble.isConnected) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Ring is not connected. Please connect before updating.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final versionTag = targetVersion ?? _selectedRelease?['version'] ?? 'Latest Firmware';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Update firmware?',
          style: AppTypography.inter(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Updating to ${_simplifyVersion(versionTag)}.\n\nDo not turn off or disconnect the ring while updating firmware.',
          style: AppTypography.inter(color: AppTheme.textSec, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: AppTypography.inter(color: AppTheme.textSec)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.gold,
              foregroundColor: Colors.black,
            ),
            child: Text('Update firmware', style: AppTypography.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    String? localFilePath = _selectedFilePath;

    // Step 1: Download from Supabase Server if URL is specified
    final downloadUrl = targetUrl ?? _selectedRelease?['file_url'] ?? _customUrlController.text.trim();
    if (localFilePath == null && downloadUrl.isNotEmpty) {
      setState(() {
        _isDownloading = true;
        _downloadProgress = 0;
        _statusMessage = 'Downloading firmware package...';
      });

      localFilePath = await SupabaseService.downloadFirmwareFile(
        downloadUrl,
        onProgress: (received, total) {
          if (mounted && total > 0) {
            setState(() {
              _downloadProgress = ((received / total) * 100).toInt();
              _statusMessage = 'Downloading: $_downloadProgress%';
            });
          }
        },
      );

      if (!mounted) return;
      setState(() => _isDownloading = false);

      if (localFilePath == null) {
        setState(() => _statusMessage = 'Failed to download firmware file.');
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Firmware download failed. Check connection.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    if (localFilePath == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No firmware file selected or found online.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // Step 2: Flash Firmware via Native DFU
    setState(() {
      _isUpdating = true;
      _flashProgress = 0;
      _statusMessage = 'Initiating Ring DFU Update...';
    });

    try {
      final success = await _ble.startOta(localFilePath);
      if (!mounted) return;
      setState(() {
        _isUpdating = false;
        if (success) {
          _flashProgress = 100;
          _statusMessage = 'Firmware update installed successfully!';
        } else {
          _statusMessage = 'OTA update failed during installation.';
        }
      });

      if (success) {
        await ble.refreshFirmwareVersion();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Firmware updated successfully! Ring is rebooting.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUpdating = false;
        _statusMessage = 'Update error: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('OTA error: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final isConnected = ble.isConnected;
    final currentFirmware = _simplifyVersion(
      ble.firmwareVersion['firmware'] ?? 'V1',
    );
    final ringName = _firstName.isNotEmpty ? "$_firstName's Ring" : 'User Name\'s Ring';
    final hasUpdate = _supabaseReleases.isNotEmpty;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: const GlassBackButton(),
        title: Text(
          'Firmware update',
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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isConnected ? 'Ring connected' : 'Ring disconnected',
              style: AppTypography.inter(
                color: isConnected ? AppTheme.success : AppTheme.danger,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              ringName,
              style: AppTypography.inter(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Firmware version : ',
                  style: AppTypography.inter(
                    color: AppTheme.gold,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  currentFirmware,
                  style: AppTypography.inter(
                    color: AppTheme.gold,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            if (hasUpdate) ...[
              const SizedBox(height: 6),
              Text(
                'New firmware available',
                style: AppTypography.inter(
                  color: AppTheme.gold,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Do not turn off or disconnect the ring while\nupdating firmware',
              style: AppTypography.inter(
                color: AppTheme.textSec,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),

            // ── Update Progress ──────────────────────────────
            if (_isDownloading || _isUpdating || _flashProgress > 0) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.gold.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _isDownloading ? 'Downloading firmware' : 'Updating firmware',
                          style: AppTypography.inter(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _isDownloading ? '$_downloadProgress%' : '$_flashProgress%',
                          style: AppTypography.inter(
                            color: AppTheme.gold,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _isDownloading
                            ? (_downloadProgress / 100).clamp(0.0, 1.0)
                            : (_flashProgress / 100).clamp(0.0, 1.0),
                        minHeight: 10,
                        backgroundColor: const Color(0x1AFFFFFF),
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.gold),
                      ),
                    ),
                    if (_statusMessage.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        _statusMessage,
                        style: AppTypography.inter(
                          color: _statusMessage.contains('failed') || _statusMessage.contains('error')
                              ? Colors.redAccent
                              : Colors.greenAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: (!isConnected || _isDownloading || _isUpdating)
                    ? null
                    : () => _startUpdateProcess(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.gold,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: const Color(0x1AFFFFFF),
                  disabledForegroundColor: Colors.white38,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                ),
                child: (_isDownloading || _isUpdating)
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : Text(
                        'Update firmware',
                        style: AppTypography.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
