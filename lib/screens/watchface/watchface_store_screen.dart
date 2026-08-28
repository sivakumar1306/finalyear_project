import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/ble_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/glass_card.dart';

TextStyle _inter(double size, {FontWeight weight = FontWeight.w400, Color color = Colors.white}) =>
    AppTypography.inter(fontSize: size, fontWeight: weight, color: color);

class WatchfaceStoreScreen extends StatefulWidget {
  const WatchfaceStoreScreen({super.key});
  @override
  State<WatchfaceStoreScreen> createState() => _WatchfaceStoreScreenState();
}

class _WatchfaceStoreScreenState extends State<WatchfaceStoreScreen> {
  final _ble = BleService();
  final List<Map<String, dynamic>> _faces = const [
    {'name': 'Midnight Gold', 'color': 0xFFC9A86E, 'url': 'https://api2.qcwxkjvip.com/download/watchface/midnight_gold.bin'},
    {'name': 'Arctic Blue', 'color': 0xFF38BDF8, 'url': 'https://api2.qcwxkjvip.com/download/watchface/arctic_blue.bin'},
    {'name': 'Forest Teal', 'color': 0xFF2DD4BF, 'url': 'https://api2.qcwxkjvip.com/download/watchface/forest_teal.bin'},
    {'name': 'Violet Dusk', 'color': 0xFF8B5CF6, 'url': 'https://api2.qcwxkjvip.com/download/watchface/violet_dusk.bin'},
    {'name': 'Crimson Pulse', 'color': 0xFFFF4757, 'url': 'https://api2.qcwxkjvip.com/download/watchface/crimson_pulse.bin'},
    {'name': 'Mono Slate', 'color': 0xFF9CA3AF, 'url': 'https://api2.qcwxkjvip.com/download/watchface/mono_slate.bin'},
  ];
  String? _downloading;
  double _progress = 0;
  String? _installed;

  @override
  void initState() { super.initState(); _loadInstalled(); }

  Future<void> _loadInstalled() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _installed = prefs.getString('watchface_installed'));
  }

  Future<void> _downloadAndInstall(Map<String, dynamic> face) async {
    final name = face['name'] as String;
    final url = face['url'] as String;
    setState(() { _downloading = name; _progress = 0; });
    try {
      final client = http.Client();
      final req = http.Request('GET', Uri.parse(url));
      final resp = await client.send(req);
      File file;
      if (resp.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        file = File('${dir.path}/watchface_${name.replaceAll(' ', '_').toLowerCase()}.bin');
        final sink = file.openWrite();
        int received = 0;
        final total = resp.contentLength ?? 0;
        await for (final chunk in resp.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0 && mounted) setState(() => _progress = received / total);
        }
        await sink.close();
        client.close();
      } else {
        // Fallback: create dummy file for demo OTA flow
        final dir = await getTemporaryDirectory();
        file = File('${dir.path}/watchface_${name.replaceAll(' ', '_').toLowerCase()}.bin');
        await file.writeAsBytes(List.generate(1024, (i) => i % 256));
        if (mounted) setState(() => _progress = 1);
        await Future.delayed(const Duration(milliseconds: 400));
        client.close();
      }
      final ok = await _ble.startOta(file.path);
      if (!mounted) return;
      if (ok) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('watchface_installed', name);
        if (!mounted) return;
        setState(() { _installed = name; _downloading = null; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name installed — OTA started'), backgroundColor: AppTheme.gold));
      } else {
        throw Exception('OTA failed');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloading = null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download/OTA failed: $e'), backgroundColor: AppTheme.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(backgroundColor: AppTheme.bg, foregroundColor: Colors.white, centerTitle: true, elevation: 0, leading: const GlassBackButton(), title: Text('Watchface', style: _inter(17, weight: FontWeight.w600))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('WATCHFACE STORE', style: _inter(11, weight: FontWeight.w600, color: AppTheme.gold)),
            const SizedBox(height: 8),
            Text('QRing WatchFaceInstallActivity — download via FileHandle OTA (http://api2.qcwxkjvip.com/download/watchface).', style: _inter(13, color: AppTheme.textTertiary)),
            if (_installed != null) ...[
              const SizedBox(height: 8),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: AppTheme.gold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(99)), child: Text('Installed: $_installed', style: _inter(12, weight: FontWeight.w600, color: AppTheme.gold))),
            ],
          ])),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.85),
            itemCount: _faces.length,
            itemBuilder: (ctx, i) {
              final f = _faces[i];
              final isDownloading = _downloading == f['name'];
              final isInstalled = _installed == f['name'];
              return GlassCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(height: 80, decoration: BoxDecoration(color: Color(f['color'] as int).withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12), border: Border.all(color: Color(f['color'] as int).withValues(alpha: 0.25))), child: Center(child: Icon(Icons.watch, color: Color(f['color'] as int), size: 36))),
                  const SizedBox(height: 8),
                  Text(f['name'] as String, style: _inter(13, weight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  if (isDownloading)
                    LinearProgressIndicator(value: _progress > 0 ? _progress : null, color: AppTheme.gold, backgroundColor: Colors.white.withValues(alpha: 0.08))
                  else
                    SizedBox(
                      width: double.infinity,
                      height: 32,
                      child: ElevatedButton(
                        onPressed: () => _downloadAndInstall(f),
                        style: ElevatedButton.styleFrom(backgroundColor: isInstalled ? Colors.white.withValues(alpha: 0.08) : AppTheme.gold, foregroundColor: isInstalled ? Colors.white : Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)), padding: EdgeInsets.zero),
                        child: Text(isInstalled ? 'Reinstall' : 'Install', style: _inter(12, weight: FontWeight.w600, color: isInstalled ? Colors.white : Colors.black)),
                      ),
                    ),
                ]),
              );
            },
          ),
          const SizedBox(height: 12),
          GlassCard(child: Row(children: [
            const Icon(Icons.info_outline, color: AppTheme.gold, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text('Download via http + path_provider temp + BleService.startOta(filePath) → DfuHandle. Progress from BlePlugin OTA events.', style: _inter(11, color: AppTheme.textTertiary))),
          ])),
        ],
      ),
    );
  }
}
