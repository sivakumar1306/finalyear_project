import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../widgets/analog_clock_picker.dart';
import '../../widgets/glass_icon_button.dart';

// Same keys as Alarms & Notifications — native reconnect loop reads these
// from FlutterSharedPreferences for the daily sleep reminder.
const _kSleepReminderEnabledKey = 'sleep_reminder_enabled';
const _kSleepReminderHourKey = 'sleep_reminder_hour';
const _kSleepReminderMinuteKey = 'sleep_reminder_minute';

/// Sleep reminder scheduler — same drag-to-set analog clock as Prayer Mode,
/// reached via the Sleep row in Alarms & Notifications.
class SleepScheduleScreen extends StatefulWidget {
  const SleepScheduleScreen({super.key});

  @override
  State<SleepScheduleScreen> createState() => _SleepScheduleScreenState();
}

class _SleepScheduleScreenState extends State<SleepScheduleScreen> {
  static const _defaultTime = TimeOfDay(hour: 22, minute: 30);

  TimeOfDay _time = _defaultTime;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final enabled = prefs.getBool(_kSleepReminderEnabledKey) ?? false;
    setState(() {
      if (enabled) {
        _time = TimeOfDay(
          hour:
              int.tryParse(prefs.getString(_kSleepReminderHourKey) ?? '') ??
              _defaultTime.hour,
          minute:
              int.tryParse(prefs.getString(_kSleepReminderMinuteKey) ?? '') ??
              _defaultTime.minute,
        );
      } else {
        _time = _defaultTime;
      }
      _loaded = true;
    });
  }

  Future<void> _save(TimeOfDay t) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSleepReminderEnabledKey, true);
    // Stored as strings — Android shared_preferences stores Dart ints as Long,
    // so native getInt() would ClassCastException. Strings round-trip safely.
    await prefs.setString(_kSleepReminderHourKey, t.hour.toString());
    await prefs.setString(_kSleepReminderMinuteKey, t.minute.toString());
  }

  void _onClockChanged(TimeOfDay t) {
    // Draft only — persisted when the user taps the check button.
    setState(() => _time = t);
  }

  Future<void> _confirm() async {
    await _save(_time);
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
              color: AppTheme.sleepColor.withValues(alpha: 0.04),
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
                'Sleep Reminder',
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
            'REMINDER TIME',
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
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
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
                  'REMINDER',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    color: AppTheme.gold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _fmt(_time),
                  style: GoogleFonts.inter(
                    fontSize: 15,
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
                  _fmt(_time),
                  style: GoogleFonts.inter(
                    fontSize: 34,
                    fontWeight: FontWeight.w300,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                AnalogClockPicker(
                  initialTime: _time,
                  onChanged: _onClockChanged,
                ),
                const SizedBox(height: 28),
                Text(
                  'You\'ll be reminded to wind down at ${_fmt(_time)}',
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
