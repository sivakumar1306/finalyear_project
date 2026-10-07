import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/alarm_mode_provider.dart';
import '../../providers/ble_provider.dart';
import '../../providers/prayer_session_provider.dart';
import '../../theme/app_theme.dart';
import 'prayer_history_screen.dart';
import 'prayer_summary_screen.dart';
import '../../widgets/app_typography.dart';
import '../../utils/formatters.dart';

/// Live Prayer Session Tracker Screen featuring a magnificent Gold Orbiting Flow-State Orb,
/// centered digital timer & serenity status badge, and a bottom floating button that opens
/// the 13 live vitals & metrics drawer.
class PrayerSessionScreen extends StatefulWidget {
  const PrayerSessionScreen({super.key});

  @override
  State<PrayerSessionScreen> createState() => _PrayerSessionScreenState();
}

class _PrayerSessionScreenState extends State<PrayerSessionScreen> with SingleTickerProviderStateMixin {
  late AnimationController _orbController;

  @override
  void initState() {
    super.initState();
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ble = context.read<BleProvider>();
      context.read<PrayerSessionProvider>().startSession(ble);
    });
  }

  @override
  void dispose() {
    _orbController.dispose();
    super.dispose();
  }

  void _endSession() {
    final session = context.read<PrayerSessionProvider>();
    final duration = session.elapsedSeconds;
    final avgHr = session.avgHeartRate;
    final avgHrv = session.avgHrv;
    final peakCalm = session.peakCalmness;
    final rating = session.calmnessRating;

    session.endSession();
    context.read<AlarmModeProvider>().setMode(PhoneMode.base);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PrayerSummaryScreen(
          durationSeconds: duration,
          avgHr: avgHr,
          avgHrv: avgHrv,
          peakCalmness: peakCalm,
          rating: rating,
        ),
      ),
    );
  }

  void _openVitalsDrawer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _VitalsDrawerSheet(),
    );
  }

  String _formatTime(int totalSeconds) {
    final hrs = totalSeconds ~/ 3600;
    final mins = (totalSeconds % 3600) ~/ 60;
    final secs = totalSeconds % 60;
    if (hrs > 0) {
      return '${hrs.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PrayerSessionProvider>();
    final calmness = session.calmnessScore;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.gold.withValues(alpha: 0.6)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.do_not_disturb_on_rounded, color: AppTheme.gold, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'Meditation DND Active',
                    style: AppTypography.inter(
                      color: AppTheme.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PrayerHistoryScreen()),
              );
            },
            icon: const Icon(Icons.show_chart_rounded, color: AppTheme.gold),
            tooltip: 'Prayer History & Trends',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final responsiveOrbSize = (MediaQuery.of(context).size.width * 0.78).clamp(260.0, 360.0);

          return Stack(
            children: [
              // ── Centered Pure 3D Gold Particle Orb & Status Layout ─────────
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(flex: 1),

                      // Responsive Clean 3D Gold Particle Cloud Orb (No inner icon or circle)
                      SizedBox(
                        width: responsiveOrbSize,
                        height: responsiveOrbSize,
                        child: AnimatedBuilder(
                          animation: _orbController,
                          builder: (context, child) {
                            return CustomPaint(
                              painter: _GoldFlowStateOrbPainter(_orbController.value),
                            );
                          },
                        ),
                      ),

                  const SizedBox(height: 36),

                  // Digital Timer below Orb
                  Text(
                    _formatTime(session.elapsedSeconds),
                    style: AppTypography.inter(
                      color: Colors.white,
                      fontSize: 44,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Serenity & Relaxation Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.gold.withValues(alpha: 0.5)),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.gold.withValues(alpha: 0.2),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.gold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$calmness% • ${session.calmnessRating}',
                          style: AppTypography.inter(
                            color: AppTheme.gold,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(flex: 2),

                  // ── End Prayer Session Button ─────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _endSession,
                      icon: const Icon(Icons.stop_circle_rounded, color: Colors.redAccent, size: 20),
                      label: Text(
                        'End Meditation',
                        style: AppTypography.inter(
                          color: Colors.redAccent,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0x44FF5252)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 80), // Space for floating bottom drawer button
                ],
              ),
            ),
          ),

          // ── Bottom Floating "Show Vitals & Metrics" Button ────────────────
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _openVitalsDrawer,
                icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 24),
                label: Text(
                  'Show 13 Vitals & Metrics',
                  style: AppTypography.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.gold,
                  foregroundColor: Colors.black,
                  elevation: 8,
                  shadowColor: AppTheme.gold.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  ),
);
  }
}

