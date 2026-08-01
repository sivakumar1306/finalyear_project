import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../../models/onboarding_data.dart';
import '../onboarding/onboarding_name_screen.dart';
import 'sign_up_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _minSplashDuration = Duration(milliseconds: 350);

  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  /// Keeps the splash visible for at least a short beat so it doesn't flash,
  /// while the profile fetch (the real work) runs concurrently.
  Future<void> _holdSplash(DateTime started) async {
    final elapsed = DateTime.now().difference(started);
    if (elapsed < _minSplashDuration) {
      await Future.delayed(_minSplashDuration - elapsed);
    }
  }

  Future<void> _checkSession() async {
    final started = DateTime.now();
    final user = SupabaseService.currentUser;
    if (user != null) {
      await _routeLoggedInUser(user, started);
    } else {
      await _holdSplash(started);
      if (!mounted) return;
      setState(() => _checking = false);
    }
  }

  Future<void> _routeLoggedInUser(User user, DateTime started) async {
    try {
      final profile = await SupabaseService.getProfile(
        user.id,
      ).timeout(const Duration(seconds: 8));
      await _holdSplash(started);
      if (!mounted) return;
      final hasProfile =
          profile != null && (profile['full_name'] as String? ?? '').isNotEmpty;
      if (hasProfile) {
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => OnboardingNameScreen(data: OnboardingData()),
          ),
        );
      }
    } catch (_) {
      await _holdSplash(started);
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _checking
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('sundr_logo.png', width: 56, height: 56),
                  const SizedBox(height: 20),
                  const Text(
                    'SUNDR',
                    style: TextStyle(
                      color: Color(0xFFC7A56A),
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 6,
                    ),
                  ),
                ],
              ),
            )
          : SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  Image.asset('ring.png', height: 200),
                  const SizedBox(height: 28),
                  const Text(
                    'SUNDR',
                    style: TextStyle(
                      color: Color(0xFFC7A56A),
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 6,
                    ),
                  ),
                  const Spacer(flex: 3),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Column(
                      children: [
                        _GlassButton(
                          label: 'Get Started',
                          textColor: const Color(0xFFC9A86E),
                          fillColor: const Color(0xFFC9A86E),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SignUpScreen(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _GlassButton(
                          label: 'Skip',
                          textColor: Colors.white,
                          fillColor: Colors.white,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

/// Translucent "glass" pill button: subtle tinted fill, faint border,
/// and a background blur — matches the frosted look in the design file.
class _GlassButton extends StatelessWidget {
  final String label;
  final Color textColor;
  final Color fillColor;
  final VoidCallback onTap;

  const _GlassButton({
    required this.label,
    required this.textColor,
    required this.fillColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Container(
              width: double.infinity,
              height: 45,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fillColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: fillColor.withValues(alpha: 0.15),
                  width: 0.5,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
