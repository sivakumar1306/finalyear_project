import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Horizontal 5-day date selector. Pass [selectedDate] and [onDateSelected]
/// to make it interactive; omit both for the static "today highlighted" look.
class VitalDateSelector extends StatelessWidget {
  final DateTime? selectedDate;
  final ValueChanged<DateTime>? onDateSelected;

  const VitalDateSelector({super.key, this.selectedDate, this.onDateSelected});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dates = List.generate(5, (i) => now.subtract(Duration(days: 4 - i)));
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final sel = selectedDate ?? now;

    return Row(
      children: dates.map((d) {
        final isSelected = d.day == sel.day && d.month == sel.month && d.year == sel.year;
        final isToday = d.day == now.day && d.month == now.month && d.year == now.year;
        return Expanded(
          child: GestureDetector(
            onTap: onDateSelected != null ? () => onDateSelected!(d) : null,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 62,
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.gold : AppTheme.card,
                borderRadius: BorderRadius.circular(12),
                border: isSelected
                    ? null
                    : Border.all(
                        color: isToday
                            ? AppTheme.gold.withValues(alpha: 0.4)
                            : AppTheme.div,
                      ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    dayNames[d.weekday - 1],
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected ? Colors.black : AppTheme.textSec,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${d.day}',
                    style: TextStyle(
                      fontSize: 18,
                      color: isSelected ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Day / Week / Month tab bar. Pass [onChanged] to be notified of selection.
class VitalPeriodTabs extends StatefulWidget {
  final ValueChanged<int>? onChanged;
  const VitalPeriodTabs({super.key, this.onChanged});

  @override
  State<VitalPeriodTabs> createState() => _VitalPeriodTabsState();
}

class _VitalPeriodTabsState extends State<VitalPeriodTabs> {
  int _sel = 0;

  @override
  Widget build(BuildContext context) {
    const tabs = ['Day', 'Week', 'Month'];
    return Row(
      children: List.generate(tabs.length, (i) {
        final active = i == _sel;
        return GestureDetector(
          onTap: () {
            setState(() => _sel = i);
            widget.onChanged?.call(i);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: active ? AppTheme.gold : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(
              tabs[i],
              style: TextStyle(
                color: active ? AppTheme.gold : AppTheme.textSec,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                fontSize: 14,
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Primary measurement action button.
class VitalOneClickButton extends StatelessWidget {
  final String label;
  final bool loading;
  final bool enabled;
  final bool isStop;
  final VoidCallback? onPressed;

  const VitalOneClickButton({
    super.key,
    this.label = 'One Click Measurement',
    this.loading = false,
    this.enabled = true,
    this.isStop = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    const stopGradient = LinearGradient(
      colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    const goldGradient = LinearGradient(
      colors: [Color(0xFFD4A853), Color(0xFF9A7235)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return GestureDetector(
      onTap: (enabled && !loading) ? onPressed : null,
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          gradient: enabled
              ? (isStop ? stopGradient : goldGradient)
              : null,
          color: enabled ? null : AppTheme.card2,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: loading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: enabled ? Colors.black : AppTheme.textSec,
                    strokeWidth: 2.5,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isStop ? Icons.stop_rounded : Icons.flash_on_rounded,
                      color: enabled ? Colors.black : AppTheme.textSec,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        color: enabled ? Colors.black : AppTheme.textSec,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Average / Minimum / Maximum stats row.
class VitalStatsRow extends StatelessWidget {
  final String avg;
  final String min;
  final String max;
  final String unit;

  const VitalStatsRow({
    super.key,
    required this.avg,
    required this.min,
    required this.max,
    this.unit = '',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.div),
      ),
      child: Row(
        children: [
          _StatCell(label: 'Average', value: avg, unit: unit),
          Container(width: 1, height: 44, color: AppTheme.div),
          _StatCell(label: 'Minimum', value: min, unit: unit),
          Container(width: 1, height: 44, color: AppTheme.div),
          _StatCell(label: 'Maximum', value: max, unit: unit),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _StatCell({required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(color: AppTheme.textSec, fontSize: 11)),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
          if (unit.isNotEmpty)
            Text(unit,
                style:
                    const TextStyle(color: AppTheme.textSec, fontSize: 10)),
        ],
      ),
    );
  }
}
