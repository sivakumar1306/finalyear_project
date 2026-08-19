import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_typography.dart';

/// Post-Session Workout-style Summary for Prayer Mode.
class PrayerSummaryScreen extends StatefulWidget {
  final int durationSeconds;
  final int avgHr;
  final int avgHrv;
  final int peakCalmness;
  final String rating;

  const PrayerSummaryScreen({
    super.key,
    required this.durationSeconds,
    required this.avgHr,
    required this.avgHrv,
    required this.peakCalmness,
    required this.rating,
  });

  @override
  State<PrayerSummaryScreen> createState() => _PrayerSummaryScreenState();
}

class _PrayerSummaryScreenState extends State<PrayerSummaryScreen> {
  bool _isSaving = true;

  @override
  void initState() {
    super.initState();
    _saveSession();
  }

  Future<void> _saveSession() async {
    final sessionMap = {
      'workout_type': 'Prayer',
      'duration_seconds': widget.durationSeconds,
      'avg_heart_rate': widget.avgHr,
      'avg_hrv': widget.avgHrv,
      'calmness_score': widget.peakCalmness,
      'rating': widget.rating,
      'created_at': DateTime.now().toIso8601String(),
    };

    // Save locally to SharedPreferences so history works offline & instantly
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingJsonList = prefs.getStringList('prayer_sessions_history') ?? [];
      existingJsonList.insert(0, jsonEncode(sessionMap));
      if (existingJsonList.length > 100) existingJsonList.removeLast();
      await prefs.setStringList('prayer_sessions_history', existingJsonList);
    } catch (e) {
      debugPrint('Error saving local prayer session: $e');
    }

    // Save to Supabase
    try {
      final user = SupabaseService.currentUser;
      if (user != null) {
        await SupabaseService.client.from('workouts').insert({
          'user_id': user.id,
          ...sessionMap,
        });
      }
    } catch (e) {
      debugPrint('Error saving prayer workout to Supabase: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _formatDuration(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Prayer Session Summary',
          style: AppTypography.inter(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 10),
            // Glowing Serenity Badge
            Container(
              width: 165,
              height: 165,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.gold.withValues(alpha: 0.15),
                border: Border.all(color: AppTheme.gold, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.gold.withValues(alpha: 0.35),
                    blurRadius: 25,
                    spreadRadius: 2,
                  )
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.self_improvement_rounded, color: AppTheme.gold, size: 38),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.peakCalmness}%',
                    style: AppTypography.inter(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Calmness',
                    style: AppTypography.inter(
                      color: AppTheme.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            Text(
              widget.rating,
              style: AppTypography.inter(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Recorded in Workout & Wellness History',
              style: AppTypography.inter(
                color: AppTheme.textSec,
                fontSize: 13,
              ),
            ),

            const SizedBox(height: 28),

            // 13-Metric Summary Cards Grid
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.6,
              children: [
                _SummaryTile(
                  icon: Icons.timer_rounded,
                  label: 'Duration',
                  value: _formatDuration(widget.durationSeconds),
                  color: AppTheme.gold,
                ),
                _SummaryTile(
                  icon: Icons.favorite_rounded,
                  label: 'Avg Heart Rate',
                  value: widget.avgHr > 0 ? '${widget.avgHr} bpm' : '--',
                  color: Colors.redAccent,
                ),
                _SummaryTile(
                  icon: Icons.favorite_border_rounded,
                  label: 'Avg HRV',
                  value: widget.avgHrv > 0 ? '${widget.avgHrv} ms' : '--',
                  color: Colors.lightBlueAccent,
                ),
                _SummaryTile(
                  icon: Icons.do_not_disturb_on_rounded,
                  label: 'Phone Status',
                  value: 'DND Active',
                  color: AppTheme.gold,
                ),
              ],
            ),

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.gold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  'Done',
                  style: AppTypography.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            if (_isSaving)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Syncing session with Supabase...',
                  style: AppTypography.inter(color: AppTheme.textSec, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SummaryTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.inter(
                    color: AppTheme.textSec,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTypography.inter(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
