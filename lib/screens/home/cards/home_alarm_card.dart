import 'dart:ui' show ImageFilter, TileMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../providers/alarm_mode_provider.dart';
import '../../../providers/alarm_schedule_provider.dart';
import '../../../services/prayer_schedule_prefs.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_typography.dart';
import '../../prayer/prayer_session_screen.dart';
import 'home_card_shared.dart';
import 'home_vitals_cards.dart';
// ── Alarms card ────────────────────────────────────────────────────────────

class AlarmModeInfo {
  final String segmentLabel;
  final Color color;
  final IconData icon;
  const AlarmModeInfo(this.segmentLabel, this.color, this.icon);
}

const Map<PhoneMode, AlarmModeInfo> _kAlarmModeInfo = {
  PhoneMode.focus: AlarmModeInfo(
    'Focus',
    AppTheme.focus,
    Icons.adjust_rounded,
  ),
  PhoneMode.base: AlarmModeInfo(
    'Base',
    AppTheme.gold,
    Icons.circle_outlined,
  ),
  PhoneMode.prayer: AlarmModeInfo(
    'Meditation',
    Color(0xFF5BAE85),
    Icons.self_improvement_rounded,
  ),
};

class AlarmGlowBackground extends StatelessWidget {
  final Color color;
  const AlarmGlowBackground({
    super.key,this.color = AppTheme.focus});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Ellipse 21 (bottom-left glow: rgba(224, 138, 74, 0.15), blur 40px, 240x240, left -70, top 90)
        Positioned(
          left: -70,
          top: 90,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: 40,
              sigmaY: 40,
              tileMode: TileMode.decal,
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 480),
              curve: Curves.easeOutCubic,
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.15),
              ),
            ),
          ),
        ),
        // Ellipse 20 (top-right glow: rgba(224, 138, 74, 0.25), blur 40px, 240x240, right -60, top -70)
        Positioned(
          right: -60,
          top: -70,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: 40,
              sigmaY: 40,
              tileMode: TileMode.decal,
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 480),
              curve: Curves.easeOutCubic,
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.25),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class AlarmCard extends StatefulWidget {
  final bool expanded;
  const AlarmCard({
    super.key,this.expanded = false});

  @override
  State<AlarmCard> createState() => AlarmCardState();
}

