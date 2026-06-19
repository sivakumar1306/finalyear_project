import 'package:flutter/material.dart';
import '../../models/onboarding_data.dart';
import 'onboarding_shell.dart';
import 'onboarding_height_screen.dart';

class OnboardingGenderScreen extends StatefulWidget {
  final OnboardingData data;
  const OnboardingGenderScreen({super.key, required this.data});

  @override
  State<OnboardingGenderScreen> createState() => _OnboardingGenderScreenState();
}

class _OnboardingGenderScreenState extends State<OnboardingGenderScreen> {
  String _selected = '';

  @override
  void initState() {
    super.initState();
    _selected = widget.data.gender;
  }

  final _options = const ['Male', 'Female', 'Non-binary', 'Prefer not to say'];

  @override
  Widget build(BuildContext context) {
    return OnboardingShell(
      step: 3,
      totalSteps: 5,
      data: widget.data,
      canContinue: _selected.isNotEmpty,
      onContinue: () {
        widget.data.gender = _selected;
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => OnboardingHeightScreen(data: widget.data)),
        );
      },
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            onboardingHeader(
              'STEP 3 OF 5',
              'Tell us your ',
              'gender?',
              '',
              'Affects how some of your health metrics are interpreted.',
            ),
            const SizedBox(height: 32),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: _options.map((opt) {
                final active = opt == _selected;
                return GestureDetector(
                  onTap: () => setState(() => _selected = opt),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFF2A2000)
                          : const Color(0xFF181818),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: active ? kGold : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: active ? kGold : Colors.white12,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          opt,
                          style: TextStyle(
                            color: active ? Colors.white : Colors.white70,
                            fontSize: 14,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
