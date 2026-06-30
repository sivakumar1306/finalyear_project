import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/ble_provider.dart';
import '../providers/workout_provider.dart';
import 'home/home_screen.dart';
import 'assist/assist_screen.dart';
import 'records/records_screen.dart';
import 'settings/settings_screen.dart';
import 'workouts/active_workout_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Navigate to active workout screen if a workout was resumed after app restart.
    context.read<WorkoutProvider>().initialized.then((_) {
      if (!mounted) return;
      final workout = context.read<WorkoutProvider>();
      if (workout.isWorkoutActive) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ActiveWorkoutScreen()),
        );
      }
    });
  }

  void _onTabTap(int index) {
    final workout = context.read<WorkoutProvider>();
    if (workout.isWorkoutActive) {
      _showWorkoutLockSheet();
      return;
    }
    setState(() => _tab = index);
  }

  void _showWorkoutLockSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.div,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Icon(Icons.directions_run_rounded, color: AppTheme.gold, size: 40),
            const SizedBox(height: 14),
            const Text(
              'Workout in Progress',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Finish your workout to access other features.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSec, fontSize: 14),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.gold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ActiveWorkoutScreen(),
                    ),
                  );
                },
                child: const Text(
                  'Go to Workout',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color.fromRGBO(8, 8, 8, 1),
        body: Stack(
          children: [
            // Block all card taps / Navigator.push calls while sync is running.
            // AbsorbPointer sits on the IndexedStack only — the bottomNavigationBar
            // lives outside this Stack so tab switching remains usable.
            Consumer<BleProvider>(
              builder: (context, ble, child) => AbsorbPointer(
                absorbing: ble.isSyncing,
                child: child!,
              ),
              child: IndexedStack(
                index: _tab,
                children: const [
                  HomeScreen(),
                  AssistScreen(),
                  RecordsScreen(),
                  SettingsScreen(),
                ],
              ),
            ),
            // Overlay is pointer-transparent — the AbsorbPointer above handles
            // blocking; this just renders the progress visually.
            Consumer<BleProvider>(
              builder: (context, ble, _) => IgnorePointer(
                child: AnimatedOpacity(
                  opacity: ble.isSyncing ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: _SyncOverlay(
                    progress: ble.syncProgress,
                    step: ble.syncStep,
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _BottomNav(
          selected: _tab,
          onTap: _onTabTap,
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0x0AFFFFFF),   // rgba(255,255,255,0.04)
            border: Border(
              top: BorderSide(color: Color(0x17FFFFFF), width: 0.5),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 60,
              child: Row(
                children: [
                  _NavTab(icon: Icons.home_rounded,      label: 'Home',     active: selected == 0, onTap: () => onTap(0)),
                  _NavTab(icon: Icons.smart_toy_rounded,  label: 'Assist',   active: selected == 1, onTap: () => onTap(1)),
                  _NavTab(icon: Icons.bar_chart_rounded,  label: 'Records',  active: selected == 2, onTap: () => onTap(2)),
                  _NavTab(icon: Icons.settings_rounded,   label: 'Settings', active: selected == 3, onTap: () => onTap(3)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Sync overlay (circular progress) ─────────────────────────────────────────

class _SyncOverlay extends StatelessWidget {
  final double progress;
  final String step;
  const _SyncOverlay({required this.progress, required this.step});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.78),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 112,
              height: 112,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: progress),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOut,
                builder: (context, value, _) {
                  final pct = (value * 100).round();
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: value,
                        strokeWidth: 5.0,
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.gold),
                      ),
                      Text(
                        '$pct%',
                        style: GoogleFonts.inter(
                          fontSize: 24,
                          fontWeight: FontWeight.w300,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Syncing Ring',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                step.isEmpty ? 'Preparing...' : step,
                key: ValueKey(step),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavTab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  static const _kGold     = Color(0xFFC9A86E);
  static const _kInactive = Color(0x66FFFFFF);   // rgba(255,255,255,0.4)

  @override
  Widget build(BuildContext context) {
    final color = active ? _kGold : _kInactive;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
