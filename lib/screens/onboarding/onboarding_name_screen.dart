import 'package:flutter/material.dart';
import '../../models/onboarding_data.dart';
import 'onboarding_shell.dart';
import 'onboarding_age_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    return OnboardingShell(
      step: 1,
      totalSteps: 5,
      data: widget.data,
      canContinue: true,
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
              'STEP 1 OF 5',
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
    );
  }
}
