import 'package:flutter/material.dart';
import '../../../models/womens_health_models.dart';
import '../../../providers/ble_provider.dart';
import '../../../services/health_engine/cycle_engine.dart';
import '../../../services/health_engine/health_engine.dart';
import '../../../services/incident_service.dart';
import '../../../services/supabase_service.dart';
import '../../../services/womens_health_prediction_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/formatters.dart';
import '../../../widgets/app_typography.dart';
import 'home_card_shared.dart';
import 'home_insight_cards.dart';
import 'home_painters.dart';
// ── Glass card foundation ─────────────────────────────────────────────────────

class HomeGlassCard extends StatelessWidget {
  final Color orbColor;
  final Widget child;
  final double? height;
  final VoidCallback? onTap;
  final bool orbOnRight;
  final bool orbAtTop;
  final double? orbOffset;
  final double orbAlpha;
  final double orbSize;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;
  final Widget? backgroundOverride;

  const HomeGlassCard({
    super.key,
    required this.orbColor,
    required this.child,
    this.height,
    this.onTap,
    this.orbOnRight = true,
    this.orbAtTop = false,
    this.orbOffset,
    this.orbAlpha = 0.34,
    this.orbSize = 240,
    this.padding,
    this.borderColor,
    this.backgroundOverride,
  });

  @override
  Widget build(BuildContext context) {
    // Small fixed-height cards get a large orb so the ambient glow covers
    // ~90% of the card; full-width auto-height cards keep a corner glow.
    final double resolvedOrbOffset = orbOffset ?? (height == null ? -78 : -56);
    final content = Padding(
      padding: padding ?? const EdgeInsets.all(16),
      child: child,
    );

    // ImageFiltered blur restored for visual quality. Clip +
    // (inside _blurOrb) keep corners clean and limit re-rasterization on scroll.
    return ShrinkButton(
      onTap: onTap,
      child: Container(
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: kCardBg,
          border: Border.all(color: borderColor ?? kCardBorder, width: 0.5),
        ),
        child: Stack(
          fit: height != null ? StackFit.expand : StackFit.loose,
          children: [
            if (backgroundOverride != null)
              Positioned.fill(child: backgroundOverride!)
            else
              Positioned(
                top: orbAtTop ? resolvedOrbOffset : null,
                bottom: orbAtTop ? null : resolvedOrbOffset,
                right: orbOnRight ? resolvedOrbOffset : null,
                left: orbOnRight ? null : resolvedOrbOffset,
                child: BlurOrb(
                  color: orbColor,
                  size: orbSize,
                  alpha: orbAlpha,
                ),
              ),
            // Fixed height: Positioned.fill gives Column tight constraints so Spacer works.
            // Auto height: plain Padding lets Stack size to content (and still
            // expands when the parent imposes a tight height via stretch).
            if (height != null) Positioned.fill(child: content) else content,
          ],
        ),
      ),
    );
  }
}

// ── Figma-style expanded card (new app page frames 478–484) ───────────────────
// Expanded cards follow the new app page anatomy: icon + mono title + chevron,
// status/value row, 36px chart area, divider, footnote.

const _kFigmaBorder = Color(0x1FFFFFFF); // rgba(255,255,255,0.12)
const _kFigmaLabel = AppTheme.white45; // rgba(255,255,255,0.45)
const _kFigmaLabelStrong = AppTheme.white60; // rgba(255,255,255,0.6)
const _kFigmaStageDeep = Color(0xFF5B7BB3);
const _kFigmaStageRem = Color(0xFFA088E0);
const _kFigmaLightBar = Color(0x59FFFFFF); // rgba(255,255,255,0.35)
const kFigmaStressLow = Color(0xFF8FE5B5);
const kFigmaStressHigh = Color(0xFFE88FA0);

TextStyle _figmaMono(
  double size, {
  Color color = _kFigmaLabel,
  FontWeight weight = FontWeight.w500,
  double tracking = 1.32,
}) => AppTypography.inter(
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: tracking,
  height: 1,
);

TextStyle _figmaFraunces(double size) => AppTypography.inter(
  fontSize: size,
  fontWeight: FontWeight.w300,
  color: Colors.white.withValues(alpha: 0.95),
  letterSpacing: 1.44,
  height: 1,
);

TextStyle _figmaStatusStyle() => AppTypography.inter(
  fontSize: 14,
  fontWeight: FontWeight.w500,
  color: Colors.white.withValues(alpha: 0.95),
  height: 1,
);

