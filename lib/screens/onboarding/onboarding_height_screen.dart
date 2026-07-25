import 'package:flutter/material.dart';
import '../../models/onboarding_data.dart';
import '../../services/unit_prefs.dart';
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
  // Canonical value, always cm — matches widget.data.heightCm / the DB
  // column. _useInches only changes what's displayed/entered here.
  late int _height;
  bool _useInches = false;

  @override
  void initState() {
    super.initState();
    _height = widget.data.heightCm;
    UnitPrefs.loadSystem().then((system) {
      if (mounted) setState(() => _useInches = system == UnitSystem.us);
    });
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
                    _useInches
                        ? UnitPrefs.formatHeightCm(_height, UnitSystem.us)
                        : '$_height',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: _useInches ? 56 : 72,
                        fontWeight: FontWeight.w300),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () {
                      final next = !_useInches;
                      setState(() => _useInches = next);
                      UnitPrefs.saveSystem(
                          next ? UnitSystem.us : UnitSystem.metric);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: kGold,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(_useInches ? 'ft/in' : 'cm',
                          style: const TextStyle(
                              color: Colors.black,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: RulerPicker(
                key: ValueKey(_useInches),
                value: _useInches
                    ? UnitPrefs.cmToInches(_height.toDouble())
                    : _height.toDouble(),
                min: _useInches ? UnitPrefs.cmToInches(100) : 100,
                max: _useInches ? UnitPrefs.cmToInches(250) : 250,
                onChanged: (v) => setState(() => _height = _useInches
                    ? UnitPrefs.inchesToCm(v).round()
                    : v.round()),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
