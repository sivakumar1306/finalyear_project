import 'package:flutter/material.dart';
import '../onboarding/pair_ring_screen.dart';
import '../../models/onboarding_data.dart';

const kGold = Color(0xFFF0A030);
const kBg = Colors.black;

class OnboardingShell extends StatelessWidget {
  final int step;
  final int totalSteps;
  final OnboardingData data;
  final Widget body;
  final String buttonLabel;
  final VoidCallback onContinue;
  final bool canContinue;

  const OnboardingShell({
    super.key,
    required this.step,
    required this.totalSteps,
    required this.data,
    required this.body,
    required this.onContinue,
    this.buttonLabel = 'Continue',
    this.canContinue = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Center(child: _StepDots(current: step, total: totalSteps)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                          builder: (_) => PairRingScreen(data: data)),
                      (_) => false,
                    ),
                    child: const Text('SKIP',
                        style: TextStyle(color: Colors.white54, fontSize: 13, letterSpacing: 1)),
                  ),
                ],
              ),
            ),
            Expanded(child: body),
            // Continue button
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: canContinue ? onContinue : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kGold,
                    disabledBackgroundColor: kGold.withValues(alpha: 0.4),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                    elevation: 0,
                  ),
                  child: Text(buttonLabel,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  final int current;
  final int total;

  const _StepDots({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (i) {
        final active = i + 1 == current;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 20 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active ? kGold : Colors.white24,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}

Widget onboardingHeader(String stepLabel, String titleStart, String titleHighlight, String titleEnd, String subtitle) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(stepLabel,
          style: const TextStyle(
              color: Colors.white38, fontSize: 12, letterSpacing: 1.5)),
      const SizedBox(height: 10),
      RichText(
        text: TextSpan(
          style: const TextStyle(
              color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
          children: [
            if (titleStart.isNotEmpty) TextSpan(text: titleStart),
            TextSpan(
                text: titleHighlight,
                style: const TextStyle(color: kGold)),
            if (titleEnd.isNotEmpty) TextSpan(text: titleEnd),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Text(subtitle,
          style: const TextStyle(color: Colors.white38, fontSize: 13)),
    ],
  );
}
