import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/main_tab_provider.dart';
import '../providers/workout_provider.dart';
import 'home/home_screen.dart';
import 'settings/profile_edit_screen.dart';
import 'workouts/active_workout_screen.dart';
import 'assist/chat_screen.dart';
import '../widgets/app_typography.dart';


// ── Apple-style transitions ───────────────────────────────────────────────────
//
// Home ↔ Profile: horizontal slide with easeOutCubic (iOS tab-like).
// AI Assist: fade + slight lift/scale present (iOS fullScreenCover feel).

const _kTabAnimDuration = Duration(milliseconds: 380);
const _kTabAnimCurve = Curves.easeOutCubic;

/// Shared route used by the bottom-nav FAB and Settings → AI Analysis.
/// iOS fullScreenCover-style: fade + slight lift + scale spring-in.
Route<void> buildAiAssistRoute({String? initialPrompt}) {
  return PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 340),
    opaque: true,
    pageBuilder: (context, animation, secondaryAnimation) {
      return ChatScreen(initialPrompt: initialPrompt);
    },
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late final PageController _pageController;
  MainTabProvider? _tabProvider;
  bool _animatingFromTap = false;

  static int _pageForTab(int tab) => tab == 2 ? 1 : 0;
  static int _tabForPage(int page) => page == 1 ? 2 : 0;

  @override
  void initState() {
    super.initState();
    final initialTab = context.read<MainTabProvider>().tab;
    _pageController = PageController(initialPage: _pageForTab(initialTab));

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<MainTabProvider>();
    if (!identical(_tabProvider, provider)) {
      _tabProvider?.removeListener(_onTabProviderChanged);
      _tabProvider = provider;
      _tabProvider!.addListener(_onTabProviderChanged);
    }
  }

  @override
  void dispose() {
    _tabProvider?.removeListener(_onTabProviderChanged);
    _pageController.dispose();
    super.dispose();
  }

  /// Syncs PageView when something outside the shell changes the tab
  /// (e.g. profile edit → Profile).
  void _onTabProviderChanged() {
    if (!mounted || !_pageController.hasClients || _animatingFromTap) return;
    final target = _pageForTab(_tabProvider!.tab);
    final current = _pageController.page?.round() ?? _pageController.initialPage;
    if (current == target) return;
    _pageController.animateToPage(
      target,
      duration: _kTabAnimDuration,
      curve: _kTabAnimCurve,
    );
  }

  void _onTabTap(int index) {
    final workout = context.read<WorkoutProvider>();
    if (workout.isWorkoutActive) {
      _showWorkoutLockSheet();
      return;
    }
    final targetPage = _pageForTab(index);
    final currentPage =
        _pageController.hasClients
            ? (_pageController.page?.round() ?? 0)
            : 0;
    if (currentPage == targetPage &&
        context.read<MainTabProvider>().tab == index) {
      return;
    }

    HapticFeedback.selectionClick();
    _animatingFromTap = true;
    context.read<MainTabProvider>().setTab(index);
    _pageController
        .animateToPage(
          targetPage,
          duration: _kTabAnimDuration,
          curve: _kTabAnimCurve,
        )
        .whenComplete(() {
          if (mounted) _animatingFromTap = false;
        });
  }

  // AI Assist is pushed as its own full-screen route so the bottom nav
  // disappears while chat is open and returns on pop.
  void _openAiAssist() {
    final workout = context.read<WorkoutProvider>();
    if (workout.isWorkoutActive) {
      _showWorkoutLockSheet();
      return;
    }
    HapticFeedback.lightImpact();
    Navigator.of(context).push(buildAiAssistRoute());
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
        extendBody: true,
        body: PageView(
          controller: _pageController,
          // Swipe disabled — tab switches are driven by the pill so motion
          // always matches the tapped destination (Apple tab-bar style).
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (page) {
            final nextTab = _tabForPage(page);
            if (context.read<MainTabProvider>().tab != nextTab) {
              context.read<MainTabProvider>().setTab(nextTab);
            }
          },
          children: [
            const _KeepAlivePage(child: HomeScreen()),
            _LazyKeepAlivePage(
              builder: (_) => const ProfileEditScreen(showBackButton: false),
            ),
          ],
        ),
        bottomNavigationBar: RepaintBoundary(
          child: _BottomNav(
            selected: tab,
            onTap: _onTabTap,
            onAssistTap: _openAiAssist,
          ),
        ),
      ),
    );
  }
}

/// Keeps each tab's state alive across animated page switches (IndexedStack
/// equivalent for a PageView).
class _KeepAlivePage extends StatefulWidget {
  final Widget child;
  const _KeepAlivePage({required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _LazyKeepAlivePage extends StatefulWidget {
  final WidgetBuilder builder;
  const _LazyKeepAlivePage({required this.builder});

  @override
  State<_LazyKeepAlivePage> createState() => _LazyKeepAlivePageState();
}

class _LazyKeepAlivePageState extends State<_LazyKeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  Widget? _child;

  @override
  bool get wantKeepAlive => _child != null;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_child == null) {
      _child = widget.builder(context);
      updateKeepAlive();
    }
    return _child!;
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
    // removes that fill so only the pill itself is visible.
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        top: false,
        // Lock text scaling for just the nav bar so layout stays stable
        // across accessibility font sizes.
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.0)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
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
                        color: AppTheme.glassButton,
                        border: Border.all(color: AppTheme.glassBorder),
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
                            icon: Icons.person_outline_rounded,
                            label: 'Profile',
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

class _NavTab extends StatefulWidget {
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
  State<_NavTab> createState() => _NavTabState();
}

class _NavTabState extends State<_NavTab> {
  static const _kGold = AppTheme.gold;
  static const _kInactive = Color(0x52FFFFFF);

  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? _kGold : _kInactive;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.active
                ? AppTheme.gridLine
                : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(
                  widget.icon,
                  key: ValueKey(widget.active),
                  color: color,
                  size: 18,
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                style: AppTypography.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: color,
                  height: 1.1,
                ),
                child: Text(widget.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavFab extends StatefulWidget {
  final VoidCallback onTap;

  const _NavFab({required this.onTap});

  @override
  State<_NavFab> createState() => _NavFabState();
}

class _NavFabState extends State<_NavFab> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              center: Alignment(0, 0),
              radius: 0.9,
              colors: [
                AppTheme.goldMuted,
                AppTheme.gold,
                AppTheme.goldDusk,
              ],
              stops: [0.0, 0.5, 1.0],
            ),
            boxShadow: _pressed
                ? []
                : [
                    BoxShadow(
                      color: AppTheme.gold.withValues(alpha: 0.35),
                      blurRadius: 12,
                      spreadRadius: 0,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: const Icon(
            Icons.auto_awesome,
            color: AppTheme.bgDim,
            size: 24,
          ),
        ),
      ),
    );
  }
}
