import 'package:flutter/material.dart';
import '../../models/onboarding_data.dart';
import '../../widgets/ruler_picker.dart';
import 'onboarding_shell.dart';
import 'onboarding_weight_screen.dart';

class OnboardingHeightScreen extends StatefulWidget {
  final OnboardingData data;
  const OnboardingHeightScreen({super.key, required this.data});

  @override
  State<OnboardingHeightScreen> createState() => _OnboardingHeightScreenState();
}

class _OnboardingHeightScreenState extends State<OnboardingHeightScreen> {
  late int _height;

  @override
  void initState() {
    super.initState();
    _height = widget.data.heightCm;
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingShell(
      step: 4,
      totalSteps: 5,
      data: widget.data,
      onContinue: () {
        widget.data.heightCm = _height;
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => OnboardingWeightScreen(data: widget.data)),
        );
      },
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            onboardingHeader(
              'STEP 4 OF 5',
              'How ',
              'tall',
              ' are you?',
              'Affects how some of your health metrics are interpreted.',
            ),
            const Spacer(),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$_height',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 72,
                        fontWeight: FontWeight.w300),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: kGold,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('cm',
                        style: TextStyle(
                            color: Colors.black,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: RulerPicker(
                value: _height.toDouble(),
                min: 100,
                max: 250,
                onChanged: (v) => setState(() => _height = v.round()),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
