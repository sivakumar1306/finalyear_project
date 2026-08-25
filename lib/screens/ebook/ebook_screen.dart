import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/glass_card.dart';

TextStyle _inter(double size, {FontWeight weight = FontWeight.w400, Color color = Colors.white}) =>
    AppTypography.inter(fontSize: size, fontWeight: weight, color: color);

class EbookScreen extends StatelessWidget {
  const EbookScreen({super.key});

  final List<Map<String,String>> _books = const [
    {'title': 'Ring User Guide', 'pages': '42 pages', 'desc': 'QRing EbookManager — device manual.'},
    {'title': 'Health Insights', 'pages': '18 pages', 'desc': 'Wellness companion notes.'},
    {'title': 'Meditation Basics', 'pages': '28 pages', 'desc': 'Breathing & focus guide.'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(backgroundColor: AppTheme.bg, foregroundColor: Colors.white, centerTitle: true, elevation: 0, leading: const GlassBackButton(), title: Text('Ebook', style: _inter(17, weight: FontWeight.w600))),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _books.length,
        separatorBuilder: (_,__)=> const SizedBox(height: 8),
        itemBuilder: (ctx,i){
          final b = _books[i];
          return GlassCard(child: Row(children: [
            Container(width: 48, height: 64, decoration: BoxDecoration(color: AppTheme.gold.withValues(alpha:0.12), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white.withValues(alpha:0.08))), child: const Icon(Icons.menu_book, color: AppTheme.gold)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b['title']!, style: _inter(14, weight: FontWeight.w600)),
              Text(b['pages']!, style: _inter(11, color: AppTheme.gold)),
              Text(b['desc']!, style: _inter(12, color: AppTheme.textTertiary)),
            ])),
            const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
          ]));
        },
      ),
    );
  }
}
