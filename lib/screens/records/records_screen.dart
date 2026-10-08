import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class RecordsScreen extends StatelessWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            const Text(
              'Records',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'All your health data',
              style: TextStyle(color: AppTheme.textSec, fontSize: 14),
            ),
            const SizedBox(height: 24),
            _sectionLabel('HEALTH VITALS'),
            const SizedBox(height: 8),
            _vitalsGroup(context),
            const SizedBox(height: 20),
            _sectionLabel('WOMEN\'S HEALTH'),
            const SizedBox(height: 8),
            _womensGroup(context),
            const SizedBox(height: 20),
            _sectionLabel('ACTIVITY'),
            const SizedBox(height: 8),
            _activityGroup(context),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            color: AppTheme.textSec,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
      );

  Widget _vitalsGroup(BuildContext context) {
    final items = [
      _RecordItem('Heart Rate', Icons.favorite_rounded, AppTheme.hrColor, '/heart-rate', '-- bpm'),
      _RecordItem('Blood Pressure', Icons.water_drop_rounded, AppTheme.bpColor, '/blood-pressure', '--/-- mmHg'),
      _RecordItem('Blood Oxygen', Icons.bloodtype_rounded, AppTheme.spo2Color, '/blood-oxygen', '-- %'),
      _RecordItem('Sleep', Icons.bedtime_rounded, AppTheme.sleepColor, '/sleep', '-- hrs'),
      _RecordItem('HRV', Icons.monitor_heart_rounded, AppTheme.hrvColor, '/hrv', '-- ms'),
      _RecordItem('Stress / Pressure', Icons.psychology_rounded, AppTheme.stressColor, '/pressure', '--'),
      _RecordItem('Temperature', Icons.thermostat_rounded, AppTheme.tempColor, '/temperature', '-- °C'),
    ];
    return _itemsCard(context, items);
  }

  Widget _womensGroup(BuildContext context) {
    final items = [
      _RecordItem('Women\'s Health', Icons.favorite_rounded,
          const Color(0xFFEC4899), '/womens-health', 'Cycle · Fertility · Symptoms'),
    ];
    return _itemsCard(context, items);
  }

  Widget _activityGroup(BuildContext context) {
    final items = [
      _RecordItem('Steps', Icons.directions_walk_rounded, AppTheme.stepsColor, '/steps', '-- steps'),
      _RecordItem('Sport Records', Icons.sports_gymnastics_rounded, const Color(0xFFD97706), '/sport-record', '--'),
      _RecordItem('Sugar & Lipids', Icons.science_rounded, const Color(0xFFEC4899), '/sugar-lipids', '--'),
    ];
    return _itemsCard(context, items);
  }

  Widget _itemsCard(BuildContext context, List<_RecordItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.div),
      ),
      child: Column(
        children: items.asMap().entries.map((e) {
          final item = e.value;
          final isLast = e.key == items.length - 1;
          return Column(
            children: [
              _RecordTile(item: item),
              if (!isLast) const Divider(height: 1, indent: 56, endIndent: 0, color: AppTheme.div),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _RecordItem {
  final String title;
  final IconData icon;
  final Color color;
  final String route;
  final String subtitle;
  const _RecordItem(this.title, this.icon, this.color, this.route, this.subtitle);
}

class _RecordTile extends StatelessWidget {
  final _RecordItem item;
  const _RecordTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, item.route),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.icon, color: item.color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppTheme.textSec, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppTheme.textSec, size: 20),
          ],
        ),
      ),
    );
  }
}
