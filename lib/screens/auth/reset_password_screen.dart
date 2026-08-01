import 'package:flutter/material.dart';

import '../../services/supabase_service.dart';
import '../../widgets/glass_back_button.dart';
import 'auth_background.dart';
import 'login_screen.dart';

/// Step 3 of the password-recovery flow — set the new password. Requires the
/// session established by the verified recovery code.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _confirmObscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    final pass = _passCtrl.text;
    final confirm = _confirmCtrl.text;
    if (pass.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (pass != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SupabaseService.updatePassword(pass);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
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
                children: const [
                  GlassBackButton(),
                  SizedBox(width: 36),
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
                      'Set New Password',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        letterSpacing: -0.38,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose a new password for your account',
                      style: TextStyle(
                        color: Color(0x85FFFFFF),
                        fontSize: 12.5,
                        letterSpacing: 0.25,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    AuthGlassField(
                      controller: _passCtrl,
                      label: 'NEW PASSWORD',
                      hint: '••••••••••••',
                      obscure: _obscure,
                      onChanged: (_) => setState(() => _error = null),
                      suffix: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          color: Colors.white38,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    const SizedBox(height: 24),
                    AuthGlassField(
                      controller: _confirmCtrl,
                      label: 'CONFIRM PASSWORD',
                      hint: '••••••••••••',
                      obscure: _confirmObscure,
                      onChanged: (_) => setState(() => _error = null),
                      suffix: IconButton(
                        icon: Icon(
                          _confirmObscure
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.white38,
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _confirmObscure = !_confirmObscure),
                      ),
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
                label: 'Reset Password',
                loading: _loading,
                onPressed: _reset,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
