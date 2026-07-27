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
    // AI Assist (index 1) hides the floating nav entirely and shows its own
    // back arrow instead (see chat_screen.dart) — the pill was overlapping
    // the chat input bar / message list, and the product wants a focused,
    // full-screen chat experience without the persistent nav competing for
    // space at the bottom.
    final showBottomNav = tab != 1;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color.fromRGBO(8, 8, 8, 1),
        extendBody: true,
        // Only 3 real tabs — Profile lives inside Settings now (see
        // settings_screen.dart's "User Profile" row), not as its own
        // bottom-nav destination. Index: Home=0, AI assist=1, Settings=2.
        body: IndexedStack(
          index: tab,
          children: [
            const HomeScreen(),
            ChatScreen(onBack: () => _onTabTap(0)),
            const SettingsScreen(),
          ],
        ),
        bottomNavigationBar: showBottomNav
            ? _BottomNav(selected: tab, onTap: _onTabTap)
            : null,
      ),
    );
  }
}

/// Glassmorphic floating pill nav bar: Home | gold FAB (AI assist) | Settings
class _BottomNav extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              width: 266,
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0x08FFFFFF), // rgba(255,255,255,0.03)
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: const Color(0x17FFFFFF), // rgba(255,255,255,0.09)
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _NavTab(
                    icon: Icons.home_outlined,
                    label: 'Home',
                    active: selected == 0,
                    onTap: () => onTap(0),
                  ),
                  _FabButton(onTap: () => onTap(1)),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.instrumentSans(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: color,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Flat gold circular FAB with a two-sparkle icon (mingcute:ai-fill style)
class _FabButton extends StatelessWidget {
  final VoidCallback onTap;

  const _FabButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFFC9A86E),
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CustomPaint(
              painter: _SparklePainter(color: Color(0xD9050505)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws two 4-point "diamond" sparkle stars: one large centered,
/// one small offset top-right, matching mingcute:ai-fill.
class _SparklePainter extends CustomPainter {
  final Color color;
  const _SparklePainter({required this.color});

  /// Draws a smooth 4-point curved diamond sparkle (super-ellipse curve style)
  Path _sparklePath(Offset center, double outerRadius) {
    final path = Path();
    final top = Offset(center.dx, center.dy - outerRadius);
    final right = Offset(center.dx + outerRadius, center.dy);
    final bottom = Offset(center.dx, center.dy + outerRadius);
    final left = Offset(center.dx - outerRadius, center.dy);

    // Control point distance from center (0.28x radius gives the exact rounded diamond waist in Mingcute AI icon)
    final ctrlDist = outerRadius * 0.19;

    path.moveTo(top.dx, top.dy);
    path.cubicTo(
      center.dx + ctrlDist,
      center.dy - ctrlDist * 2.2,
      center.dx + ctrlDist * 2.2,
      center.dy - ctrlDist,
      right.dx,
      right.dy,
    );
    path.cubicTo(
      center.dx + ctrlDist * 2.2,
      center.dy + ctrlDist,
      center.dx + ctrlDist,
      center.dy + ctrlDist * 2.2,
      bottom.dx,
      bottom.dy,
    );
    path.cubicTo(
      center.dx - ctrlDist,
      center.dy + ctrlDist * 2.2,
      center.dx - ctrlDist * 2.2,
      center.dy + ctrlDist,
      left.dx,
      left.dy,
    );
    path.cubicTo(
      center.dx - ctrlDist * 2.2,
      center.dy - ctrlDist,
      center.dx - ctrlDist,
      center.dy - ctrlDist * 2.2,
      top.dx,
      top.dy,
    );
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Main diamond sparkle (centered)
    final mainCenter = Offset(size.width * 0.44, size.height * 0.54);
    canvas.drawPath(_sparklePath(mainCenter, size.width * 0.38), paint);

    // Top-right accent diamond sparkle
    final smallCenter = Offset(size.width * 0.77, size.height * 0.22);
    canvas.drawPath(_sparklePath(smallCenter, size.width * 0.15), paint);
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) =>
      oldDelegate.color != color;
}
