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

  // AI Assist is no longer a tab in the IndexedStack — it's pushed as its
  // own full-screen route. That means the bottom nav (which only lives in
  // this shell's build method) is structurally absent while chat is open,
  // and reappears automatically the moment Navigator.pop brings the user
  // back here — no manual show/hide state needed.
  void _openAiAssist() {
    final workout = context.read<WorkoutProvider>();
    if (workout.isWorkoutActive) {
      _showWorkoutLockSheet();
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ChatScreen()));
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
    // tab is still 0 (Home) or 2 (Settings) from MainTabProvider — the
    // IndexedStack below only has two children now, so we map tab 2 -> 1.
    final tab = context.watch<MainTabProvider>().tab;
    final stackIndex = tab == 2 ? 1 : 0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color.fromRGBO(8, 8, 8, 1),
        // Without this, Scaffold reserves space and stops `body` short of
        // bottomNavigationBar — so the BackdropFilter behind the pill only
        // ever blurs empty black Scaffold background, not your actual
        // scrolled content, which is what was reading as a solid black box.
        extendBody: true,
        // Home and Settings only — AI Assist is pushed separately, so the
        // bottom nav (built right below) never renders while it's open.
        body: IndexedStack(
          index: stackIndex,
          children: const [HomeScreen(), SettingsScreen()],
        ),
        bottomNavigationBar: _BottomNav(
          selected: tab,
          onTap: _onTabTap,
          onAssistTap: _openAiAssist,
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onTap;
  final VoidCallback onAssistTap;

  const _BottomNav({
    required this.selected,
    required this.onTap,
    required this.onAssistTap,
  });

  @override
  Widget build(BuildContext context) {
    // Scaffold wraps bottomNavigationBar in an opaque Material by default
    // (theme's canvas/bottom-app-bar color) — that was the solid black
    // rounded box showing behind the glass pill. Material(transparency)
    // removes that fill so only the pill itself (with its own translucent
    // background + blur) is visible, letting it truly float over content.
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        top: false,
        // Lock text scaling for just the nav bar. A user's accessibility
        // font-size setting (or a phone with a different default scale) is
        // exactly what caused the "works on my phone, not yours" overflow —
        // this makes the nav's own layout independent of that setting while
        // leaving the rest of the app scaling normally.
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.0)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            // Row(mainAxisAlignment: center) centers horizontally without
            // expanding to fill available height — unlike Center()/Align(),
            // which grab all loose vertical space and end up centering the
            // pill in the middle of the whole screen while squashing the body.
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(
                          0x08FFFFFF,
                        ), // rgba(255,255,255,0.03)
                        border: Border.all(
                          color: const Color(
                            0x17FFFFFF,
                          ), // rgba(255,255,255,0.09)
                        ),
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _NavTab(
                            icon: Icons.home_outlined,
                            label: 'Home',
                            active: selected == 0,
                            onTap: () => onTap(0),
                          ),
                          const SizedBox(width: 24),
                          _NavFab(onTap: onAssistTap),
                          const SizedBox(width: 24),
                          _NavTab(
                            icon: Icons.settings_outlined,
                            label: 'Settings',
                            active: selected == 2,
                            onTap: () => onTap(2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
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
      child: Container(
        // No fixed height — the Column hugs its own content (icon + gap +
        // label) via MainAxisSize.min, so it can never be shorter than what
        // it needs to render, on any device/font-scale combination.
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0x0DFFFFFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: color,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavFab extends StatelessWidget {
  final VoidCallback onTap;

  const _NavFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 48,
        height: 48,
        // No fill/color here beyond the gradient below — the circle itself
        // is the only background; the icon sits directly on it with
        // nothing else behind it.
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: Alignment(0, 0),
            radius: 0.9,
            colors: [Color(0xFFE0BC85), Color(0xFFC9A86E), Color(0xFF8E7A55)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: const Icon(
          // Spec: star vector fill is rgba(5,5,5,0.85) — a dark icon sitting
          // on the gold gradient, not white.
          Icons.auto_awesome,
          color: Color(0xD9050505),
          size: 24,
        ),
      ),
    );
  }
}
