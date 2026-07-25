import 'package:flutter/material.dart';
import '../../models/onboarding_data.dart';
import '../../services/unit_prefs.dart';
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
  // Canonical value, always kg — matches widget.data.weightKg / the DB
  // column. _useLbs only changes what's displayed/entered here.
  late double _weight;
  bool _useLbs = false;

  @override
  void initState() {
    super.initState();
    _weight = widget.data.weightKg;
    UnitPrefs.loadSystem().then((system) {
      if (mounted) setState(() => _useLbs = system == UnitSystem.us);
    });
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
                    (_useLbs ? UnitPrefs.kgToLbs(_weight) : _weight)
                        .toStringAsFixed(0),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 72,
                        fontWeight: FontWeight.w300),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () {
                      final next = !_useLbs;
                      setState(() => _useLbs = next);
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
                      child: Text(_useLbs ? 'lbs' : 'kg',
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
                key: ValueKey(_useLbs),
                value: _useLbs ? UnitPrefs.kgToLbs(_weight) : _weight,
                min: _useLbs ? UnitPrefs.kgToLbs(20) : 20,
                max: _useLbs ? UnitPrefs.kgToLbs(250) : 250,
                isInteger: false,
                onChanged: (v) => setState(
                    () => _weight = _useLbs ? UnitPrefs.lbsToKg(v) : v),
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
