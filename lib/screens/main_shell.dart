import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/main_tab_provider.dart';
import '../providers/workout_provider.dart';
import 'home/home_screen.dart';
import 'settings/settings_screen.dart';
import 'workouts/active_workout_screen.dart';
import 'assist/chat_screen.dart';
import 'settings/profile_edit_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  @override
  void initState() {
    super.initState();
    context.read<WorkoutProvider>().initialized.then((_) {
      if (!mounted) return;
      final workout = context.read<WorkoutProvider>();
      if (workout.isWorkoutActive) {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ActiveWorkoutScreen()));
      }
    });
  }

  void _onTabTap(int index) {
    final workout = context.read<WorkoutProvider>();
    if (workout.isWorkoutActive) {
      _showWorkoutLockSheet();
      return;
    }
    context.read<MainTabProvider>().setTab(index);
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
            const Icon(
              Icons.directions_run_rounded,
              color: AppTheme.gold,
              size: 40,
            ),
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
    final tab = context.watch<MainTabProvider>().tab;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color.fromRGBO(8, 8, 8, 1),
        body: IndexedStack(
          index: tab,
          children: const [
            HomeScreen(),
            ChatScreen(),
            ProfileEditScreen(showBackButton: false),
            SettingsScreen(),
          ],
        ),
        bottomNavigationBar: _BottomNav(selected: tab, onTap: _onTabTap),
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
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0x8C050505), // rgba(5,5,5,0.55)
            border: Border(
              top: BorderSide(
                color: Color(0x0DFFFFFF),
                width: 0.5,
              ), // rgba(255,255,255,0.05)
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(36, 12, 36, 14),
              child: SizedBox(
                height: 44,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _NavTab(
                      icon: Icons.home_outlined,
                      label: 'Home',
                      active: selected == 0,
                      onTap: () => onTap(0),
                    ),
                    _NavTab(
                      icon: Icons.auto_awesome,
                      label: 'AI assist',
                      active: selected == 1,
                      onTap: () => onTap(1),
                    ),
                    _NavTab(
                      icon: Icons.person_outline_rounded,
                      label: 'Profile',
                      active: selected == 2,
                      onTap: () => onTap(2),
                    ),
                    _NavTab(
                      icon: Icons.settings_outlined,
                      label: 'Settings',
                      active: selected == 3,
                      onTap: () => onTap(3),
                    ),
                  ],
                ),
              ),
            ),
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

  static const _kGold = Color(0xFFC9A86E);
  static const _kInactive = Color(0x52FFFFFF); // rgba(255,255,255,0.32)

  @override
  Widget build(BuildContext context) {
    final color = active ? _kGold : _kInactive;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.instrumentSans(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: color,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
