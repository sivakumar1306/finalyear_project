import 'package:flutter/material.dart';
import 'app_typography.dart';
import 'glass_card.dart';

class DateScrollRow extends StatelessWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;

  const DateScrollRow({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
  });

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dates = List.generate(7, (i) => today.add(Duration(days: i - 3)));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < dates.length; i++) ...[
            if (i > 0) const SizedBox(width: 16),
            _buildItem(dates[i], today),
          ],
        ],
      ),
    );
  }

  Widget _buildItem(DateTime d, DateTime today) {
    final isToday = d == today;
    final isFuture = d.isAfter(today);
    final sel = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final isSelected = d == sel && !isToday;

    if (isToday || isSelected) {
      return GestureDetector(
        onTap: isToday ? null : () => onDateSelected(d),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF202020),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF363636)),
          ),
          child: Text(
            isToday ? 'Today, ${d.day} ${_months[d.month - 1]}' : '${d.day} ${_months[d.month - 1]}',
            style: AppTypography.inter(13, weight: FontWeight.w500),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: isFuture ? null : () => onDateSelected(d),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text(
          '${d.day}',
          style: AppTypography.inter(15, color: isFuture ? const Color(0xFF333333) : kSec2),
        ),
      ),
    );
  }
}
