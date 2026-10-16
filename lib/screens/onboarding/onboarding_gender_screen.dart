import 'package:flutter/material.dart';
import '../../models/onboarding_data.dart';
import 'onboarding_shell.dart';
import 'onboarding_height_screen.dart';
import '../../theme/app_theme.dart';

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
            builder: (_) => OnboardingHeightScreen(data: widget.data),
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
              'STEP 3 OF 6',
              'Tell us your ',
              'gender?',
              '',
              'Affects how some of your health metrics are interpreted.',
            ),
            const SizedBox(height: 32),
            // Male / Female — square icon cards
            Row(
              children: [
                Expanded(
                  child: _IconGenderCard(
                    label: 'Male',
                    icon: Icons.male_rounded,
                    active: _selected == 'Male',
                    onTap: () => setState(() => _selected = 'Male'),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: _IconGenderCard(
                    label: 'Female',
                    icon: Icons.female_rounded,
                    active: _selected == 'Female',
                    onTap: () => setState(() => _selected = 'Female'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // Non-binary / Prefer not to say — short pill rows
            Row(
              children: [
                Expanded(
                  child: _PillGenderCard(
                    label: 'Non-binary',
                    active: _selected == 'Non-binary',
                    onTap: () => setState(() => _selected = 'Non-binary'),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: _PillGenderCard(
                    label: 'Prefer not to say',
                    active: _selected == 'Prefer not to say',
                    onTap: () =>
                        setState(() => _selected = 'Prefer not to say'),
                  ),
                ),
              ],
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

/// Square-ish card used for Male / Female, with an icon avatar in the
/// top-left and the label anchored to the bottom-left.
class _IconGenderCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _IconGenderCard({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 155,
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
        decoration: BoxDecoration(
          color: active
              ? kGold.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? kGold.withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.08),
            width: active ? 1 : 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? kGold : Colors.white.withValues(alpha: 0.05),
              ),
              child: Icon(
                icon,
                size: 24,
                color: active
                    ? AppTheme.surfaceWarm
                    : Colors.white.withValues(alpha: 0.92),
              ),
            ),
            const Spacer(),
            Text(
              label,
              style: TextStyle(
                color: active ? kGold : Colors.white,
                fontSize: 14,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Short full-width pill row used for Non-binary / Prefer not to say.
class _PillGenderCard extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _PillGenderCard({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 51,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: active
              ? kGold.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? kGold.withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.08),
            width: active ? 1 : 0.5,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            color: active ? kGold : Colors.white,
            fontSize: 14,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
