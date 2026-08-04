import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_typography.dart';

class SleepHighlightsCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback? onTap;

  const SleepHighlightsCard({
    super.key,
    required this.data,
    this.onTap,
  });

  String _formatMinutes(int totalMins) {
    if (totalMins <= 0) return '0m';
    final h = totalMins ~/ 60;
    final m = totalMins % 60;
    if (h > 0) {
      return m > 0 ? '${h}h ${m}m' : '${h}h';
    }
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final int awake = (data['time_awake_min'] as num? ?? 0).toInt();
    final int light = (data['light_sleep_min'] as num? ?? 0).toInt();
    final int deep = (data['deep_sleep_min'] as num? ?? 0).toInt();
    
    int totalMinutes = awake + light + deep;
    if (totalMinutes == 0) totalMinutes = 1;

    // RepaintBoundary caches the blurred layer so scrolling the chat list
    // doesn't re-blur the backdrop every frame.
    return RepaintBoundary(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 335),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    decoration: BoxDecoration(
                      color: const Color(0x0AFFFFFF), // rgba(255,255,255,0.03)
                      border: Border.all(
                        color: const Color(0x14FFFFFF), // rgba(255,255,255,0.08)
                        width: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SLEEP HIGHLIGHTS',
                          style: AppTypography.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.14 * 10, // 0.14em
                            color: const Color(0x6BFFFFFF), // rgba(255,255,255,0.42)
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          height: 0.5,
                          color: const Color(0x0AFFFFFF), // rgba(255,255,255,0.04)
                        ),
                        const SizedBox(height: 14),
                        _buildRow(
                          color: AppTheme.sleepAwake,
                          label: 'Time Awake',
                          mins: awake,
                          totalMins: totalMinutes,
                        ),
                        _buildDivider(),
                        _buildRow(
                          color: AppTheme.sleepLight,
                          label: 'Light Sleep',
                          mins: light,
                          totalMins: totalMinutes,
                        ),
                        _buildDivider(),
                        _buildRow(
                          color: AppTheme.sleepDeep,
                          label: 'Deep Sleep',
                          mins: deep,
                          totalMins: totalMinutes,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        height: 0.5,
        color: const Color(0x0AFFFFFF), // rgba(255,255,255,0.04)
      ),
    );
  }

  Widget _buildRow({
    required Color color,
    required String label,
    required int mins,
    required int totalMins,
  }) {
    final double ratio = (mins / totalMins).clamp(0.0, 1.0);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: AppTypography.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w400,
              color: const Color(0xEBFFFFFF), // rgba(255,255,255,0.92)
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 6,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Container(
                    height: 4,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0x0FFFFFFF), // rgba(255,255,255,0.06)
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                  Container(
                    height: 4,
                    width: constraints.maxWidth * ratio,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 45,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              _formatMinutes(mins),
              style: AppTypography.inter(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: const Color(0x73FFFFFF), // rgba(255,255,255,0.45)
              ),
            ),
          ),
        ),
      ],
    );
  }
}
