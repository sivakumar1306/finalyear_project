import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/supabase_service.dart';
import 'sign_up_screen.dart';
import 'login_screen.dart';
import '../../theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _checking = true;

  StreamSubscription? _restoreSub;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _restoreSub?.cancel();
    super.dispose();
  }

  /// Route from the local login flag or an already-restored session. Profile
  /// lookup happens on Home, so a cold start does not wait on the network.
  Future<void> _open() async {
    var flagged = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      flagged = prefs.getBool('user_logged_in') ?? false;
    } catch (_) {}
    if (!mounted) return;
    var hasUser = false;
    try {
      hasUser = SupabaseService.currentUser != null;
    } catch (_) {}
    if (flagged || hasUser) {
      Navigator.pushReplacementNamed(context, '/home');
      return;
    }
    setState(() => _checking = false);
    try {
      _restoreSub = SupabaseService.client.auth.onAuthStateChange.listen((state) {
        if (!mounted || state.session?.user == null) return;
        _restoreSub?.cancel();
        _restoreSub = null;
        Navigator.pushReplacementNamed(context, '/home');
      });
    } catch (_) {}
  }

  Widget _buildLogo() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'VITAL',
          style: TextStyle(
            color: Color(0xFFC7A56A),
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: 5.5,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'MONITORING',
          style: TextStyle(
            color: Color(0xFFC7A56A),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 4.0,
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
                    child: _buildLogo(),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const Spacer(),
                        Center(
                          child: _buildLogo(),
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
