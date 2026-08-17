import 'package:flutter/material.dart';
import '../../models/onboarding_data.dart';
import '../../services/unit_prefs.dart';
import 'onboarding_shell.dart';
import 'onboarding_emergency_contact_screen.dart';
import '../../theme/app_theme.dart';

class OnboardingWeightScreen extends StatefulWidget {
  final OnboardingData data;
  const OnboardingWeightScreen({super.key, required this.data});

  @override
  State<OnboardingWeightScreen> createState() => _OnboardingWeightScreenState();
}

class _OnboardingWeightScreenState extends State<OnboardingWeightScreen> {
  late double _weight;
  bool _useLbs = false;
  FixedExtentScrollController? _ctrl;

  @override
  void initState() {
    super.initState();
    _weight = widget.data.weightKg;
    _initController();
    UnitPrefs.loadSystem().then((system) {
      if (mounted && system == UnitSystem.us && !_useLbs) {
        final oldCtrl = _ctrl;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          oldCtrl?.dispose();
        });
        setState(() {
          _useLbs = true;
          _initController();
        });
      }
    });
  }

  void _initController() {
    final initialItem = _useLbs
        ? UnitPrefs.kgToLbs(_weight).round() - 44
        : _weight.round() - 20;
    _ctrl = FixedExtentScrollController(initialItem: initialItem);
  }

  void _setUnit(bool useLbs) {
    if (useLbs == _useLbs) return;
    
    final oldCtrl = _ctrl;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldCtrl?.dispose();
    });

    setState(() {
      _useLbs = useLbs;
      _initController();
    });
    UnitPrefs.saveSystem(useLbs ? UnitSystem.us : UnitSystem.metric);
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
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
            const SizedBox(height: 24),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 140,
                    child: _ctrl == null ? const SizedBox() : ListWheelScrollView.useDelegate(
                      key: ValueKey(_useLbs),
                      controller: _ctrl,
                      itemExtent: 60,
                      physics: const FixedExtentScrollPhysics(),
                      perspective: 0.004,
                      onSelectedItemChanged: (i) {
                        setState(() {
                          _weight = _useLbs
                              ? UnitPrefs.lbsToKg((44 + i).toDouble())
                              : (20 + i).toDouble();
                        });
                      },
                      childDelegate: ListWheelChildBuilderDelegate(
                        childCount: _useLbs ? (551 - 44 + 1) : (250 - 20 + 1),
                        builder: (ctx, i) {
                          final currentVal = _useLbs ? 44 + i : 20 + i;
                          final selected = _useLbs 
                              ? currentVal == UnitPrefs.kgToLbs(_weight).round()
                              : currentVal == _weight.round();
                              
                          return Center(
                            child: Text(
                              '$currentVal',
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
                  _UnitToggle(useLbs: _useLbs, onChanged: _setUnit),
                ],
              ),
            ),
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
            color: active ? AppTheme.surfaceWarm : Colors.white54,
            fontSize: 14,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
