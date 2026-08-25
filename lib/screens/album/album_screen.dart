import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/ble_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/glass_card.dart';

TextStyle _inter(double size, {FontWeight weight = FontWeight.w400, Color color = Colors.white}) =>
    AppTypography.inter(fontSize: size, fontWeight: weight, color: color);

class AlbumScreen extends StatefulWidget {
  const AlbumScreen({super.key});
  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  List<File> _files = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dir = await getTemporaryDirectory();
      final list = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.jpg') || f.path.endsWith('.png') || f.path.endsWith('.mp4')).toList();
      // Also try to scan via BleService scanMediaFile for ring photos (best-effort)
      try { await BleService().scanMediaFile(dir.path); } catch (_) {}
      if (mounted) setState(() { _files = list.take(20).toList(); });
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(backgroundColor: AppTheme.bg, foregroundColor: Colors.white, centerTitle: true, elevation: 0, leading: const GlassBackButton(), title: Text('Album', style: _inter(17, weight: FontWeight.w600))),
      body: _loading ? const Center(child: CircularProgressIndicator(color: AppTheme.gold)) : _files.isEmpty
          ? ListView(padding: const EdgeInsets.all(16), children: [GlassCard(child: Column(children: [Text('No photos yet', style: _inter(14, weight: FontWeight.w600)), const SizedBox(height: 8), Text('Ring camera photos via BleService.takePicture() appear here after scanMediaFile. Take a photo from Ring Camera screen.', style: _inter(12, color: AppTheme.textTertiary), textAlign: TextAlign.center)]))])
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12),
              itemCount: _files.length,
              itemBuilder: (ctx,i){
                final f = _files[i];
                return GlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Container(decoration: BoxDecoration(color: Colors.white.withValues(alpha:0.06), borderRadius: BorderRadius.circular(12)), child: f.path.endsWith('.mp4') ? const Center(child: Icon(Icons.videocam, color: AppTheme.gold, size: 28)) : ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(f, fit: BoxFit.cover, errorBuilder: (_,__,___)=> const Center(child: Icon(Icons.image, color: Colors.white24)))))),
                  const SizedBox(height: 8),
                  Text(f.uri.pathSegments.last, style: _inter(11, color: AppTheme.textTertiary), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]));
              },
            ),
    );
  }
}