class AlarmCardState extends State<AlarmCard> {
  TimeOfDay _meditationEnd = PrayerSchedulePrefs.defaultEnd;
  TimeOfDay? _sleepTime;
  bool _hasSavedMeditation = false;
  bool _sleepReminderEnabled = false;
  bool _scheduleLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final (_, end) = await PrayerSchedulePrefs.load();
    final hasSavedMeditation =
        prefs.containsKey('prayer_mode_end_hour') ||
        prefs.containsKey('prayer_mode_start_hour');
    final sleepEnabled = prefs.getBool('sleep_reminder_enabled') ?? false;
    final h = int.tryParse(prefs.getString('sleep_reminder_hour') ?? '') ?? 22;
    final m =
        int.tryParse(prefs.getString('sleep_reminder_minute') ?? '') ?? 30;
    final sleepTime = TimeOfDay(hour: h, minute: m);
    if (!mounted) return;
    setState(() {
      _meditationEnd = end;
      _hasSavedMeditation = hasSavedMeditation;
      _sleepReminderEnabled = sleepEnabled;
      _sleepTime = sleepTime;
      _scheduleLoaded = true;
    });
  }

  String _headline(PhoneMode mode, AlarmScheduleProvider sched) {
    if (widget.expanded) {
      switch (mode) {
        case PhoneMode.focus:
          return sched.isFocusScheduled
              ? 'No Alarms, no calls till ${sched.label(sched.focusEnd)}'
              : 'No Alarms, no calls';
        case PhoneMode.prayer:
          return 'Do Not Disturb until ${_fmt24(_meditationEnd)}';
        case PhoneMode.base:
          return 'All alarms and calls are on';
      }
    }
    switch (mode) {
      case PhoneMode.focus:
        return 'Focus';
      case PhoneMode.prayer:
        return 'Prayer mode';
      case PhoneMode.base:
        return 'Normal';
    }
  }

  String _subtext(PhoneMode mode, AlarmScheduleProvider sched) {
    if (widget.expanded) {
      switch (mode) {
        case PhoneMode.focus:
          return sched.pushingAppsCount > 0
              ? '${sched.pushingAppsCount} apps still pushing · Calls from favourites only'
              : 'Calls from favourites only';
        case PhoneMode.prayer:
          return 'Priority interruptions only · Auto-off at ${_fmt24(_meditationEnd)}';
        case PhoneMode.base:
          return 'Ringer normal · No restrictions';
      }
    }
    switch (mode) {
      case PhoneMode.focus:
        return sched.isFocusScheduled
            ? 'Until ${_fmt24(sched.focusEnd)}'
            : 'Silent mode active';
      case PhoneMode.prayer:
        return 'Until ${_fmt24(_meditationEnd)}';
      case PhoneMode.base:
        return 'All alerts on';
    }
  }

  /// Formats a TimeOfDay as 24-hour "HH:mm" — matches "Until 13:00" / "Dhuhr 13:14".
  String _fmt24(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AlarmModeProvider>();
    final sched = context.watch<AlarmScheduleProvider>();
    final mode = provider.mode;
    final info = _kAlarmModeInfo[mode]!;

    if (!sched.isLoaded || !_scheduleLoaded) {
      return const SizedBox(height: 160);
    }

    final isFocusSet = mode == PhoneMode.focus && sched.isFocusScheduled;
    final isMeditationSet = mode == PhoneMode.prayer || _hasSavedMeditation;
    final isSleepSet = _sleepReminderEnabled && _sleepTime != null;

    final activeFields = <Widget>[];

    if (isFocusSet) {
      activeFields.add(
        Expanded(
          child: AlarmTimeField(
            timeLabel: sched.label(sched.focusEnd),
            label: 'Focus ends',
          ),
        ),
      );
    }

    if (isMeditationSet) {
      if (activeFields.isNotEmpty) {
        activeFields.add(
          Container(
            width: 1,
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: Colors.white.withValues(alpha: 0.08),
          ),
        );
      }
      activeFields.add(
        Expanded(
          child: AlarmTimeField(
            timeLabel: sched.label(_meditationEnd),
            label: 'Meditation ends',
          ),
        ),
      );
    }

    if (isSleepSet) {
      if (activeFields.isNotEmpty) {
        activeFields.add(
          Container(
            width: 1,
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: Colors.white.withValues(alpha: 0.08),
          ),
        );
      }
      activeFields.add(
        Expanded(
          child: AlarmTimeField(
            timeLabel: sched.label(_sleepTime!),
            label: 'Wind-down Alarm',
          ),
        ),
      );
    }

    final hasBottomRow = widget.expanded && activeFields.isNotEmpty;

    return HomeGlassCard(
      orbColor: info.color,
      orbAtTop: true,
      backgroundOverride: AlarmGlowBackground(color: info.color),
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'ALARMS',
                  style: inter(
                    11,
                    weight: FontWeight.w700,
                    color: info.color,
                    letterSpacing: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: () async {
                  await Navigator.pushNamed(context, '/alarms-notifications');
                  _loadSchedules();
                },
                child: chevron(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (mode == PhoneMode.prayer) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PrayerSessionScreen(),
                  ),
                );
              }
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              switchInCurve: const Cubic(0.34, 1.2, 0.64, 1.0),
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.12),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: Column(
                key: ValueKey(mode),
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _headline(mode, sched),
                    style: AppTypography.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                      color: info.color,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _subtext(mode, sched),
                    style: inter(
                      12.5,
                      color: Colors.white.withValues(alpha: 0.55),
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          AlarmModeSelector(
            mode: mode,
            onChanged: (m) {
              if (m != PhoneMode.focus) {
                context.read<AlarmScheduleProvider>().clearFocusSchedule();
              }
              requestPhoneMode(context, provider, m);
              if (m == PhoneMode.prayer) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PrayerSessionScreen(),
                  ),
                );
              }
            },
          ),
          if (hasBottomRow) ...[
            const SizedBox(height: 14),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
            const SizedBox(height: 12),
            Row(children: activeFields),
          ],
        ],
      ),
    );
  }
}

