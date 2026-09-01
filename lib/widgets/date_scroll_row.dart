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
  late final ScrollController _scrollController;
  final GlobalKey _selectedKey = GlobalKey();

  static const _monthAbbr = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// 90-day rolling window ending at today (inclusive) so the row always
  /// spans month boundaries. If [selected] is older than the window we
  /// extend the start to include it — guarantees any cached history is
  /// reachable even after a month change (fixes Sep-1 -> Aug-31 case).
  static const _windowDays = 90;

  List<DateTime> _datesFor(DateTime selected) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sel = DateTime(selected.year, selected.month, selected.day);
    var start = today.subtract(const Duration(days: _windowDays - 1));
    if (sel.isBefore(start)) start = sel;
    // If selected is in the future (should not happen) clamp to today.
    final end = sel.isAfter(today) ? sel : today;
    final count = end.difference(start).inDays + 1;
    return List.generate(count, (i) => start.add(Duration(days: i)));
  }

  double _calcInitialOffset(DateTime date) {
    final dates = _datesFor(date);
    final sel = DateTime(date.year, date.month, date.day);
    final idx = dates.indexWhere((d) => _sameDay(d, sel));
    final index = idx == -1 ? dates.length - 1 : idx;
    final target = (index * 48.0) - 120.0;
    return target < 0 ? 0.0 : target;
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      initialScrollOffset: _calcInitialOffset(widget.selectedDate),
    );
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
    } else {
      final target = _calcInitialOffset(widget.selectedDate);
      if (_scrollController.hasClients && target > 0) {
        _scrollController.jumpTo(
          target.clamp(0.0, _scrollController.position.maxScrollExtent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final dates = _datesFor(widget.selectedDate);

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
