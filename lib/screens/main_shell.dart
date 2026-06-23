import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/workout_provider.dart';
import 'home/home_screen.dart';
import 'assist/assist_screen.dart';
import 'records/records_screen.dart';
import 'settings/settings_screen.dart';
import 'workouts/workouts_screen.dart';
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
        setState(() => _tab = 4);
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ActiveWorkoutScreen()),
        );
      }
    });
  }

  void _onTabTap(int index) {
    final workout = context.read<WorkoutProvider>();
    if (workout.isWorkoutActive && index != 4) {
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
                  setState(() => _tab = 4);
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
        backgroundColor: AppTheme.bg,
        body: IndexedStack(
          index: _tab,
          children: const [
            HomeScreen(),
            AssistScreen(),
            RecordsScreen(),
            SettingsScreen(),
            WorkoutsScreen(),
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
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D0D),
        border: Border(top: BorderSide(color: AppTheme.div, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _NavTab(
                icon: Icons.home_rounded,
                label: 'Home',
                active: selected == 0,
                onTap: () => onTap(0),
              ),
              _NavTab(
                icon: Icons.smart_toy_rounded,
                label: 'Assist',
                active: selected == 1,
                onTap: () => onTap(1),
              ),
              _NavTab(
                icon: Icons.bar_chart_rounded,
                label: 'Records',
                active: selected == 2,
                onTap: () => onTap(2),
              ),
              _NavTab(
                icon: Icons.person_rounded,
                label: 'Profile',
                active: selected == 3,
                onTap: () => onTap(3),
              ),
              _NavTab(
                icon: Icons.directions_run_rounded,
                label: 'Workouts',
                active: selected == 4,
                onTap: () => onTap(4),
              ),
            ],
          ),
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

  @override
  Widget build(BuildContext context) {
    final color = active ? AppTheme.gold : const Color(0xFF484848);
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
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
