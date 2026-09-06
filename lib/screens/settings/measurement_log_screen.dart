import 'package:flutter/material.dart';
import '../../services/measurement_log_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/footer_spacer.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/glass_card.dart';

/// Visual measurement log: last 3 days, grouped per auto cycle.
/// Local Room only (`measurement_cycle` + `measurement_attempt`).
class MeasurementLogScreen extends StatefulWidget {
  const MeasurementLogScreen({super.key});
  @override
  State<MeasurementLogScreen> createState() => _MeasurementLogScreenState();
}

class _MeasurementLogScreenState extends State<MeasurementLogScreen> {
  final _svc = MeasurementLogService();
  bool _failedOnly = false;
  bool _loading = true;
  List<GroupedCycle> _groups = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime get _from {
    final now = DateTime.now();
    final d = now.subtract(const Duration(days: 2));
    return DateTime(d.year, d.month, d.day);
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final groups = await _svc.getGroupedLog(from: _from, to: DateTime.now(), failedOnly: _failedOnly);
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _timeLabel(int ms) {
    if (ms <= 0) return '--';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'success':
      case 'COMPLETED':
        return AppTheme.success;
      case 'timeout':
      case 'YIELDED_TO_MANUAL':
        return AppTheme.focus;
      case 'failed':
      case 'rejected':
      case 'ABORTED_DISCONNECT':
        return AppTheme.danger;
      default:
        return AppTheme.textSec;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        centerTitle: true,
        leading: const GlassBackButton(),
        title: Text('Measurement Log', style: AppTypography.inter(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: RefreshIndicator(
        color: AppTheme.gold,
        backgroundColor: AppTheme.card,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          children: [
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('All')),
                      ButtonSegment(value: true, label: Text('Failed only')),
                    ],
                    selected: {_failedOnly},
                    onSelectionChanged: (s) {
                      setState(() => _failedOnly = s.first);
                      _load();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Last 3 days · grouped by automatic cycle',
                style: AppTypography.inter(fontSize: 11, color: AppTheme.textTertiary)),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: AppTheme.gold)))
            else if (_error != null)
              GlassCard(child: Text(_error!, style: AppTypography.inter(fontSize: 13, color: AppTheme.danger)))
            else if (_groups.isEmpty)
              GlassCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.history_rounded, size: 28, color: AppTheme.textTertiary),
                    const SizedBox(height: 10),
                    Text(_failedOnly ? 'NO FAILED MEASUREMENTS' : 'NO MEASUREMENTS YET',
                        style: AppTypography.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textTertiary, letterSpacing: 1.2)),
                    const SizedBox(height: 6),
                    Text(_failedOnly
                        ? 'No failed measurements in the last 3 days.'
                        : 'No automatic or manual measurements in the last 3 days. Wear your ring.',
                        textAlign: TextAlign.center,
                        style: AppTypography.inter(fontSize: 13, color: AppTheme.textSec, height: 1.4)),
                  ],
                ),
              )
            else
              for (final g in _groups) ...[
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              g.isManual
                                  ? 'Manual · ${_timeLabel(g.startedAt)}'
                                  : 'Auto cycle · ${_timeLabel(g.startedAt)}${g.completedAt != null ? ' – ${_timeLabel(g.completedAt!)}' : ''}',
                              style: AppTypography.inter(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _statusColor(g.status).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              g.attempts.isEmpty
                                  ? g.status
                                  : '${g.attempts.length - g.failedCount}/${g.attempts.length} ok',
                              style: AppTypography.inter(fontSize: 11, fontWeight: FontWeight.w600, color: _statusColor(g.status)),
                            ),
                          ),
                        ],
                      ),
                      if (g.attempts.isEmpty) ...[
                        const SizedBox(height: 8),
                        Text('No per-vital attempts recorded (cycle ${g.status}).',
                            style: AppTypography.inter(fontSize: 12, color: AppTheme.textSec)),
                      ] else ...[
                        const SizedBox(height: 10),
                        for (final a in g.attempts) ...[
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                    color: _statusColor(a['status'] as String? ?? 'success'),
                                    shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${a['vital']} · ${a['source']}',
                                        style: AppTypography.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                                    if ((a['error'] as String?)?.isNotEmpty == true)
                                      Text(a['error'] as String,
                                          style: AppTypography.inter(fontSize: 11, color: AppTheme.textSec)),
                                  ],
                                ),
                              ),
                              Text(a['status'] as String? ?? 'success',
                                  style: AppTypography.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _statusColor(a['status'] as String? ?? 'success'))),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            const FooterSpacer(),
          ],
        ),
      ),
    );
  }
}
