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
/// Supports downloading firmware packages (.bin/.zip) directly from Supabase
/// Storage / Server, custom URLs, or local files, and flashing via native DFU.
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
  bool _isLoadingReleases = false;
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
    setState(() => _isLoadingReleases = true);
    try {
      final releases = await SupabaseService.getFirmwareUpdates();
      if (mounted) {
        setState(() {
          _supabaseReleases = releases;
          if (releases.isNotEmpty) {
            _selectedRelease = releases.first;
          }
          _isLoadingReleases = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingReleases = false);
    }
  }

  Future<void> _pickLocalFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['bin', 'zip'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedFilePath = result.files.single.path;
        _selectedFileName = result.files.single.name;
        _selectedRelease = null;
        _statusMessage = 'Selected local file: $_selectedFileName';
      });
    }
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
        _statusMessage = 'Downloading firmware package from Supabase...';
      });

      localFilePath = await SupabaseService.downloadFirmwareFile(
        downloadUrl,
        onProgress: (received, total) {
          if (mounted && total > 0) {
            setState(() {
              _downloadProgress = ((received / total) * 100).toInt();
              _statusMessage = 'Downloading from Supabase: $_downloadProgress%';
            });
          }
        },
      );

      if (!mounted) return;
      setState(() => _isDownloading = false);

      if (localFilePath == null) {
        setState(() => _statusMessage = 'Failed to download firmware file from Supabase.');
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Firmware download failed. Check connection or URL.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    if (localFilePath == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No firmware file selected.'),
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
    final ringName = _firstName.isNotEmpty ? "$_firstName's Ring" : 'My Ring';
    final hasUpdate = _supabaseReleases.isNotEmpty;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: const GlassBackButton(),
        title: Text(
          'Firmware upgrade',
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0x1AFFFFFF),
                  width: 0.5,
                ),
              ),
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
                  const SizedBox(height: 6),
                  Text(
                    currentFirmware,
                    style: AppTypography.inter(
                      color: AppTheme.gold,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (hasUpdate) ...[
                    const SizedBox(height: 6),
                    Text(
                      'New firmware available',
                      style: AppTypography.inter(
                        color: AppTheme.gold,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    'Do not turn off or disconnect the ring while updating firmware.',
                    style: AppTypography.inter(
                      color: AppTheme.textSec,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Available updates',
                  style: AppTypography.inter(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  onPressed: _isLoadingReleases ? null : _fetchSupabaseReleases,
                  icon: _isLoadingReleases
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.gold),
                        )
                      : const Icon(Icons.refresh_rounded, color: AppTheme.gold, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 10),

            if (_supabaseReleases.isNotEmpty) ...[
              ..._supabaseReleases.map((release) {
                final isSelected = _selectedRelease == release;
                final version = _simplifyVersion(
                  (release['version'] as String?) ?? 'V1',
                );
                final notes = release['release_notes'] as String? ??
                    'Performance and stability improvements.';

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedRelease = release;
                      _selectedFilePath = null;
                      _selectedFileName = null;
                      _statusMessage = 'Selected release: $version';
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.card2 : AppTheme.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? AppTheme.gold : const Color(0x1AFFFFFF),
                        width: isSelected ? 1.5 : 0.5,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: isSelected ? AppTheme.gold : AppTheme.textSec,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                version,
                                style: AppTypography.inter(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                notes,
                                style: AppTypography.inter(
                                  color: AppTheme.textSec,
                                  fontSize: 12,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x1AFFFFFF)),
                ),
                child: Text(
                  _isLoadingReleases
                      ? 'Checking for firmware updates...'
                      : 'No new firmware available. You can still install from a file or URL below.',
                  style: AppTypography.inter(color: AppTheme.textSec, fontSize: 13),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // ── Custom Supabase File Link Input ──────────────────────────────
            Text(
              'Or Custom Supabase Storage URL',
              style: AppTypography.inter(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _customUrlController,
              style: AppTypography.inter(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'https://xyz.supabase.co/storage/v1/object/public/...',
                hintStyle: AppTypography.inter(color: AppTheme.textSec, fontSize: 12),
                filled: true,
                fillColor: AppTheme.card,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppTheme.gold),
                ),
              ),
              onChanged: (val) {
                if (val.trim().isNotEmpty) {
                  setState(() {
                    _selectedRelease = null;
                    _selectedFilePath = null;
                    _selectedFileName = null;
                    _statusMessage = 'Using custom URL';
                  });
                }
              },
            ),

            const SizedBox(height: 24),

            // ── Manual Local File Fallback ───────────────────────────────────
            Text(
              'Local File Option',
              style: AppTypography.inter(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x1AFFFFFF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_selectedFileName != null) ...[
                    Row(
                      children: [
                        const Icon(Icons.file_present_rounded, color: AppTheme.gold, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _selectedFileName!,
                            style: AppTypography.inter(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: (_isDownloading || _isUpdating) ? null : _pickLocalFile,
                      icon: const Icon(Icons.folder_open_rounded, size: 18),
                      label: Text(
                        'Select Local .bin / .zip File',
                        style: AppTypography.inter(fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0x33FFFFFF)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ── Update Progress & Action Button ──────────────────────────────
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
              child: ElevatedButton.icon(
                onPressed: (!isConnected || _isDownloading || _isUpdating)
                    ? null
                    : () => _startUpdateProcess(),
                icon: (_isDownloading || _isUpdating)
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.system_update_rounded, size: 20),
                label: Text(
                  _isDownloading
                      ? 'Downloading...'
                      : _isUpdating
                          ? 'Updating...'
                          : hasUpdate
                              ? 'Update firmware'
                              : 'Update firmware',
                  style: AppTypography.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.gold,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: const Color(0x1AFFFFFF),
                  disabledForegroundColor: Colors.white38,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 36),
          ],
        ),
      ),
    );
  }
}


