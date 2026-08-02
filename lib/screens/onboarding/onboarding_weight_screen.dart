import 'package:flutter/material.dart';
import '../../models/onboarding_data.dart';
import '../../services/unit_prefs.dart';
import '../../widgets/ruler_picker.dart';
import 'onboarding_shell.dart';
import 'onboarding_emergency_contact_screen.dart';

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

  void _setUnit(bool useLbs) {
    if (useLbs == _useLbs) return;
    setState(() => _useLbs = useLbs);
    UnitPrefs.saveSystem(useLbs ? UnitSystem.us : UnitSystem.metric);
  }

  Future<void> _editWeight() async {
    // Editing is always done in the unit currently on screen, then
    // converted back to the canonical kg value.
    final controller = TextEditingController(
      text: (_useLbs ? UnitPrefs.kgToLbs(_weight) : _weight).toStringAsFixed(0),
    );
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter weight (${_useLbs ? 'lbs' : 'kg'})',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w300,
                ),
                decoration: const InputDecoration(
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: kGold, width: 2),
                  ),
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, controller.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kGold,
                    foregroundColor: const Color(0xFF16130E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (result == null) return;
    final entered = double.tryParse(result.trim());
    if (entered == null) return;

    setState(() {
      if (_useLbs) {
        final clampedLbs = entered.clamp(
          UnitPrefs.kgToLbs(20),
          UnitPrefs.kgToLbs(250),
        );
        _weight = UnitPrefs.lbsToKg(clampedLbs);
      } else {
        _weight = entered.clamp(20, 250);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingShell(
      step: 5,
      totalSteps: 6,
      data: widget.data,
      buttonLabel: 'Continue',
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
              'STEP 5 OF 6',
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
                  GestureDetector(
                    onTap: _editWeight,
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      (_useLbs ? UnitPrefs.kgToLbs(_weight) : _weight)
                          .toStringAsFixed(0),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 72,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _UnitToggle(useLbs: _useLbs, onChanged: _setUnit),
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
                  () => _weight = _useLbs ? UnitPrefs.lbsToKg(v) : v,
                ),
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
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OnboardingEmergencyContactScreen(data: widget.data)),
    );
  }
}

/// Two-way segmented toggle (kg / lbs), matching the Figma pill spec:
/// outer track hug W, H33, radius 100, padding 2, gap 3, fill white@4%,
/// stroke white@6% (0.5 inside). Active segment gets a solid gold pill.
class _UnitToggle extends StatelessWidget {
  final bool useLbs;
  final ValueChanged<bool> onChanged;

  const _UnitToggle({required this.useLbs, required this.onChanged});

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
          _Segment(label: 'kg', active: !useLbs, onTap: () => onChanged(false)),
          const SizedBox(width: 3),
          _Segment(label: 'lbs', active: useLbs, onTap: () => onChanged(true)),
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
