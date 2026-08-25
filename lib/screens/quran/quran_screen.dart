import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/glass_card.dart';

TextStyle _inter(double size, {FontWeight weight = FontWeight.w400, Color color = Colors.white, double? letterSpacing}) =>
    AppTypography.inter(fontSize: size, fontWeight: weight, color: color, letterSpacing: letterSpacing);

class QuranScreen extends StatefulWidget {
  const QuranScreen({super.key});
  @override
  State<QuranScreen> createState() => _QuranScreenState();
}

class _QuranScreenState extends State<QuranScreen> {
  List<Map<String, dynamic>> _chapters = [];
  Set<int> _bookmarks = {};
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final raw = await rootBundle.loadString('assets/quran/quran.json');
      final decoded = jsonDecode(raw);
      List list;
      if (decoded is Map && decoded['quran'] is List) {
        list = decoded['quran'] as List;
      } else if (decoded is List) {
        list = decoded;
      } else {
        list = [];
      }
      final chapters = list.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('quran_bookmarks') ?? [];
      final bm = saved.map((s) => int.tryParse(s) ?? -1).where((i) => i >= 0).toSet();

      // Try Supabase bookmarks (best-effort, table may not exist yet)
      try {
        final user = SupabaseService.currentUser;
        if (user != null) {
          final rows = await SupabaseService.client.from('user_quran_bookmarks').select().eq('user_id', user.id);
          for (final r in (rows as List)) {
            final idx = (r['chapter_index'] as num?)?.toInt() ?? (r['content_uuid'] as num?)?.toInt();
            if (idx != null && idx >= 0) bm.add(idx);
          }
        }
      } catch (_) {}

      if (mounted) setState(() { _chapters = chapters; _bookmarks = bm; });
    } catch (_) {
      if (mounted) setState(() => _chapters = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleBookmark(int idx) async {
    final next = Set<int>.from(_bookmarks);
    if (next.contains(idx)) {
      next.remove(idx);
    } else {
      next.add(idx);
    }
    setState(() => _bookmarks = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('quran_bookmarks', next.map((e) => e.toString()).toList());
    // Supabase sync best-effort
    try {
      final user = SupabaseService.currentUser;
      if (user != null) {
        if (_bookmarks.contains(idx)) {
          await SupabaseService.client.from('user_quran_bookmarks').delete().eq('user_id', user.id).eq('chapter_index', idx);
        } else {
          await SupabaseService.client.from('user_quran_bookmarks').insert({'user_id': user.id, 'chapter_index': idx, 'is_collection': true});
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _chapters.asMap().entries.where((e) {
      if (_query.isEmpty) return true;
      final title = (e.value['chapterTitle']?['english'] ?? e.value['title'] ?? '').toString().toLowerCase();
      return title.contains(_query.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(backgroundColor: AppTheme.bg, foregroundColor: Colors.white, centerTitle: true, elevation: 0, leading: const GlassBackButton(), title: Text('Quran', style: _inter(17, weight: FontWeight.w600))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              style: _inter(14),
              decoration: InputDecoration(
                hintText: 'Search chapter',
                hintStyle: _inter(13, color: AppTheme.textTertiary),
                prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 18),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: 8),
          if (_loading) const LinearProgressIndicator(color: AppTheme.gold, backgroundColor: Colors.transparent),
          Expanded(
            child: _loading
                ? const SizedBox.shrink()
                : filtered.isEmpty
                    ? Center(child: Text('No chapters', style: _inter(13, color: AppTheme.textTertiary)))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final idx = filtered[i].key;
                          final chap = filtered[i].value;
                          final titleMap = chap['chapterTitle'] as Map? ?? {};
                          final title = (titleMap['english'] ?? chap['title'] ?? 'Chapter ${idx + 1}').toString();
                          final verses = (chap['chapterListEnglish'] as List? ?? chap['verses'] as List? ?? []).length;
                          final isBm = _bookmarks.contains(idx);
                          return GlassCard(
                            child: InkWell(
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _ChapterDetail(chapterIndex: idx, data: chap, isBookmarked: isBm, onToggle: () => _toggleBookmark(idx)))),
                              borderRadius: BorderRadius.circular(20),
                              child: Row(children: [
                                Container(width: 36, height: 36, decoration: BoxDecoration(color: AppTheme.gold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)), child: Center(child: Text('${idx + 1}', style: _inter(13, weight: FontWeight.w600, color: AppTheme.gold)))),
                                const SizedBox(width: 12),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(title, style: _inter(14, weight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  Text('$verses verses', style: _inter(12, color: AppTheme.textTertiary)),
                                ])),
                                IconButton(icon: Icon(isBm ? Icons.bookmark : Icons.bookmark_border, color: isBm ? AppTheme.gold : Colors.white54, size: 20), onPressed: () => _toggleBookmark(idx)),
                              ]),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _ChapterDetail extends StatelessWidget {
  final int chapterIndex;
  final Map<String, dynamic> data;
  final bool isBookmarked;
  final VoidCallback onToggle;
  const _ChapterDetail({required this.chapterIndex, required this.data, required this.isBookmarked, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final titleMap = data['chapterTitle'] as Map? ?? {};
    final title = (titleMap['english'] ?? 'Chapter ${chapterIndex + 1}').toString();
    final versesEn = (data['chapterListEnglish'] as List? ?? []).cast<dynamic>();
    final versesAr = (data['chapterListArabic'] as List? ?? data['chapterListChinese'] as List? ?? []).cast<dynamic>();
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(backgroundColor: AppTheme.bg, foregroundColor: Colors.white, centerTitle: true, elevation: 0, leading: const GlassBackButton(), title: Text(title, style: _inter(15, weight: FontWeight.w600)), actions: [IconButton(icon: Icon(isBookmarked ? Icons.bookmark : Icons.bookmark_border, color: isBookmarked ? AppTheme.gold : Colors.white), onPressed: onToggle)]),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: versesEn.length,
        itemBuilder: (context, i) {
          final en = versesEn[i].toString();
          final ar = i < versesAr.length ? versesAr[i].toString() : '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${i + 1}. $en', style: _inter(14, height: 1.4)),
                if (ar.isNotEmpty && !ar.contains('�')) ...[
                  const SizedBox(height: 6),
                  Text(ar, style: _inter(13, color: AppTheme.textTertiary), textAlign: TextAlign.right),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }
}
