import 'dart:ui';

import 'package:flutter/material.dart';
import '../../services/goal_prefs.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_header.dart';
import '../../widgets/glass_icon_button.dart';
import '../../widgets/app_typography.dart';

/// Goal setting screen — Figma spec.
///
/// Shows the user's daily targets (steps, calories, distance, sleep window)
/// as tappable rows. Tapping a row opens an editor for that target.
///
/// Persistence: no Supabase table currently stores goal targets (checked
/// user_profiles / user_steps / user_sleep / etc. — none have target
/// columns), so this reads/writes through [GoalPrefs] (SharedPreferences).
/// Swap [GoalPrefs] for Supabase calls later without touching this UI.
class CardSettingsScreen extends StatefulWidget {
  const CardSettingsScreen({super.key});
  @override
  State<CardSettingsScreen> createState() => _CardSettingsScreenState();
}

class _CardSettingsScreenState extends State<CardSettingsScreen> {
  GoalTargets? _targets;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await GoalPrefs.load();
    if (mounted) setState(() => _targets = t);
  }

  Future<void> _persist(GoalTargets t) async {
    setState(() => _targets = t);
    await GoalPrefs.save(t);
  }

  // ── Editors ──────────────────────────────────────────────────────────────

  Future<void> _editSteps() async {
    final t = _targets!;
    final result = await _showNumberEditor(
      title: 'Steps',
      initial: t.steps,
      suffix: 'steps',
      step: 500,
      min: 1000,
      max: 50000,
    );
    if (result != null) _persist(t.copyWith(steps: result));
  }

  Future<void> _editCalories() async {
    final t = _targets!;
    final result = await _showNumberEditor(
      title: 'Calories',
      initial: t.calories,
      suffix: 'kcal',
      step: 50,
      min: 100,
      max: 5000,
    );
    if (result != null) _persist(t.copyWith(calories: result));
  }

  Future<void> _editDistance() async {
    final t = _targets!;
    final result = await _showNumberEditor(
      title: 'Distance',
      initial: (t.distanceKm * 10).round(),
      suffix: 'km',
      step: 1,
      min: 5,
      max: 500,
      isDecimalTenths: true,
    );
    if (result != null) _persist(t.copyWith(distanceKm: result / 10));
  }

  Future<void> _editSleep() async {
    final t = _targets!;
    final start = TimeOfDay(
      hour: (t.sleepStartMin ~/ 60) % 24,
      minute: t.sleepStartMin % 60,
    );
    final end = TimeOfDay(
      hour: (t.sleepEndMin ~/ 60) % 24,
      minute: t.sleepEndMin % 60,
    );

    final newStart = await _pickTime('Sleep start', start);
    if (newStart == null) return;
    final newEnd = await _pickTime('Wake up', end);
    if (newEnd == null) return;

    _persist(
      t.copyWith(
        sleepStartMin: newStart.hour * 60 + newStart.minute,
        sleepEndMin: newEnd.hour * 60 + newEnd.minute,
      ),
    );
  }

  Future<TimeOfDay?> _pickTime(String title, TimeOfDay initial) {
    return showTimePicker(
      context: context,
      initialTime: initial,
      helpText: title.toUpperCase(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.gold,
              onPrimary: Colors.black,
              surface: AppTheme.surfaceDeep,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
  }

  Future<int?> _showNumberEditor({
    required String title,
    required int initial,
    required String suffix,
    required int step,
    required int min,
    required int max,
    bool isDecimalTenths = false,
  }) async {
    int value = initial;
    return showDialog<int>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final displayValue = isDecimalTenths
                ? (value / 10).toStringAsFixed(1)
                : '$value';
            return Dialog(
              backgroundColor: AppTheme.surfaceDeep,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppTypography.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _StepperButton(
                          icon: Icons.remove_rounded,
                          onTap: () => setDialogState(
                            () => value = (value - step).clamp(min, max),
                          ),
                        ),
                        SizedBox(
                          width: 120,
                          child: Text(
                            '$displayValue $suffix',
                            textAlign: TextAlign.center,
                            style: AppTypography.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        _StepperButton(
                          icon: Icons.add_rounded,
                          onTap: () => setDialogState(
                            () => value = (value + step).clamp(min, max),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'Cancel',
                              style: AppTypography.inter(
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context, value),
                            child: Text(
                              'Save',
                              style: AppTypography.inter(
                                color: AppTheme.gold,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Stack(
        children: [
          Positioned(
            left: 83,
            top: -100,
            child: _GlowBlob(width: 280, height: 200),
          ),
          Positioned(
            left: -227,
            bottom: -161,
            child: _GlowBlob(
              width: 450,
              height: 320,
              color: AppTheme.gold.withValues(alpha: 0.025),
            ),
          ),
          SafeArea(
            child: _targets == null
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.gold),
                  )
                : _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final t = _targets!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassHeader(
          title: 'Goal setting',
          trailing: GlassIconButton(
            icon: Icons.check_rounded,
            onTap: () => Navigator.pop(context),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 12),
          child: Text(
            'PROFILE',
            style: AppTypography.inter(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 2.0,
              color: Colors.white.withValues(alpha: 0.42),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
            child: Column(
              children: [
                _GoalRow(
                  icon: Icons.directions_walk_rounded,
                  iconColor: AppTheme.stepsColor,
                  label: 'Steps',
                  value: '${t.steps} steps',
                  showDivider: true,
                  onTap: _editSteps,
                ),
                _GoalRow(
                  icon: Icons.local_fire_department_rounded,
                  iconColor: AppTheme.stepsColor,
                  label: 'Calories',
                  value: '${t.calories} kcal',
                  showDivider: true,
                  onTap: _editCalories,
                ),
                _GoalRow(
                  icon: Icons.directions_run_rounded,
                  iconColor: AppTheme.stepsColor,
                  label: 'Distance',
                  value: '${t.distanceKm.toStringAsFixed(1)} km',
                  showDivider: true,
                  onTap: _editDistance,
                ),
                _GoalRow(
                  icon: Icons.bedtime_rounded,
                  iconColor: AppTheme.sleepColor,
                  label: 'Sleep',
                  value: t.sleepLabel,
                  showDivider: false,
                  onTap: _editSleep,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────

class _GlowBlob extends StatelessWidget {
  final double width;
  final double height;
  final Color color;

  const _GlowBlob({
    required this.width,
    required this.height,
    this.color = AppTheme.goldGlow,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

/// A single row: icon chip · label · value (right-aligned, muted) · tap to edit.
class _GoalRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final bool showDivider;
  final VoidCallback onTap;

  const _GoalRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.showDivider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: showDivider
              ? Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.04),
                    width: 0.5,
                  ),
                )
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                    width: 0.5,
                  ),
                ),
                child: Icon(icon, color: iconColor, size: 16),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.005,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ),
              Text(
                value,
                style: AppTypography.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.42),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 18,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}
