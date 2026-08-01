import 'package:flutter/material.dart';

import '../../services/supabase_service.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/glass_icon_button.dart';
import '../settings/faq_screen.dart';
import 'auth_background.dart';
import 'recovery_code_screen.dart';

/// Step 1 of the password-recovery flow — enter the registered email and
/// request a recovery code. Matches the Figma "Forgot Password" screen.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(email)) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SupabaseService.resetPassword(email);
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RecoveryCodeScreen(email: email),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e.toString().replaceAll('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthBackground(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const GlassBackButton(),
                  GlassIconButton(
                    icon: Icons.help_outline_rounded,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const FaqScreen()),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    const Text(
                      'Forgot Password?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        letterSpacing: -0.38,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'We will send a recovery code to your registered email address',
                      style: TextStyle(
                        color: Color(0x85FFFFFF),
                        fontSize: 12.5,
                        letterSpacing: 0.25,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 17),
                    AuthGlassField(
                      controller: _emailCtrl,
                      label: 'EMAIL ID',
                      hint: 'emailexample@email.com',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() => _error = null),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
              child: AuthGoldButton(
                label: 'Send Recovery Code',
                loading: _loading,
                onPressed: _sendCode,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
