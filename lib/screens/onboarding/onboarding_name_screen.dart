import 'package:flutter/material.dart';
import '../../models/onboarding_data.dart';
import '../../services/incident_service.dart';
import '../../services/supabase_service.dart';
import '../auth/splash_screen.dart';
import 'onboarding_age_screen.dart';
import 'onboarding_shell.dart';

class OnboardingNameScreen extends StatefulWidget {
  final OnboardingData data;
  const OnboardingNameScreen({super.key, required this.data});

  @override
  State<OnboardingNameScreen> createState() => _OnboardingNameScreenState();
}

class _OnboardingNameScreenState extends State<OnboardingNameScreen> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.data.name);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _goBackToSplash() async {
    try {
      await SupabaseService.signOut();
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'onboarding_name_screen',
        error: e,
        stackTrace: st,
        customMessage: '_goBackToSplash signOut failed',
      );
    }
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const SplashScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.data.isEditMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goBackToSplash();
      },
      child: OnboardingShell(
        step: 1,
        totalSteps: 6,
        data: widget.data,
        canContinue: true,
        onBack: widget.data.isEditMode ? () => Navigator.pop(context) : _goBackToSplash,
        onContinue: () {
        widget.data.name = _ctrl.text.trim();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OnboardingAgeScreen(data: widget.data),
          ),
        );
      },
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            onboardingHeader(
              'STEP 1 OF 6',
              'What should we ',
              'call you?',
              '',
              'A first name is fine. This is how we will greet you.',
            ),
            const Spacer(),
            TextField(
              controller: _ctrl,
              onChanged: (_) => setState(() {}),
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w600,
              ),
              decoration: const InputDecoration(
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: kGold),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: kGold, width: 2),
                ),
                hintText: 'Your name',
                hintStyle: TextStyle(color: Colors.white24, fontSize: 28),
              ),
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    ),
  );
}
}
