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

  void _setUnit(bool useInches) {
    if (useInches == _useInches) return;
    setState(() => _useInches = useInches);
    UnitPrefs.saveSystem(useInches ? UnitSystem.us : UnitSystem.metric);
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingShell(
      step: 4,
      totalSteps: 6,
      data: widget.data,
      onContinue: () {
        widget.data.heightCm = _height;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OnboardingWeightScreen(data: widget.data),
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
              'STEP 4 OF 6',
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
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _UnitToggle(useInches: _useInches, onChanged: _setUnit),
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
                onChanged: (v) => setState(
                  () => _height = _useInches
                      ? UnitPrefs.inchesToCm(v).round()
                      : v.round(),
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

/// Two-way segmented toggle (cm / ft), matching the Figma pill spec:
/// outer track W72 H33, radius 100, padding 2, gap 3, fill white@4%,
/// stroke white@6% (0.5 inside). Active segment gets a solid gold pill.
class _UnitToggle extends StatelessWidget {
  final bool useInches;
  final ValueChanged<bool> onChanged;

  const _UnitToggle({required this.useInches, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 33,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Segment(
            label: 'cm',
            active: !useInches,
            onTap: () => onChanged(false),
          ),
          const SizedBox(width: 3),
          _Segment(
            label: 'ft',
            active: useInches,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: active ? kGold : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? const Color(0xFF16130E) : Colors.white54,
            fontSize: 14,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
