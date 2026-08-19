import 'dart:ui';
import 'package:flutter/material.dart';
import '../../services/prayer_schedule_prefs.dart';
import '../../theme/app_theme.dart';
import '../../widgets/analog_clock_picker.dart';
import '../../widgets/glass_header.dart';
import '../../widgets/app_typography.dart';

/// Meditation quiet-hours scheduler — drag-to-set analog clock for end time.
class PrayerScheduleScreen extends StatefulWidget {
  const PrayerScheduleScreen({super.key});

  @override
  State<PrayerScheduleScreen> createState() => _PrayerScheduleScreenState();
}

class _PrayerScheduleScreenState extends State<PrayerScheduleScreen> {
  TimeOfDay _end = PrayerSchedulePrefs.defaultEnd;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final (_, end) = await PrayerSchedulePrefs.load();
    if (!mounted) return;
    setState(() {
      _end = end;
      _loaded = true;
    });
  }

  void _onClockChanged(TimeOfDay t) {
    setState(() {
      _end = t;
    });
  }

  Future<void> _confirm() async {
    await PrayerSchedulePrefs.save(PrayerSchedulePrefs.defaultStart, _end);
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
              color: AppTheme.stressColor.withValues(alpha: 0.025),
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
        const GlassHeader(title: 'Schedule meditation'),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 12),
          child: Text(
            'QUIET HOURS',
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
                  _fmt(_end),
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
                  _fmt(_end),
                  style: AppTypography.inter(
                    fontSize: 34,
                    fontWeight: FontWeight.w300,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                AnalogClockPicker(
                  initialTime: _end,
                  onChanged: _onClockChanged,
                ),
                const SizedBox(height: 28),
                Text(
                  'Notifications stay silent until ${_fmt(_end)}',
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
