import 'package:flutter/material.dart';
import '../../models/onboarding_data.dart';
import '../../services/unit_prefs.dart';
import 'onboarding_shell.dart';
import 'onboarding_weight_screen.dart';
import '../../theme/app_theme.dart';

class OnboardingHeightScreen extends StatefulWidget {
  final OnboardingData data;
  const OnboardingHeightScreen({super.key, required this.data});

  @override
  State<OnboardingHeightScreen> createState() => _OnboardingHeightScreenState();
}

class _OnboardingHeightScreenState extends State<OnboardingHeightScreen> {
  late int _height;
  bool _useInches = false;
  FixedExtentScrollController? _ctrl;

  @override
  void initState() {
    super.initState();
    _height = widget.data.heightCm;
    _initController();
    UnitPrefs.loadSystem().then((system) {
      if (mounted && system == UnitSystem.us && !_useInches) {
        final oldCtrl = _ctrl;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          oldCtrl?.dispose();
        });
        setState(() {
          _useInches = true;
          _initController();
        });
      }
    });
  }

  void _initController() {
    final initialItem = _useInches
        ? UnitPrefs.cmToInches(_height.toDouble()).round() - 39
        : _height - 100;
    _ctrl = FixedExtentScrollController(initialItem: initialItem);
  }

  void _setUnit(bool useInches) {
    if (useInches == _useInches) return;
    
    final oldCtrl = _ctrl;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldCtrl?.dispose();
    });

    setState(() {
      _useInches = useInches;
      _initController();
    });
    UnitPrefs.saveSystem(useInches ? UnitSystem.us : UnitSystem.metric);
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
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
            const SizedBox(height: 24),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 160,
                    child: _ctrl == null ? const SizedBox() : ListWheelScrollView.useDelegate(
                      key: ValueKey(_useInches),
                      controller: _ctrl,
                      itemExtent: 60,
                      physics: const FixedExtentScrollPhysics(),
                      perspective: 0.004,
                      onSelectedItemChanged: (i) {
                        setState(() {
                          _height = _useInches
                              ? UnitPrefs.inchesToCm((39 + i).toDouble()).round()
                              : 100 + i;
                        });
                      },
                      childDelegate: ListWheelChildBuilderDelegate(
                        childCount: _useInches ? (98 - 39 + 1) : (250 - 100 + 1),
                        builder: (ctx, i) {
                          final currentVal = _useInches ? 39 + i : 100 + i;
                          final selected = _useInches 
                              ? currentVal == UnitPrefs.cmToInches(_height.toDouble()).round()
                              : currentVal == _height;
                              
                          final text = _useInches 
                              ? UnitPrefs.formatHeightCm(UnitPrefs.inchesToCm(currentVal.toDouble()), UnitSystem.us)
                              : '$currentVal';

                          return Center(
                            child: Text(
                              text,
                              style: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.2),
                                fontSize: selected ? (_useInches ? 48 : 52) : 28,
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
                  _UnitToggle(useInches: _useInches, onChanged: _setUnit),
                ],
              ),
            ),
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
            color: active ? AppTheme.surfaceWarm : Colors.white54,
            fontSize: 14,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
