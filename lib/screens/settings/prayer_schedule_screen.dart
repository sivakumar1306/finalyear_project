import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/prayer_schedule_prefs.dart';
import '../../theme/app_theme.dart';
import '../../widgets/analog_clock_picker.dart';
import '../../widgets/glass_icon_button.dart';

/// Prayer Mode's quiet-hours scheduler — a clean drag-to-set analog clock
/// for the start and end time, reached via the pencil icon on the Prayer
/// Mode row in Alarms & Notifications.
class PrayerScheduleScreen extends StatefulWidget {
  const PrayerScheduleScreen({super.key});

  @override
  State<PrayerScheduleScreen> createState() => _PrayerScheduleScreenState();
}

class _PrayerScheduleScreenState extends State<PrayerScheduleScreen> {
  TimeOfDay _start = PrayerSchedulePrefs.defaultStart;
  TimeOfDay _end = PrayerSchedulePrefs.defaultEnd;
  bool _editingStart = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final (start, end) = await PrayerSchedulePrefs.load();
    if (!mounted) return;
    setState(() {
      _start = start;
      _end = end;
      _loaded = true;
    });
  }

  void _onClockChanged(TimeOfDay t) {
    // Draft only — persisted when the user taps the check button.
    setState(() {
      if (_editingStart) {
        _start = t;
      } else {
        _end = t;
      }
    });
  }

  Future<void> _confirm() async {
    await PrayerSchedulePrefs.save(_start, _end);
    if (!mounted) return;
    Navigator.pop(context);
  }

  String _fmt(TimeOfDay t) => t.format(context);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
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
              color: const Color(0xFF6BC99B).withValues(alpha: 0.025),
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
    final current = _editingStart ? _start : _end;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GlassIconButton(
                icon: Icons.arrow_back_rounded,
                onTap: () => Navigator.pop(context),
              ),
              Text(
                'Prayer Mode Schedule',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.005,
                  color: Colors.white.withValues(alpha: 0.88),
                ),
              ),
              GlassIconButton(
                icon: Icons.check_rounded,
                onTap: _confirm,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 12),
          child: Text(
            'QUIET HOURS',
            style: GoogleFonts.inter(
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
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _PeriodTab(
                    label: 'Start',
                    value: _fmt(_start),
                    selected: _editingStart,
                    onTap: () => setState(() => _editingStart = true),
                  ),
                ),
                Container(
                  width: 0.5,
                  height: 34,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                Expanded(
                  child: _PeriodTab(
                    label: 'End',
                    value: _fmt(_end),
                    selected: !_editingStart,
                    onTap: () => setState(() => _editingStart = false),
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
                  _fmt(current),
                  style: GoogleFonts.inter(
                    fontSize: 34,
                    fontWeight: FontWeight.w300,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                AnalogClockPicker(
                  key: ValueKey(_editingStart),
                  initialTime: current,
                  onChanged: _onClockChanged,
                ),
                const SizedBox(height: 28),
                Text(
                  'Notifications stay silent from ${_fmt(_start)} to ${_fmt(_end)}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.42),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PeriodTab extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  const _PeriodTab({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.white.withValues(alpha: 0.06) : null,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              label.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: selected
                    ? AppTheme.gold
                    : Colors.white.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: selected ? 0.95 : 0.55),
              ),
            ),
          ],
        ),
      ),
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
    this.color = const Color(0x0DC9A86E),
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
