import 'package:flutter/material.dart';
import '../../models/onboarding_data.dart';
import '../../widgets/ruler_picker.dart';
import 'onboarding_shell.dart';
import 'pair_ring_screen.dart';

class OnboardingWeightScreen extends StatefulWidget {
  final OnboardingData data;
  const OnboardingWeightScreen({super.key, required this.data});

  @override
  State<OnboardingWeightScreen> createState() => _OnboardingWeightScreenState();
}

class _OnboardingWeightScreenState extends State<OnboardingWeightScreen> {
  late double _weight;

  @override
  void initState() {
    super.initState();
    _weight = widget.data.weightKg;
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingShell(
      step: 5,
      totalSteps: 5,
      data: widget.data,
      buttonLabel: 'Finish',
      onContinue: () {
        widget.data.weightKg = _weight;
        _saveAndNext();
      },
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            onboardingHeader(
              'STEP 5 OF 5',
              'And your ',
              'weight?',
              '',
              'Used for body composition and effort estimates.',
            ),
            const Spacer(),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    _weight.toStringAsFixed(0),
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
                    child: const Text('kg',
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
                value: _weight,
                min: 20,
                max: 250,
                isInteger: false,
                onChanged: (v) => setState(() => _weight = v),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAndNext() async {
    widget.data.weightKg = _weight;
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => PairRingScreen(data: widget.data)),
      (_) => false,
    );
  }
}