/// One time column at the bottom of the enlarged Alarms card.
class AlarmTimeField extends StatelessWidget {
  final String timeLabel;
  final String label;

  const AlarmTimeField({
    super.key,required this.timeLabel, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          timeLabel,
          style: AppTypography.inter(
            fontSize: 17,
            fontWeight: FontWeight.w400,
            color: Colors.white.withValues(alpha: 0.95),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: inter(
            11,
            color: Colors.white.withValues(alpha: 0.45),
            weight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// Apple-style liquid-glass segmented control for Focus / Normal / Prayer.
// A single frosted pill slides under the active mode with springy motion and
// soft color morph — not per-segment solid fills that pop.
class AlarmModeSelector extends StatelessWidget {
  final PhoneMode mode;
  final ValueChanged<PhoneMode> onChanged;
  const AlarmModeSelector({
    super.key,required this.mode, required this.onChanged});

  static const _kSlideDuration = Duration(milliseconds: 480);
  // Slight overshoot — feels like liquid glass settling into place.
  static const _kSlideCurve = Cubic(0.34, 1.25, 0.64, 1.0);

  @override
  Widget build(BuildContext context) {
    final modes = PhoneMode.values;
    final selectedIndex = modes.indexOf(mode);
    final selectedInfo = _kAlarmModeInfo[mode]!;
    // Alignment.x for equal-width segments: -1, 0, +1 for 3 items.
    final alignX = modes.length <= 1
        ? 0.0
        : -1.0 + (2.0 * selectedIndex / (modes.length - 1));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: kBtnBg,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: kBtnBorder, width: 0.5),
      ),
      // Row defines height; thumb fills that height and slides across segments.
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              duration: _kSlideDuration,
              curve: _kSlideCurve,
              alignment: Alignment(alignX, 0),
              child: FractionallySizedBox(
                widthFactor: 1 / modes.length,
                heightFactor: 1,
                child: Padding(
                  padding: const EdgeInsets.all(1),
                  child: LiquidGlassThumb(color: selectedInfo.color),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final m in modes)
                Expanded(
                  child: AlarmSegment(
                    mode: m,
                    selected: m == mode,
                    onTap: () {
                      if (m == mode && m != PhoneMode.prayer) return;
                      HapticFeedback.selectionClick();
                      onChanged(m);
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Frosted pill that morphs color as the active mode changes.
class LiquidGlassThumb extends StatelessWidget {
  final Color color;
  const LiquidGlassThumb({
    super.key,required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AlarmModeSelector._kSlideDuration,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.20),
            blurRadius: 10,
            spreadRadius: -1,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}

class AlarmSegment extends StatelessWidget {
  final PhoneMode mode;
  final bool selected;
  final VoidCallback onTap;

  const AlarmSegment({
    super.key,
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final info = _kAlarmModeInfo[mode]!;
    final idle = Colors.white.withValues(alpha: 0.42);
    final active = info.color;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) {
                return FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.85, end: 1.0).animate(anim),
                    child: child,
                  ),
                );
              },
              child: Icon(
                info.icon,
                key: ValueKey<bool>(selected),
                size: selected ? 17 : 16,
                color: selected ? active : idle,
              ),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  style: inter(
                    11,
                    weight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? active : idle,
                    height: 1.1,
                  ),
                  child: Text(
                    info.segmentLabel,
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// ── Women's Health card ───────────────────────────────────────────────────────

