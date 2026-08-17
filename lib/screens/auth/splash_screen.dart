import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../../models/onboarding_data.dart';
import '../onboarding/onboarding_name_screen.dart';
import 'sign_up_screen.dart';
import 'login_screen.dart';
import '../../theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _minSplashDuration = Duration(milliseconds: 600);

  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

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

  Widget _buildLogo({double iconSize = 34, double fontSize = 28}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset(
          'sundr_logo.png',
          width: iconSize,
          height: iconSize,
          color: const Color(0xFFC7A56A),
          errorBuilder: (context, error, stackTrace) => SizedBox(
            width: iconSize,
            height: iconSize,
            child: CustomPaint(
              painter: const _SundrStarburstPainter(color: Color(0xFFC7A56A)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          'SUNDR',
          style: TextStyle(
            color: Color(0xFFC7A56A),
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: 5.5,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
            child: _checking
                ? Center(
                    child: _buildLogo(iconSize: 34, fontSize: 28),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const Spacer(),
                        Center(
                          child: _buildLogo(iconSize: 34, fontSize: 28),
                        ),
                        const Spacer(),
                        _GlassButton(
                          label: 'Get Started',
                          textColor: const Color(0xFFC7A56A),
                          fillColor: const Color(0xFFC7A56A),
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
                        const SizedBox(height: 28),
                      ],
                    ),
                  ),
          ),
    );
  }
}

class _SundrStarburstPainter extends CustomPainter {
  final Color color;
  const _SundrStarburstPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.075
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    for (int i = 0; i < 4; i++) {
      final angle = (i * 90) * (pi / 180);
      final dx = cos(angle);
      final dy = sin(angle);

      canvas.drawLine(
        center,
        Offset(center.dx + dx * r * 0.95, center.dy + dy * r * 0.95),
        paint,
      );

      final tip = Offset(center.dx + dx * r * 0.95, center.dy + dy * r * 0.95);
      final wing1 = angle + 135 * (pi / 180);
      final wing2 = angle - 135 * (pi / 180);
      final wingLen = r * 0.38;

      canvas.drawLine(
        tip,
        Offset(tip.dx + cos(wing1) * wingLen, tip.dy + sin(wing1) * wingLen),
        paint,
      );
      canvas.drawLine(
        tip,
        Offset(tip.dx + cos(wing2) * wingLen, tip.dy + sin(wing2) * wingLen),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

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
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fillColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: fillColor.withValues(alpha: 0.20),
                  width: 0.8,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
