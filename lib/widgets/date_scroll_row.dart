import 'package:flutter/material.dart';
import 'app_typography.dart';

class DateScrollRow extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;

  const DateScrollRow({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
  });

  @override
  State<DateScrollRow> createState() => _DateScrollRowState();
}

class _DateScrollRowState extends State<DateScrollRow> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _selectedKey = GlobalKey();

  static const _monthAbbr = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected(animate: false));
  }

  @override
  void didUpdateWidget(covariant DateScrollRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameDay(oldWidget.selectedDate, widget.selectedDate)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected(animate: true));
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _scrollToSelected({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    final ctx = _selectedKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: animate ? const Duration(milliseconds: 250) : Duration.zero,
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final year = widget.selectedDate.year;
    final month = widget.selectedDate.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final dates = List.generate(daysInMonth, (i) => DateTime(year, month, i + 1));

    return SizedBox(
      height: 58,
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: dates.length,
        itemBuilder: (context, i) {
          final date = dates[i];
          final isToday = _sameDay(date, today);
          final isSelected = _sameDay(date, widget.selectedDate);
          final isFuture = date.isAfter(today);

          return Padding(
            key: isSelected ? _selectedKey : null,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: isFuture ? null : () => widget.onDateSelected(date),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  alignment: Alignment.center,
                  constraints: BoxConstraints(
                    minWidth: isSelected ? 96 : 44,
                    minHeight: 40,
                  ),
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: EdgeInsets.symmetric(
                    horizontal: isSelected ? 16 : 12,
                    vertical: 8,
                  ),
                  decoration: isSelected
                      ? BoxDecoration(
                          color: const Color(0xFF202020),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: const Color(0xFF363636),
                            width: 0.5,
                          ),
                        )
                      : null,
                  child: Text(
                    isSelected
                        ? (isToday
                              ? 'Today, ${date.day} ${_monthAbbr[date.month - 1]}'
                              : '${date.day} ${_monthAbbr[date.month - 1]}')
                        : '${date.day}',
                    style: AppTypography.inter(
                      fontSize: isSelected ? 13 : 14,
                      fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                      color: isFuture
                          ? Colors.white.withValues(alpha: 0.35)
                          : isSelected
                          ? Colors.white.withValues(alpha: 0.95)
                          : Colors.white.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
