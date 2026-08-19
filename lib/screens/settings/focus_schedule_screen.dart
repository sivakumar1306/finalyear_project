import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/alarm_schedule_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/analog_clock_picker.dart';
import '../../widgets/glass_header.dart';
import '../../widgets/app_typography.dart';

/// Focus mode end-time scheduler — matching Meditation schedule screen style
/// with drag-to-set analog clock picker.
class FocusScheduleScreen extends StatefulWidget {
  const FocusScheduleScreen({super.key});

  @override
  State<FocusScheduleScreen> createState() => _FocusScheduleScreenState();
}

class _FocusScheduleScreenState extends State<FocusScheduleScreen> {
  late TimeOfDay _focusEnd;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final sched = context.read<AlarmScheduleProvider>();
    _focusEnd = sched.focusEnd;
    _loaded = true;
  }

  void _onClockChanged(TimeOfDay t) {
    setState(() => _focusEnd = t);
  }

  Future<void> _confirm() async {
    final sched = context.read<AlarmScheduleProvider>();
    await sched.setFocusEnd(_focusEnd);
    if (!mounted) return;
    Navigator.pop(context);
  }

  String _fmt(TimeOfDay t) => t.format(context);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Stack(
        children: [
          Positioned(
            left: 83,
            top: -100,
            child: const _GlowBlob(width: 280, height: 200),
          ),
          Positioned(
            left: -227,
            bottom: -161,
            child: _GlowBlob(
              width: 450,
              height: 320,
              color: AppTheme.focus.withValues(alpha: 0.025),
            ),
          ),
          SafeArea(
            child: !_loaded
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const GlassHeader(title: 'Schedule Focus'),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 12),
          child: Text(
            'FOCUS DURATION',
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
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
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
                Text(
                  'ENDS AT',
                  style: AppTypography.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    color: AppTheme.gold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _fmt(_focusEnd),
                  style: AppTypography.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.95),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _fmt(_focusEnd),
                  style: AppTypography.inter(
                    fontSize: 34,
                    fontWeight: FontWeight.w300,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                AnalogClockPicker(
                  initialTime: _focusEnd,
                  onChanged: _onClockChanged,
                ),
                const SizedBox(height: 28),
                Text(
                  'Focus mode stays active until ${_fmt(_focusEnd)}',
                  style: AppTypography.inter(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.42),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _confirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                elevation: 0,
              ),
              child: Text(
                'Confirm',
                style: AppTypography.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

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
