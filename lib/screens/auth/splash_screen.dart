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
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    final user = SupabaseService.currentUser;
    if (user != null) {
      await _routeLoggedInUser(user);
    } else {
      setState(() => _checking = false);
    }
  }

  Future<void> _routeLoggedInUser(User user) async {
    try {
      final profile = await SupabaseService.getProfile(user.id);
      if (!mounted) return;
      final hasProfile = profile != null &&
          (profile['full_name'] as String? ?? '').isNotEmpty;
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
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _checking
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFF0A030)))
          : SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  Image.asset('ring.png', height: 200),
                  const SizedBox(height: 28),
                  const Text(
                    'SUNDR',
                    style: TextStyle(
                      color: Color(0xFFF0A030),
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 6,
                    ),
                  ),
                  const Spacer(flex: 3),
                  _GoldButton(
                    label: 'Get Started',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SignUpScreen()),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    ),
                    child: const Text(
                      'Skip',
                      style: TextStyle(color: Colors.white70, fontSize: 15),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class _GoldButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool outlined;

  const _GoldButton({
    required this.label,
    required this.onTap,
  }) : outlined = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: outlined
            ? OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white38),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 15)),
              )
            : ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF0A030),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  elevation: 0,
                ),
                child: Text(label,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
      ),
    );
  }
}