Text figmaValue(String s) => Text(s, style: _figmaFraunces(24));

Text figmaUnit(String s) => Text(s, style: _figmaMono(11, tracking: 0.66));

/// Shared expanded-card layout from the new app page: header row (13px icon,
/// uppercase mono title, 16px chevron), 24px status/value row, 36px chart,
/// 1px divider and a two-tone mono footnote.
class FigmaExpandedCard extends StatelessWidget {
  final Color orbColor;
  final double height;
  final IconData icon;
  final String title;
  final String status;
  final Widget value;
  final Widget chart;
  final String footnoteLead;
  final String footnoteRest;
  final VoidCallback? onTap;

  const FigmaExpandedCard({
    super.key,
    required this.orbColor,
    required this.height,
    required this.icon,
    required this.title,
    required this.status,
    required this.value,
    required this.chart,
    required this.footnoteLead,
    required this.footnoteRest,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return HomeGlassCard(
      orbColor: orbColor,
      height: height,
      orbAlpha: 0.25,
      orbSize: 220,
      borderColor: _kFigmaBorder,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: Colors.white.withValues(alpha: 0.6)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: _figmaMono(11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 16, color: _kFigmaLabel),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  status,
                  style: _figmaStatusStyle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              value,
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(height: 36, width: double.infinity, child: chart),
          const SizedBox(height: 10),
          Container(height: 1, width: double.infinity, color: _kFigmaBorder),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              style: _figmaMono(11, tracking: 0.44),
              children: [
                TextSpan(
                  text: footnoteLead,
                  style: const TextStyle(
                    color: _kFigmaLabelStrong,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(text: footnoteRest),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Sleep stage bar — deep / REM / light segments with the design's 4px gap
/// and rounded leading/trailing corners.  Falls back to equal thirds when no
/// stage data has arrived yet.
class SleepStageBar extends StatelessWidget {
  final int deepSecs;
  final int lightSecs;
  final int remSecs;

  const SleepStageBar({
    super.key,
    required this.deepSecs,
    required this.lightSecs,
    required this.remSecs,
  });

  @override
  Widget build(BuildContext context) {
    final total = deepSecs + lightSecs + remSecs;
    int flex(int v) =>
        total <= 0 ? 1 : (v / total * 1000).round().clamp(1, 1000).toInt();
    return Row(
      children: [
        Expanded(
          flex: flex(deepSecs),
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: _kFigmaStageDeep,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(4),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          flex: flex(remSecs),
          child: Container(height: 8, color: _kFigmaStageRem),
        ),
        const SizedBox(width: 4),
        Expanded(
          flex: flex(lightSecs),
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: _kFigmaLightBar,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Activity progress bar — 8px track with a rounded 35%-white fill.
class ActivityProgressBar extends StatelessWidget {
  final double fraction;
  const ActivityProgressBar({
    super.key,required this.fraction});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 8,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: fraction.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: _kFigmaLightBar,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

/// Cycle phase bar — menstrual / follicular / ovulating / luteal segments
/// with a day marker above the bar.
class CyclePhaseBar extends StatelessWidget {
  final int cycleDay;
  final int cycleLength;
  final int periodLen;

  const CyclePhaseBar({
    super.key,
    required this.cycleDay,
    required this.cycleLength,
    required this.periodLen,
  });

  @override
  Widget build(BuildContext context) {
    final len = cycleLength > 0 ? cycleLength : 28;
    final f = CycleEngine.flexes(cycleLength, periodLen);
    final day = cycleDay.clamp(1, len).toInt();

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Row(
              children: [
                Expanded(
                  flex: f.pLen,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: kFigmaStressHigh,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  flex: f.fol,
                  child: Container(height: 8, color: _kFigmaLightBar),
                ),
                const SizedBox(width: 4),
                Expanded(
                  flex: f.ov,
                  child: Container(height: 8, color: kFigmaStressLow),
                ),
                const SizedBox(width: 4),
                Expanded(
                  flex: f.lut,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: _kFigmaStageDeep,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: (constraints.maxWidth * ((day - 0.5) / len)) - 5,
              top: -4,
              child: Icon(
                Icons.arrow_drop_down,
                size: 12,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ignore: unused_element
String _demoPhase(int day, int pLen, int cLen) => CycleEngine.phaseName(day, pLen, cLen);

// ── Chevron button (glass) ────────────────────────────────────────────────────

Widget chevron() => Container(
  width: 26,
  height: 26,
  decoration: BoxDecoration(
    shape: BoxShape.circle,
    color: Colors.white.withValues(alpha: 0.08),
    border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
  ),
  child: const Icon(
    Icons.chevron_right_rounded,
    color: Colors.white54,
    size: 16,
  ),
);

// ── Mini card (compact mode) ───────────────────────────────────────────────────

class MiniCard extends StatelessWidget {
  final String label;
  final String? value;
  final String? sub;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;
  final bool expanded;

  const MiniCard({
    super.key,
    required this.label,
    this.value,
    this.sub,
    required this.color,
    required this.icon,
    this.onTap,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return HomeGlassCard(
      orbColor: color,
      height: expanded ? 195 : 130,
      orbAlpha: 0.25,
      orbSize: 180,
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 14, color: color),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white54,
                  size: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: inter(
              10,
              weight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          if (value != null) ...[
            Text(value!, style: inter(20, weight: FontWeight.w600)),
            if (sub != null) Text(sub!, style: inter(10, color: AppTheme.textSec)),
          ],
          if (expanded) const Spacer(),
        ],
      ),
    );
  }
}

class WomensHealthMiniCard extends StatefulWidget {
  final BleProvider ble;
  final bool expanded;
  final VoidCallback onTap;

  const WomensHealthMiniCard({
    super.key,
    required this.ble,
    required this.expanded,
    required this.onTap,
  });

  @override
  State<WomensHealthMiniCard> createState() => WomensHealthMiniCardState();
}

class WomensHealthMiniCardState extends State<WomensHealthMiniCard> {
  String _value = 'Day --';
  String _sub = '---';
  // ignore: unused_field
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = SupabaseService.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final cycles = await SupabaseService.getCycles(user.id);
      if (cycles.isNotEmpty) {
        final latest = cycles.first;
        final startStr = latest['period_start'] as String;
        final start = DateTime.parse(startStr);
        final now = DateTime.now();
        final startDt = DateTime(start.year, start.month, start.day);
        final nowDt = DateTime(now.year, now.month, now.day);
        final day = CycleEngine.cycleDay(startDt, nowDt);

        final cycleLen = latest['cycle_length'] as int;

        // Build HealthMetrics using BleProvider values
        // Normalized roughly 0-100
        final metrics = HealthMetrics(
          temperature:
              (widget.ble.todayAvgSpo2 > 0
                      ? widget.ble.todayAvgSpo2.toDouble()
                      : 50.0)
                  .clamp(0, 100),
          hrv: (widget.ble.todayAvgHrv.toDouble()).clamp(0, 100),
          heartRate: (widget.ble.todayAvgHr.toDouble()).clamp(0, 100),
          sleepQuality: (widget.ble.todaySleepScore.toDouble()).clamp(0, 100),
          stress: (widget.ble.todayAvgStress.toDouble()).clamp(0, 100),
          activityLevel: ((widget.ble.todaySteps / 10000.0) * 100.0).clamp(
            0,
            100,
          ),
        );

        final service = WomenHealthPredictionService();
        final result = service.predictCycle(
          lastMenstrualPeriod: startDt,
          averageCycleLength: cycleLen,
          metrics: metrics,
          hasHistory: true,
        );

        final phase = result.estimatedPhase.displayName.replaceAll(
          ' Phase',
          '',
        );
        final score = result.confidenceScore.round();

        if (mounted) {
          setState(() {
            _value = 'Day $day • $phase';
            _sub = '$score% AWHE Confidence';
          });
        }
      } else {
        final metrics = HealthMetrics(
          temperature:
              (widget.ble.todayAvgSpo2 > 0
                      ? widget.ble.todayAvgSpo2.toDouble()
                      : 50.0)
                  .clamp(0, 100),
          hrv: (widget.ble.todayAvgHrv.toDouble()).clamp(0, 100),
          heartRate: (widget.ble.todayAvgHr.toDouble()).clamp(0, 100),
          sleepQuality: (widget.ble.todaySleepScore.toDouble()).clamp(0, 100),
          stress: (widget.ble.todayAvgStress.toDouble()).clamp(0, 100),
          activityLevel: ((widget.ble.todaySteps / 10000.0) * 100.0).clamp(
            0,
            100,
          ),
        );
        final service = WomenHealthPredictionService();
        final result = service.predictCycle(
          lastMenstrualPeriod: null,
          averageCycleLength: 28,
          metrics: metrics,
          hasHistory: false,
        );
        final phase = result.estimatedPhase.displayName.replaceAll(
          ' Phase',
          '',
        );
        final score = result.confidenceScore.round();
        if (mounted) {
          setState(() {
            _value = phase;
            _sub = '$score% AWHE Vitals Only';
          });
        }
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'home_vitals_cards',
        error: e,
        stackTrace: st,
        customMessage: 'load womens health prediction failed',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MiniCard(
      label: "Women's Health",
      value: _value,
      sub: _sub,
      color: AppTheme.womenColor,
      icon: Icons.woman,
      expanded: widget.expanded,
      onTap: widget.onTap,
    );
  }
}

// ── Generic half-width metric card ────────────────────────────────────────────

class HomeCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final String status;
  final Color statusColor;
  final Color orbColor;
  final List<double> sparkData;
  final bool connected;
  final VoidCallback? onTap;
  final bool expanded;

  const HomeCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.status,
    required this.statusColor,
    required this.orbColor,
    required this.sparkData,
    required this.connected,
    this.onTap,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return HomeGlassCard(
      orbColor: orbColor,
      height: expanded ? 240 : 160,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: inter(
                    13,
                    weight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              chevron(),
            ],
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value,
                          style: AppTypography.inter(
                            fontSize: 30,
                            fontWeight: FontWeight.w200,
                            color: Colors.white.withValues(alpha: 0.95),
                          ),
                        ),
                      ),
                    ),
                    if (unit.isNotEmpty) ...[
                      const SizedBox(width: 3),
                      Text(
                        unit,
                        style: inter(
                          11,
                          weight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 28,
                  child: connected
                      ? CustomPaint(painter: SparkPainter(orbColor, sparkData))
                      : const ConnectHint(compact: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            status,
            style: inter(11, color: statusColor, weight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Full-width Stress card ────────────────────────────────────────────────────

class StressCard extends StatelessWidget {
  final int value;
  final int avgStress;
  final int minStress;
  final int maxStress;
  final int hrv;
  final bool connected;
  final VoidCallback? onTap;
  final bool expanded;

  static const _barData = [
    0.30,
    0.45,
    0.38,
    0.52,
    0.48,
    0.42,
    0.55,
    0.38,
    0.47,
    0.35,
    0.60,
    0.55,
    0.48,
    0.40,
    0.35,
    0.42,
    0.50,
    0.45,
    0.38,
    0.30,
    0.40,
    0.35,
    0.28,
    0.32,
  ];

  static final _bars40 = interpolate(_barData, 40);

  const StressCard({
    super.key,
    required this.value,
    required this.avgStress,
    required this.minStress,
    required this.maxStress,
    required this.connected,
    this.hrv = 0,
    this.onTap,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final status = HealthEngine.instance.assessStress(value).label == '--' ? 'No data' : HealthEngine.instance.assessStress(value).label;
    final color = HealthEngine.instance.assessStress(value).color;

    if (expanded) {
      return FigmaExpandedCard(
        orbColor: AppTheme.stressColor,
        height: 158,
        icon: Icons.monitor_heart,
        title: 'STRESS',
        status: value > 0 ? status : 'No data',
        value: figmaValue(value > 0 ? '$value' : '--'),
        chart: CustomPaint(
          painter: StressMiniBarsPainter(_bars40),
          child: const SizedBox.expand(),
        ),
        footnoteLead: avgStress > 0 ? 'Avg $avgStress' : 'No data',
        footnoteRest: maxStress > 0 ? ' · Range $minStress-$maxStress' : '',
        onTap: onTap,
      );
    }

    // Auto-height: fixed pixel heights clip on denser fonts / text scale /
    // narrow phones. Content defines the card height instead.  Expanded cards
    // switch to the fixed 1.5× height (240 = 1.5 × the standard 160 card).
    return HomeGlassCard(
      orbColor: AppTheme.stressColor,
      orbOnRight: false,
      orbOffset: -78,
      height: expanded ? 240 : null,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Stress',
                  style: inter(
                    15,
                    weight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              chevron(),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value > 0 ? '$value' : '--',
                style: AppTypography.inter(
                  fontSize: 36,
                  fontWeight: FontWeight.w300,
                  height: 1.1,
                  color: Colors.white.withValues(alpha: 0.95),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  status,
                  style: inter(
                    13,
                    color: color,
                    weight: FontWeight.w500,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 24,
            width: double.infinity,
            child: connected
                ? CustomPaint(painter: BarChartPainter(AppTheme.stressColor, _barData))
                : const ConnectHint(),
          ),
          const SizedBox(height: 8),
          Container(
            height: 1,
            width: double.infinity,
            color: Colors.white.withValues(alpha: 0.08),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: StressStatColumn(
                  label: 'Daily Average',
                  value: avgStress > 0 ? '$avgStress' : '--',
                  status: HealthEngine.instance.assessStress(avgStress).label == '--' ? 'No data' : HealthEngine.instance.assessStress(avgStress).label,
                ),
              ),
              Container(
                width: 1,
                height: 48,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              Expanded(
                child: StressStatColumn(
                  label: 'Daily Range',
                  value: maxStress > 0 ? '$minStress-$maxStress' : '--',
                  status: HealthEngine.instance.assessStress(maxStress).label == '--' ? 'No data' : HealthEngine.instance.assessStress(maxStress).label,
                ),
              ),
            ],
          ),
          if (expanded) const Spacer(),
        ],
      ),
    );
  }
}

/// Bottom stat cell for the Stress card — keeps label/value/status from
/// overflowing by using explicit line heights and ellipsis.
class StressStatColumn extends StatelessWidget {
  final String label;
  final String value;
  final String status;

  const StressStatColumn({
    super.key,
    required this.label,
    required this.value,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: inter(
            11,
            color: Colors.white.withValues(alpha: 0.4),
            weight: FontWeight.w500,
            height: 1.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTypography.inter(
            fontSize: 22,
            fontWeight: FontWeight.w300,
            height: 1.15,
            color: Colors.white.withValues(alpha: 0.95),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          status,
          style: inter(
            11,
            color: Colors.white.withValues(alpha: 0.5),
            weight: FontWeight.w400,
            height: 1.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
// ── Activity score card ────────────────────────────────────────────────────────

class ActivityScoreCard extends StatelessWidget {
  final int score;
  final bool hasData;
  final int steps;
  final int calories;
  final double distanceM;
  final VoidCallback? onTap;
  final bool expanded;

  const ActivityScoreCard({
    super.key,
    required this.score,
    required this.hasData,
    this.steps = 0,
    this.calories = 0,
    this.distanceM = 0,
    this.onTap,
    this.expanded = false,
  });

  String get _distanceLabel {
    if (distanceM <= 0) return 'No distance';
    if (distanceM >= 1000) {
      return '${(distanceM / 1000).fixed2()} km';
    }
    return '${distanceM.round()} m';
  }

  @override
  Widget build(BuildContext context) {
    if (expanded) {
      final activeMin = steps ~/ 100;
      final showData = hasData && (steps > 0 || calories > 0 || distanceM > 0);
      return FigmaExpandedCard(
        orbColor: AppTheme.focus,
        height: 158,
        icon: Icons.directions_walk,
        title: 'ACTIVITY',
        status: showData
            ? HealthEngine.instance.activityLabel(score)
            : 'No data',
        value: showData
            ? Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  figmaValue('$score'),
                  const SizedBox(width: 3),
                  figmaUnit('pts'),
                ],
              )
            : figmaValue('--'),
        chart: ActivityProgressBar(
          fraction: (steps / 10000.0).clamp(0.0, 1.0),
        ),
        footnoteLead: steps > 0
            ? '${formatInt(steps)} / 10K steps'
            : 'No activity',
        footnoteRest: distanceM > 0
            ? ' · $_distanceLabel · $activeMin min active'
            : '',
        onTap: onTap,
      );
    }
    // No fixed height — pairs with AlarmCard via IntrinsicHeight so both
    // grow together when text scale / font metrics need more room. Expanded
    // cards switch to the fixed 1.5× height (240 = 1.5 × the standard 160).
    return HomeGlassCard(
      orbColor: AppTheme.focus,
      orbOnRight: true,
      orbAlpha: 0.25,
      height: expanded ? 240 : null,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Activity',
                  style: inter(
                    15,
                    weight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              chevron(),
            ],
          ),
          const SizedBox(height: 10),
          Divider(
            color: Colors.white.withValues(alpha: 0.08),
            height: 1,
            thickness: 0.5,
          ),
          // Spacer only expands after IntrinsicHeight assigns a shared height
          // (contributes 0 to intrinsic measurement).
          const Spacer(),
          Text(
            hasData ? '$score' : '--',
            style: AppTypography.inter(
              fontSize: 40,
              fontWeight: FontWeight.w300,
              height: 1.1,
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            hasData && distanceM > 0
                ? _distanceLabel
                : HealthEngine.instance.activityLabel(score),
            style: inter(
              13,
              weight: FontWeight.w500,
              color: AppTheme.focus,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

