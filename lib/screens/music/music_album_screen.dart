import 'package:flutter/material.dart';
import '../../services/ble_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/glass_card.dart';

TextStyle _inter(double size, {FontWeight weight = FontWeight.w400, Color color = Colors.white}) =>
    AppTypography.inter(fontSize: size, fontWeight: weight, color: color);

class MusicAlbumScreen extends StatefulWidget {
  const MusicAlbumScreen({super.key});
  @override
  State<MusicAlbumScreen> createState() => _MusicAlbumScreenState();
}

class _MusicAlbumScreenState extends State<MusicAlbumScreen> {
  final _ble = BleService();
  bool _playing = false;

  Future<void> _toggle() async {
    try {
      final ok = await _ble.toggleMediaPlayPause();
      if (!mounted) return;
      setState(() => _playing = !_playing);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? (_playing ? 'Playing' : 'Paused') : 'Toggle failed'), backgroundColor: AppTheme.gold));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final albums = const [
      {'title': 'Chill Focus', 'artist': 'Sundr Mix', 'count': '12 tracks'},
      {'title': 'Night Run', 'artist': 'Sundr Mix', 'count': '9 tracks'},
      {'title': 'Deep Sleep', 'artist': 'Sundr Mix', 'count': '7 tracks'},
    ];
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(backgroundColor: AppTheme.bg, foregroundColor: Colors.white, centerTitle: true, elevation: 0, leading: const GlassBackButton(), title: Text('Music', style: _inter(17, weight: FontWeight.w600))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(child: Row(children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: AppTheme.gold.withValues(alpha:0.15), borderRadius: BorderRadius.circular(12)), child: Icon(_playing ? Icons.pause : Icons.play_arrow, color: AppTheme.gold)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_playing ? 'Playing' : 'Ring Media Control', style: _inter(14, weight: FontWeight.w600)), Text('BleService.toggleMediaPlayPause() via ring gesture', style: _inter(11, color: AppTheme.textTertiary))])),
            ElevatedButton(onPressed: _toggle, style: ElevatedButton.styleFrom(backgroundColor: AppTheme.gold, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))), child: Text(_playing ? 'Pause' : 'Play', style: _inter(12, weight: FontWeight.w600, color: Colors.black))),
          ])),
          const SizedBox(height: 12),
          for (final a in albums)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: GlassCard(child: Row(children: [
              Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white.withValues(alpha:0.06), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.album, color: Colors.white70)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(a['title']!, style: _inter(14, weight: FontWeight.w600)), Text('${a['artist']} · ${a['count']}', style: _inter(11, color: AppTheme.textTertiary))])),
              const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
            ]))),
        ],
      ),
    );
  }
}