/// Custom Painter rendering a 3D Energy Orb composed of thousands of luminous gold particles.
/// Uses exact App Gold palette (AppTheme.gold), continuous seamless animation formulas (no resets/jumps),
/// ultra-slow meditative particle drift, and individual particle radial compression & expansion.
class _GoldFlowStateOrbPainter extends CustomPainter {
  final double animationValue; // 0.0 to 1.0 (continuous controller)

  static const int _numParticles = 420;
  static List<_OrbParticle>? _cachedParticles;

  _GoldFlowStateOrbPainter(this.animationValue) {
    _cachedParticles ??= _generateFibonacciParticles(_numParticles);
  }

  static List<_OrbParticle> _generateFibonacciParticles(int count) {
    final list = <_OrbParticle>[];
    final goldenRatio = (1.0 + math.sqrt(5.0)) / 2.0;

    for (int i = 0; i < count; i++) {
      final theta = 2.0 * math.pi * i / goldenRatio;
      final phi = math.acos(1.0 - 2.0 * (i + 0.5) / count);

      final nx = math.sin(phi) * math.cos(theta);
      final ny = math.sin(phi) * math.sin(theta);
      final nz = math.cos(phi);

      // App Theme Gold palette mapping
      final colorSeed = (i % 4);
      Color color;
      if (colorSeed == 0) {
        color = AppTheme.goldPale; // Champagne Gold highlight
      } else if (colorSeed == 1) {
        color = AppTheme.gold; // Exact App Gold (0xFFC9A86E)
      } else if (colorSeed == 2) {
        color = const Color(0xFFD6B57C); // Soft Warm Gold
      } else {
        color = AppTheme.goldDark; // Deep Warm Amber Gold
      }

      list.add(_OrbParticle(
        nx: nx,
        ny: ny,
        nz: nz,
        baseSize: 1.2 + (i % 3) * 0.7,
        color: color,
        phase: (i * 0.23) % (2.0 * math.pi),
        phase2: (i * 0.41) % (2.0 * math.pi),
      ));
    }
    return list;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // Continuous time variable (0.0 to 2*pi) — seamless, no wrap jumps!
    final t = animationValue * 2.0 * math.pi;

    // 1. Soft Volumetric App Gold Core Glow & Light Scattering
    final glowRadius = maxRadius * 0.85;
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          AppTheme.goldPale.withValues(alpha: 0.45), // Champagne Bloom
          AppTheme.gold.withValues(alpha: 0.32),            // App Gold Core
          AppTheme.goldDark.withValues(alpha: 0.16), // Outer Deep Warm Gold
          Colors.transparent,
        ],
        stops: const [0.0, 0.38, 0.72, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: glowRadius));
    canvas.drawCircle(center, glowRadius, glowPaint);

    // 2. Base Meditative Global Breathing Pulse
    final globalBreath = math.sin(t);
    final baseSphereRadius = maxRadius * 0.56 * (1.0 + 0.05 * globalBreath);

    // 3. Ultra-Slow 3D Rotation Angles & Magnetic Field Drift (Seamless Formulas)
    final rotY = t * 0.20;                            // Ultra-slow smooth rotation
    final rotX = math.sin(t * 0.5) * 0.25;
    final rotZ = math.cos(t * 0.3) * 0.20;

    final cosY = math.cos(rotY), sinY = math.sin(rotY);
    final cosX = math.cos(rotX), sinX = math.sin(rotX);
    final cosZ = math.cos(rotZ), sinZ = math.sin(rotZ);

    final particles = _cachedParticles!;
    final projectedList = <_ProjectedParticle>[];

    for (final p in particles) {
      // Individual Particle Compression & Expansion (breathing inward and outward)
      final particleBreath = math.sin(t * 0.8 + p.phase);
      final particleBreath2 = math.cos(t * 0.5 + p.phase2);
      final individualRadiusFactor = 1.0 + 0.14 * particleBreath + 0.06 * particleBreath2;
      final sphereRadius = baseSphereRadius * individualRadiusFactor;

      // Ultra-slow surface curl noise flow
      final flowAngle = (t * 0.12) + p.phase;
      final curlJitterX = 0.05 * math.sin(flowAngle * 2.0 + p.ny * 3.0);
      final curlJitterY = 0.05 * math.cos(flowAngle * 2.0 + p.nz * 3.0);
      final curlJitterZ = 0.05 * math.sin(flowAngle + p.nx * 3.0);

      double x = p.nx + curlJitterX;
      double y = p.ny + curlJitterY;
      double z = p.nz + curlJitterZ;

      final len = math.sqrt(x * x + y * y + z * z);
      x /= len; y /= len; z /= len;

      // 3D Rotation (Y -> X -> Z)
      final x1 = x * cosY + z * sinY;
      final y1 = y;
      final z1 = -x * sinY + z * cosY;

      final x2 = x1;
      final y2 = y1 * cosX - z1 * sinX;
      final z2 = y1 * sinX + z1 * cosX;

      final x3 = x2 * cosZ - y2 * sinZ;
      final y3 = x2 * sinZ + y2 * cosZ;
      final z3 = z2;

      // Perspective Projection
      final perspective = 1.0 / (1.25 - z3 * 0.35);
      final screenX = center.dx + x3 * sphereRadius * perspective;
      final screenY = center.dy + y3 * sphereRadius * perspective;

      final depthFactor = (z3 + 1.0) / 2.0;
      final alpha = (0.25 + 0.75 * depthFactor).clamp(0.0, 1.0);
      final drawSize = p.baseSize * perspective * (0.7 + 0.5 * depthFactor);

      projectedList.add(_ProjectedParticle(
        screenX: screenX,
        screenY: screenY,
        z: z3,
        size: drawSize,
        alpha: alpha,
        color: p.color,
      ));
    }

    // Depth Sort (draw back to front)
    projectedList.sort((a, b) => a.z.compareTo(b.z));

    final particlePaint = Paint()..style = PaintingStyle.fill;

    for (final p in projectedList) {
      particlePaint.color = p.color.withValues(alpha: p.alpha);
      canvas.drawCircle(Offset(p.screenX, p.screenY), p.size, particlePaint);

      // Bloom highlight for front-facing particles
      if (p.z > 0.3) {
        final glowAlpha = ((p.z - 0.3) / 0.7 * 0.40).clamp(0.0, 0.40);
        final bloomPaint = Paint()
          ..color = AppTheme.goldPale.withValues(alpha: glowAlpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
        canvas.drawCircle(Offset(p.screenX, p.screenY), p.size * 2.0, bloomPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GoldFlowStateOrbPainter oldDelegate) => true;
}

class _OrbParticle {
  final double nx, ny, nz;
  final double baseSize;
  final Color color;
  final double phase;
  final double phase2;

  _OrbParticle({
    required this.nx,
    required this.ny,
    required this.nz,
    required this.baseSize,
    required this.color,
    required this.phase,
    required this.phase2,
  });
}

class _ProjectedParticle {
  final double screenX;
  final double screenY;
  final double z;
  final double size;
  final double alpha;
  final Color color;

  _ProjectedParticle({
    required this.screenX,
    required this.screenY,
    required this.z,
    required this.size,
    required this.alpha,
    required this.color,
  });
}

/// Expandable Bottom Sheet Drawer presenting all 13 live sensor metrics during prayer.
class _VitalsDrawerSheet extends StatelessWidget {
  const _VitalsDrawerSheet();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PrayerSessionProvider>();
    final ble = context.watch<BleProvider>();
    final calmness = session.calmnessScore;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surfaceDeep,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: AppTheme.gold, width: 1.5)),
        ),
        child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white30,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '13 Live Sensor Metrics',
                  style: AppTypography.inter(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  ble.isConnected ? 'Ring Connected' : 'Simulated Data',
                  style: AppTypography.inter(
                    color: ble.isConnected ? AppTheme.gold : AppTheme.textSec,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Divider(color: AppTheme.white10, height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.7,
                    children: [
                      _VitalCard(
                        title: '1. Heart Rate',
                        value: ble.todayAvgHr > 0 ? '${ble.todayAvgHr} bpm' : '--',
                        icon: Icons.favorite_rounded,
                        color: Colors.redAccent,
                      ),
                      _VitalCard(
                        title: '2. HRV',
                        value: ble.todayAvgHrv > 0 ? '${ble.todayAvgHrv} ms' : '--',
                        icon: Icons.favorite_border_rounded,
                        color: Colors.lightBlueAccent,
                      ),
                      _VitalCard(
                        title: '3. Blood Oxygen',
                        value: ble.todayAvgSpo2 > 0 ? '${ble.todayAvgSpo2}%' : '--',
                        icon: Icons.water_drop_rounded,
                        color: Colors.cyanAccent,
                      ),
                      _VitalCard(
                        title: '4. BP Systolic',
                        value: ble.latestBpSbp > 0 ? '${ble.latestBpSbp} mmHg' : '--',
                        icon: Icons.speed_rounded,
                        color: Colors.orangeAccent,
                      ),
                      _VitalCard(
                        title: '5. BP Diastolic',
                        value: ble.latestBpDbp > 0 ? '${ble.latestBpDbp} mmHg' : '--',
                        icon: Icons.compress_rounded,
                        color: Colors.amberAccent,
                      ),
                      _VitalCard(
                        title: '6. Skin Temp',
                        value: ble.latestTempC > 0 ? '${ble.latestTempC.fixed2()} °C' : '--',
                        icon: Icons.thermostat_rounded,
                        color: Colors.deepOrangeAccent,
                      ),
                      _VitalCard(
                        title: '7. Stress Level',
                        value: ble.latestStressValue > 0 ? '${ble.latestStressValue} / 100' : '--',
                        icon: Icons.psychology_rounded,
                        color: Colors.purpleAccent,
                      ),
                      _VitalCard(
                        title: '8. Daily Steps',
                        value: '${ble.todaySteps} steps',
                        icon: Icons.directions_walk_rounded,
                        color: Colors.greenAccent,
                      ),
                      _VitalCard(
                        title: '9. Calories',
                        value: '${ble.todayCalories} kcal',
                        icon: Icons.local_fire_department_rounded,
                        color: Colors.pinkAccent,
                      ),
                      _VitalCard(
                        title: '10. Distance',
                        value: '${ble.todayDistanceM.toStringAsFixed(0)} m',
                        icon: Icons.map_rounded,
                        color: Colors.tealAccent,
                      ),
                      _VitalCard(
                        title: '11. Rest Rate',
                        value: session.snapshots.isNotEmpty ? '${session.snapshots.last.restRate} bpm' : '--',
                        icon: Icons.bedtime_rounded,
                        color: Colors.indigoAccent,
                      ),
                      _VitalCard(
                        title: '12. Respiration',
                        value: session.snapshots.isNotEmpty ? '${session.snapshots.last.respirationRate} /min' : '--',
                        icon: Icons.air_rounded,
                        color: Colors.lightGreenAccent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _VitalCard(
                    title: '13. Composite Serenity Index',
                    value: '$calmness% Calm & Relaxed',
                    icon: Icons.self_improvement_rounded,
                    color: AppTheme.gold,
                    fullWidth: true,
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
}

class _VitalCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final bool fullWidth;

  const _VitalCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.white10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: AppTypography.inter(color: AppTheme.textSec, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AppTypography.inter(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
