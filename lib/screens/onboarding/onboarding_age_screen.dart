import 'package:flutter/material.dart';
import '../../models/onboarding_data.dart';
import 'onboarding_shell.dart';
import 'onboarding_gender_screen.dart';

class OnboardingAgeScreen extends StatefulWidget {
  final OnboardingData data;
  const OnboardingAgeScreen({super.key, required this.data});

  @override
  State<OnboardingAgeScreen> createState() => _OnboardingAgeScreenState();
}

class _OnboardingAgeScreenState extends State<OnboardingAgeScreen> {
  late int _age;
  late FixedExtentScrollController _ctrl;

  @override
  void initState() {
    super.initState();
    _age = widget.data.age;
    _ctrl = FixedExtentScrollController(initialItem: _age - 1);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingShell(
      step: 2,
      totalSteps: 6,
      data: widget.data,
      onContinue: () {
        widget.data.age = _age;
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => OnboardingGenderScreen(data: widget.data)),
        );
      },
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            onboardingHeader(
              'STEP 2 OF 6',
              'How ',
              'old',
              ' are you?',
              'Helps personalise heart-rate zones and sleep targets.',
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 140,
                    child: ListWheelScrollView.useDelegate(
                      controller: _ctrl,
                      itemExtent: 60,
                      physics: const FixedExtentScrollPhysics(),
                      perspective: 0.004,
                      onSelectedItemChanged: (i) {
                        setState(() => _age = i + 1);
                      },
                      childDelegate: ListWheelChildBuilderDelegate(
                        childCount: 100,
                        builder: (ctx, i) {
                          final age = i + 1;
                          final selected = age == _age;
                          return Center(
                            child: Text(
                              '$age',
                              style: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.2),
                                fontSize: selected ? 52 : 28,
                                fontWeight: selected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('YEARS',
                      style: TextStyle(
                          color: Colors.white38,
                          fontSize: 14,
                          letterSpacing: 2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
