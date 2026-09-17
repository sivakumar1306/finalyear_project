import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/incident_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/glass_card.dart';

TextStyle _inter(double size, {FontWeight weight = FontWeight.w400, Color color = Colors.white}) =>
    AppTypography.inter(fontSize: size, fontWeight: weight, color: color);

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});
  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _ranking = [];
  bool _loading = true;
  static const _kLocalKey = 'friends_local_v1';

  @override
  void initState() { super.initState(); _tab = TabController(length: 2, vsync: this); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    List<Map<String, dynamic>> friends = [];
    final user = SupabaseService.currentUser;
    if (user != null) {
      try {
        final rows = await SupabaseService.client.from('user_friends').select().eq('user_id', user.id).order('created_at');
        friends = (rows as List).map((e) => Map<String,dynamic>.from(e as Map)).toList();
      } catch (_) {}
      // Ranking via user_steps (best-effort)
      try {
        final steps = await SupabaseService.client.from('user_steps').select().order('steps', ascending: false).limit(10);
        _ranking = (steps as List).map((e) => Map<String,dynamic>.from(e as Map)).toList();
      } catch (_) {}
    }
    if (friends.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_kLocalKey);
        if (raw != null) friends = (jsonDecode(raw) as List).map((e) => Map<String,dynamic>.from(e as Map)).toList();
      } catch (_) {}
    }
    if (mounted) setState(() { _friends = friends; _loading = false; });
  }

  Future<void> _invite() async {
    final user = SupabaseService.currentUser;
    final code = user?.id.substring(0, 8) ?? 'SUNDR-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    await SharePlus.instance.share(ShareParams(text: 'Join me on SUNDR — invite code $code — https://sundr.app/invite/$code'));
  }

  Future<void> _addFriend() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.card,
      title: Text('Add Friend', style: _inter(16, weight: FontWeight.w600)),
      content: TextField(controller: ctrl, decoration: InputDecoration(hintText: 'Friend email or ID', hintStyle: _inter(13, color: AppTheme.textTertiary)), style: _inter(14)),
      actions: [TextButton(onPressed: ()=> Navigator.pop(ctx,false), child: Text('Cancel', style: _inter(13))), ElevatedButton(onPressed: ()=> Navigator.pop(ctx,true), style: ElevatedButton.styleFrom(backgroundColor: AppTheme.gold), child: Text('Add', style: _inter(13, color: Colors.black)))],
    ));
    if (ok != true || ctrl.text.trim().isEmpty) return;
    final entry = {'friend_id': ctrl.text.trim(), 'status': 'pending', 'created_at': DateTime.now().toIso8601String()};
    final next = [..._friends, entry];
    setState(() => _friends = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLocalKey, jsonEncode(next));
    } catch (_) {}
    final user = SupabaseService.currentUser;
    if (user != null) {
      try {
        await SupabaseService.client.from('user_friends').insert({'user_id': user.id, 'friend_user_id': ctrl.text.trim(), 'status': 'pending'});
      } catch (e, st) {
        IncidentService.reportUnhandled(source: 'friends_screen', error: e, stackTrace: st, customMessage: 'Friend insert to Supabase failed');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(backgroundColor: AppTheme.bg, foregroundColor: Colors.white, centerTitle: true, elevation: 0, leading: const GlassBackButton(), title: Text('Friends', style: _inter(17, weight: FontWeight.w600)), bottom: TabBar(controller: _tab, labelColor: AppTheme.gold, unselectedLabelColor: Colors.white54, indicatorColor: AppTheme.gold, tabs: const [Tab(text: 'Friends'), Tab(text: 'Ranking')])),
      floatingActionButton: FloatingActionButton(onPressed: _addFriend, backgroundColor: AppTheme.gold, child: const Icon(Icons.person_add, color: Colors.black)),
      body: _loading ? const Center(child: CircularProgressIndicator(color: AppTheme.gold)) : TabBarView(controller: _tab, children: [
        RefreshIndicator(color: AppTheme.gold, backgroundColor: AppTheme.card, onRefresh: _load, child: _friends.isEmpty
            ? ListView(padding: const EdgeInsets.all(16), children: [GlassCard(child: Column(children: [Text('No friends yet', style: _inter(14, weight: FontWeight.w600)), const SizedBox(height: 8), Text('Invite via QR/share. Ranking syncs step_detail via Supabase.', style: _inter(12, color: AppTheme.textTertiary), textAlign: TextAlign.center), const SizedBox(height: 12), ElevatedButton(onPressed: _invite, style: ElevatedButton.styleFrom(backgroundColor: AppTheme.gold), child: Text('Invite', style: _inter(13, color: Colors.black)))]))])
            : ListView.separated(padding: const EdgeInsets.all(16), itemCount: _friends.length, separatorBuilder: (context, index)=> const SizedBox(height: 8), itemBuilder: (ctx,i){
              final f = _friends[i];
              return GlassCard(child: Row(children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: AppTheme.gold.withValues(alpha:0.15), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.person, color: AppTheme.gold, size: 18)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(f['friend_id']?.toString() ?? 'Friend ${i+1}', style: _inter(14, weight: FontWeight.w600)), Text(f['status']?.toString() ?? 'pending', style: _inter(11, color: AppTheme.textTertiary))])),
                Icon(Icons.chevron_right, color: Colors.white.withValues(alpha:0.3), size: 18),
              ]));
            })),
        RefreshIndicator(color: AppTheme.gold, backgroundColor: AppTheme.card, onRefresh: _load, child: _ranking.isEmpty
            ? ListView(padding: const EdgeInsets.all(16), children: [GlassCard(child: Column(children: [Text('Ranking', style: _inter(14, weight: FontWeight.w600)), const SizedBox(height: 8), Text('Top step counts from user_steps. Invite friends to populate.', style: _inter(12, color: AppTheme.textTertiary), textAlign: TextAlign.center)]))])
            : ListView.separated(padding: const EdgeInsets.all(16), itemCount: _ranking.length, separatorBuilder: (context, index)=> const SizedBox(height: 8), itemBuilder: (ctx,i){
              final r = _ranking[i];
              return GlassCard(child: Row(children: [
                Container(width: 28, height: 28, decoration: BoxDecoration(color: i==0? AppTheme.gold : Colors.white.withValues(alpha:0.06), borderRadius: BorderRadius.circular(8)), child: Center(child: Text('${i+1}', style: _inter(12, weight: FontWeight.w600, color: i==0? Colors.black: Colors.white)))),
                const SizedBox(width: 12),
                Expanded(child: Text(r['user_id']?.toString().substring(0,8) ?? 'User', style: _inter(13))),
                Text('${r['steps'] ?? 0} steps', style: _inter(13, weight: FontWeight.w600, color: AppTheme.gold)),
              ]));
            })),
      ]),
    );
  }
}
