import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/ble_provider.dart';
import '../../../services/supabase_service.dart';
import '../../../services/unit_prefs.dart';
import '../../../services/health_engine/cycle_engine.dart';
import '../../../services/health_engine/health_engine.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/formatters.dart';
import '../../../widgets/app_typography.dart';
import 'home_card_shared.dart';
import 'home_insight_cards.dart';
import 'home_painters.dart';
import 'home_vitals_cards.dart';
// ── Compact health card widgets ──────────────────────────────────────────────

class CompactHealthCard extends StatelessWidget {
  final String title;
  final Color orbColor;
  final bool orbOnRight;
  final VoidCallback? onTap;
  final Widget child;
  final bool expanded;
  // When set, replaces the default radial orb glow with this gradient — used
  // by cards (e.g. Temperature) that need a directional fade instead.
  final Gradient? overlayGradient;

  const CompactHealthCard({
    super.key,
    required this.title,
    required this.orbColor,
    required this.child,
    this.orbOnRight = true,
    this.onTap,
    this.expanded = false,
    this.overlayGradient,
  });

  @override
  Widget build(BuildContext context) {
    // Glass per DESIGN.md: rgba(255,255,255,0.06) bg, 0.09 border, blur 28, radius 20
    return ShrinkButton(
      onTap: onTap,
      child: Container(
        height: expanded ? 240 : 160,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: AppTheme.glassCard,
          border: Border.all(
            color: AppTheme.glassBorder,
            width: 0.5,
          ),
        ),
        child: Stack(
          children: [
            if (overlayGradient != null)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: overlayGradient),
                ),
              )
            else
              Positioned(
                top: -40,
                left: orbOnRight ? null : -40,
                right: orbOnRight ? -40 : null,
                child: BlurOrb(
                  color: orbColor,
                  size: 220,
                  alpha: 0.35,
                  compact: true,
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: inter(
                            14,
                            weight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.95),
                            letterSpacing: -0.01,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.06),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                            width: 0.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white70,
                          size: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 0.5,
                    width: double.infinity,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CompactWomensHealthCard extends StatefulWidget {
  final VoidCallback? onTap;
  final bool expanded;
  const CompactWomensHealthCard({
    super.key,this.onTap, this.expanded = false});

  @override
  State<CompactWomensHealthCard> createState() =>
      CompactWomensHealthCardState();
}

class CompactWomensHealthCardState extends State<CompactWomensHealthCard> {
  int _cycleDay = 0;
  int _cycleLength = 28;
  int _periodLen = 5;

  @override
  void initState() {
    super.initState();
    _loadCycle();
  }

  Future<void> _loadCycle() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return;
      final rows = await SupabaseService.getCycles(user.id);
      if (rows.isEmpty || !mounted) return;
      final row = rows.first;
      final periodStart = DateTime.parse(row['period_start'] as String);
      final cycleLength = (row['cycle_length'] as num? ?? 28).toInt();
      final periodLength = (row['period_length'] as num? ?? 5).toInt();
      final day = CycleEngine.cycleDay(periodStart, DateTime.now());
      setState(() {
        _cycleDay = day.clamp(1, cycleLength);
        _cycleLength = cycleLength;
        _periodLen = periodLength;
      });
      if (kDebugMode) {
        debugPrint(
          'DEBUG: Loaded cycle day: $_cycleDay, cycleLength: $_cycleLength, periodLength: $_periodLen',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Error loading cycle data in compact card: $e\n$stackTrace');
    }
  }

  String get _phaseName => CycleEngine.phaseName(_cycleDay, _periodLen, _cycleLength);

  @override
  Widget build(BuildContext context) {
    if (widget.expanded) {
      final daysLeft = (_cycleLength - _cycleDay + 1).clamp(1, _cycleLength);
      return FigmaExpandedCard(
        orbColor: AppTheme.womenColor,
        height: 158,
        icon: Icons.woman,
        title: 'CYCLE',
        status: _cycleDay > 0 ? _phaseName : 'No data',
        value: figmaValue(_cycleDay > 0 ? 'Day $_cycleDay' : 'Day --'),
        chart: CyclePhaseBar(
          cycleDay: _cycleDay,
          cycleLength: _cycleLength,
          periodLen: _periodLen,
        ),
        footnoteLead: _cycleDay > 0
            ? 'Next period in $daysLeft days'
            : 'No data',
        footnoteRest: _cycleDay > 0
            ? ' · ${_phaseName.toLowerCase()} phase'
            : '',
        onTap: widget.onTap,
      );
    }
    return CompactHealthCard(
      title: 'Women\'s Health',
      orbColor: AppTheme.womenColor.withValues(alpha: 0.45),
      orbOnRight: true,
      expanded: widget.expanded,
      onTap: widget.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _cycleDay > 0 ? 'Day $_cycleDay' : 'Day --',
            style: AppTypography.inter(
              fontSize: 34,
              fontWeight: FontWeight.w200,
              color: Colors.white.withValues(alpha: 0.98),
              letterSpacing: -0.005,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _phaseName,
            style: inter(
              12,
              weight: FontWeight.w500,
              color: const Color(0xFFE8867F),
              letterSpacing: -0.005,
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
({int pLen, int fol, int ov, int lut}) _demoFlexes(int cLen, int pLen) => CycleEngine.flexes(cLen, pLen);

class CompactBloodPressureCard extends StatelessWidget {
  final VoidCallback? onTap;
  final bool expanded;
  const CompactBloodPressureCard({
    super.key,this.onTap, this.expanded = false});

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final sbp = ble.latestBpSbp;
    final dbp = ble.latestBpDbp;
    final hasData = sbp > 0 && dbp > 0;

    if (expanded) {
      return FigmaExpandedCard(
        orbColor: AppTheme.bpColor,
        height: 161,
        icon: Icons.water_drop,
        title: 'BLOOD PRESSURE',
        status: hasData ? HealthEngine.instance.assessBloodPressure(sbp, dbp).label : 'No data',
        value: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            figmaValue(hasData ? '$sbp' : '--'),
            const SizedBox(width: 3),
            figmaUnit(hasData ? '/$dbp' : '/--'),
          ],
        ),
        chart: CustomPaint(
          painter: BpChartPainter(sbp: sbp, dbp: dbp),
          child: const SizedBox.expand(),
        ),
        footnoteLead: hasData ? '$sbp/$dbp mmHg' : 'No data',
        footnoteRest: hasData ? ' · latest reading' : '',
        onTap: onTap,
      );
    }

    return CompactHealthCard(
      title: 'Blood Pressure',
      orbColor: AppTheme.bpColor.withValues(alpha: 0.45),
      expanded: expanded,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                hasData ? '$sbp' : '--',
                style: AppTypography.inter(
                  fontSize: 34,
                  fontWeight: FontWeight.w200,
                  color: Colors.white.withValues(alpha: 0.98),
                  letterSpacing: -0.005,
                ),
              ),
              Text(
                hasData ? '/$dbp' : '/--',
                style: AppTypography.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w300,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            HealthEngine.instance.assessBloodPressure(sbp, dbp).label,
            style: inter(
              12,
              weight: FontWeight.w500,
              color: HealthEngine.instance.assessBloodPressure(sbp, dbp).color,
              letterSpacing: -0.005,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Temperature card ──────────────────────────────────────────────────────────
// Diagonal glass fade — warm #F5F0E2 highlight top-right easing through the
// spec's 6% base tone, down to a black-tinted bottom-left corner.

class TemperatureCard extends StatefulWidget {
  final double tempC;
  final bool connected;
  final VoidCallback? onTap;
  final bool expanded;

  const TemperatureCard({
    super.key,
    required this.tempC,
    required this.connected,
    this.onTap,
    this.expanded = false,
  });

  @override
  State<TemperatureCard> createState() => TemperatureCardState();
}

class TemperatureCardState extends State<TemperatureCard> {
  TempUnit _tempUnit = TempUnit.celsius;

  @override
  void initState() {
    super.initState();
    _loadTempUnit();
  }

  @override
  void didUpdateWidget(covariant TemperatureCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadTempUnit();
  }

  Future<void> _loadTempUnit() async {
    final unit = await UnitPrefs.loadTempUnit();
    if (mounted && _tempUnit != unit) {
      setState(() => _tempUnit = unit);
    }
  }

  // Display-only conversion — tempC stays in Celsius (the ring's native unit);
  // only the number shown changes with the Temperature Unit setting. Mirrors
  // TemperatureScreen's own _disp()/_unitLabel logic exactly.
  double get _dispTemp => _tempUnit == TempUnit.fahrenheit
      ? UnitPrefs.celsiusToFahrenheit(widget.tempC)
      : widget.tempC;

  String get _unitLabel => _tempUnit == TempUnit.fahrenheit ? '°F' : '°C';

  @override
  Widget build(BuildContext context) {
    _loadTempUnit();
    final hasData = widget.tempC > 0;

    return CompactHealthCard(
      title: 'Temperature',
      orbColor: AppTheme.tempColor,
      expanded: widget.expanded,
      onTap: widget.onTap,
      overlayGradient: const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        stops: [0.0, 0.5, 1.0],
        colors: [
          Color(0x26F5F0E2), // brighter warm highlight at the top-right corner
          Color(0x0FF5F0E2), // spec: #F5F0E2 @ 6%
          Color(0x59000000), // black touch fading in at the bottom-left
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    hasData ? _dispTemp.fixed2() : '--',
                    style: AppTypography.inter(
                      fontSize: 34,
                      fontWeight: FontWeight.w200,
                      color: Colors.white.withValues(alpha: 0.98),
                      letterSpacing: -0.005,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 3),
              Text(
                _unitLabel,
                style: AppTypography.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w300,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            HealthEngine.instance.assessTemperature(widget.tempC).label == '--' ? 'No data' : HealthEngine.instance.assessTemperature(widget.tempC).label, // status thresholds stay in Celsius (the canonical unit)
            style: inter(
              12,
              weight: FontWeight.w500,
              color: hasData ? AppTheme.tempColor : AppTheme.textSec,
              letterSpacing: -0.005,
            ),
          ),
        ],
      ),
    );
  }
}

