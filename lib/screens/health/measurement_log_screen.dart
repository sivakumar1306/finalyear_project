import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';

/// A single measurement entry for the log screen.
class MeasurementEntry {
  final DateTime time;
  final String value;
  final String unit;
  final String? label;
  final Color? color;
  final IconData? icon;

  const MeasurementEntry({
    required this.time,
    required this.value,
    required this.unit,
    this.label,
    this.color,
    this.icon,
  });
}

/// Generic measurement log screen — shows a scrollable list of
/// [MeasurementEntry] items for any health metric.
///
/// Used by HRV, Heart Rate, SpO2, Blood Pressure, Temperature, and Stress
/// screens to display per-reading breakdowns.
class MeasurementLogScreen extends StatelessWidget {
  final String title;
  final DateTime date;
  final List<MeasurementEntry> entries;
  final Color accentColor;

  const MeasurementLogScreen({
    super.key,
    required this.title,
    required this.date,
    required this.entries,
    this.accentColor = AppTheme.gold,
  });

  @override
  Widget build(BuildContext context) {
    final months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    final dateLabel =
        '${months[date.month - 1]} ${date.day}, ${date.year}';

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: const GlassBackButton(),
        title: Text(title, style: _inter(17, weight: FontWeight.w600)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(color: AppTheme.div, height: 0.5),
        ),
      ),
      body: entries.isEmpty
          ? _buildEmptyState(dateLabel)
          : _buildList(dateLabel),
    );
  }

  Widget _buildEmptyState(String dateLabel) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.monitor_heart_rounded,
            color: AppTheme.textTertiary,
            size: 36,
          ),
          const SizedBox(height: 12),
          Text(
            'No readings for $dateLabel',
            style: _inter(14, color: AppTheme.textSec),
          ),
        ],
      ),
    );
  }

  Widget _buildList(String dateLabel) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              dateLabel.toUpperCase(),
              style: _inter(
                10,
                weight: FontWeight.w600,
                color: AppTheme.textTertiary,
                letterSpacing: 0.7,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '${entries.length} reading${entries.length == 1 ? '' : 's'}',
              style: _inter(12, color: AppTheme.textSec),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final entry = entries[index];
              final isLast = index == entries.length - 1;
              return _MeasurementRow(
                entry: entry,
                isLast: isLast,
              );
            },
            childCount: entries.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }
}

class _MeasurementRow extends StatelessWidget {
  final MeasurementEntry entry;
  final bool isLast;

  const _MeasurementRow({required this.entry, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final color = entry.color ?? AppTheme.gold;
    final icon = entry.icon ?? Icons.monitor_heart_rounded;
    final timeStr = _fmtTime(entry.time);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      timeStr,
                      style: _inter(14, weight: FontWeight.w600),
                    ),
                    if (entry.label != null)
                      Text(
                        entry.label!,
                        style: _inter(11, color: color),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    entry.value,
                    style: _inter(22, weight: FontWeight.w700),
                  ),
                  Text(
                    entry.unit,
                    style: _inter(10, color: AppTheme.textTertiary),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!isLast)
          const Divider(color: AppTheme.div, height: 0.5, indent: 66),
      ],
    );
  }
}

String _fmtTime(DateTime dt) {
  final h = dt.hour;
  final m = dt.minute;
  final period = h >= 12 ? 'PM' : 'AM';
  final h12 = h == 0 ? 12 : h > 12 ? h - 12 : h;
  return '$h12:${m.toString().padLeft(2, '0')} $period';
}

TextStyle _inter(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = Colors.white,
  double? letterSpacing,
}) =>
    AppTypography.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
    );
