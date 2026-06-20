import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _firstName = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BleProvider>().checkConnection();
    });
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    try {
      final user = SupabaseService.currentUser;
      if (user != null) {
        final profile = await SupabaseService.getProfile(user.id);
        if (mounted && profile != null) {
          final fullName = profile['full_name'] as String? ?? '';
          setState(() => _firstName = fullName.split(' ').first);
        }
      }
    } catch (_) {}
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning,';
    if (h < 17) return 'Good Afternoon,';
    if (h < 21) return 'Good Evening,';
    return 'Good Night,';
  }

  String get _dateLabel {
    final now = DateTime.now();
    const d = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const m = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
                'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    return '${d[now.weekday - 1]} ${now.day} ${m[now.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    return RefreshIndicator(
      color: AppTheme.gold,
      backgroundColor: AppTheme.card,
      onRefresh: () async {
        await ble.checkConnection();
        await _loadUserName();
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(ble),
                  const SizedBox(height: 4),
                  const Divider(color: AppTheme.div, thickness: 0.5, height: 0.5),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'ALL METRICS  ·  TODAY',
                      style: TextStyle(
                        color: AppTheme.gold.withValues(alpha: 0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Row(children: [
                  Expanded(child: _MetricCard(
                    label: 'STEPS',
                    value: ble.todaySteps > 0 ? '${ble.todaySteps}' : '--',
                    unit: 'steps',
                    status: ble.syncingSteps
                        ? 'Syncing...'
                        : ble.todaySteps > 0
                            ? '${ble.todayCalories} kcal'
                            : 'Tap to load',
                    color: AppTheme.stepsColor,
                    icon: Icons.directions_walk_rounded,
                    chartData: const [0.3, 0.4, 0.6, 0.7, 0.5, 0.8, 0.6, 0.4, 0.5, 0.7, 0.9, 0.5],
                    onTap: () => Navigator.pushNamed(context, '/steps'),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _MetricCard(
                    label: 'SLEEP',
                    value: '--',
                    unit: 'hrs',
                    status: 'Tap to sync',
                    color: AppTheme.sleepColor,
                    icon: Icons.bedtime_rounded,
                    chartData: const [0.7, 0.75, 0.8, 0.75, 0.7, 0.65, 0.8, 0.85, 0.8, 0.75, 0.7, 0.75],
                    onTap: () => Navigator.pushNamed(context, '/sleep'),
                  )),
                ]),
                const SizedBox(height: 12),
                _StressCard(onTap: () => Navigator.pushNamed(context, '/pressure')),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _MetricCard(
                    label: 'HRV',
                    value: '--',
                    unit: 'ms',
                    status: 'Normal',
                    color: AppTheme.hrvColor,
                    icon: Icons.monitor_heart_rounded,
                    chartData: const [0.5, 0.6, 0.45, 0.7, 0.55, 0.8, 0.6, 0.5, 0.45, 0.65, 0.7, 0.55],
                    onTap: () => Navigator.pushNamed(context, '/hrv'),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _MetricCard(
                    label: 'BLOOD OXYGEN',
                    value: '--',
                    unit: '%',
                    status: 'Excellent',
                    color: AppTheme.spo2Color,
                    icon: Icons.bloodtype_rounded,
                    chartData: const [0.96, 0.97, 0.96, 0.98, 0.97, 0.99, 0.98, 0.97, 0.96, 0.98, 0.97, 0.99],
                    onTap: () => Navigator.pushNamed(context, '/blood-oxygen'),
                  )),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _MetricCard(
                    label: 'HEART RATE',
                    value: '--',
                    unit: 'bpm',
                    status: 'Resting',
                    color: AppTheme.hrColor,
                    icon: Icons.favorite_rounded,
                    chartData: const [0.45, 0.5, 0.55, 0.5, 0.6, 0.55, 0.5, 0.48, 0.52, 0.58, 0.54, 0.5],
                    onTap: () => Navigator.pushNamed(context, '/heart-rate'),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _MetricCard(
                    label: 'BLOOD PRESSURE',
                    value: '--/--',
                    unit: 'mmHg',
                    status: 'Normal',
                    color: AppTheme.bpColor,
                    icon: Icons.water_drop_rounded,
                    chartData: const [0.6, 0.65, 0.6, 0.68, 0.65, 0.6, 0.64, 0.67, 0.64, 0.6, 0.65, 0.62],
                    onTap: () => Navigator.pushNamed(context, '/blood-pressure'),
                  )),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _MetricCard(
                    label: 'TEMPERATURE',
                    value: '--',
                    unit: '°C',
                    status: 'Normal',
                    color: AppTheme.tempColor,
                    icon: Icons.thermostat_rounded,
                    chartData: const [0.5, 0.52, 0.51, 0.53, 0.52, 0.51, 0.5, 0.52, 0.53, 0.51, 0.5, 0.52],
                    onTap: () => Navigator.pushNamed(context, '/temperature'),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _MetricCard(
                    label: 'SPORT',
                    value: '--',
                    unit: 'kcal',
                    status: 'No activity',
                    color: const Color(0xFFD97706),
                    icon: Icons.sports_gymnastics_rounded,
                    chartData: const [0.2, 0.3, 0.5, 0.4, 0.6, 0.7, 0.5, 0.3, 0.2, 0.4, 0.5, 0.3],
                    onTap: () => Navigator.pushNamed(context, '/sport-record'),
                  )),
                ]),
                const SizedBox(height: 100),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BleProvider ble) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting,
                  style: const TextStyle(
                    color: AppTheme.textSec,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Text(
                  _firstName.isNotEmpty ? _firstName : 'User',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _dateLabel,
                  style: const TextStyle(
                    color: AppTheme.textSec,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildDevicePill(ble),
        ],
      ),
    );
  }

  Widget _buildDevicePill(BleProvider ble) {
    final connected = ble.isConnected;
    final reconnecting = ble.isReconnecting;
    final battery = ble.battery;

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/device-bind'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: connected
                ? AppTheme.gold.withValues(alpha: 0.3)
                : AppTheme.div,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reconnecting)
              const SizedBox(
                width: 8,
                height: 8,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppTheme.gold,
                ),
              )
            else
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: connected
                      ? AppTheme.success
                      : const Color(0xFF6B7280),
                ),
              ),
            const SizedBox(width: 6),
            Text(
              ble.deviceName.isNotEmpty ? ble.deviceName : 'Ring',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (battery >= 0) ...[
              const SizedBox(width: 6),
              Icon(
                battery > 60
                    ? Icons.battery_full_rounded
                    : battery > 30
                        ? Icons.battery_3_bar_rounded
                        : Icons.battery_1_bar_rounded,
                color: battery > 20 ? AppTheme.textSec : AppTheme.danger,
                size: 14,
              ),
              Text(
                '$battery%',
                style: const TextStyle(color: AppTheme.textSec, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────
// 2×1 Metric card
// ──────────────────────────────────────────────────
class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final String status;
  final Color color;
  final IconData icon;
  final List<double> chartData;
  final VoidCallback onTap;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.status,
    required this.color,
    required this.icon,
    required this.chartData,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 165,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.18), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 17),
                ),
                const Spacer(),
                Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textSec, size: 16),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: 0.85),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 3),
                Text(unit,
                    style: const TextStyle(
                        color: AppTheme.textSec, fontSize: 10)),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    status,
                    style: const TextStyle(
                        color: AppTheme.textSec, fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 28,
                    child: CustomPaint(
                      painter: _MiniSparkPainter(color, chartData),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniSparkPainter extends CustomPainter {
  final Color color;
  final List<double> data;

  const _MiniSparkPainter(this.color, this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final step = size.width / (data.length - 1);
    final path = Path();

    for (int i = 0; i < data.length; i++) {
      final x = i * step;
      final y = size.height - data[i] * size.height * 0.88 - 1;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        final px = (i - 1) * step;
        final py = size.height - data[i - 1] * size.height * 0.88 - 1;
        final cpx = (px + x) / 2;
        path.cubicTo(cpx, py, cpx, y, x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_MiniSparkPainter old) =>
      old.color != color || old.data != data;
}

// ──────────────────────────────────────────────────
// Full-width Stress card with mini bar chart
// ──────────────────────────────────────────────────
class _StressCard extends StatelessWidget {
  final VoidCallback onTap;

  const _StressCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: AppTheme.stressColor.withValues(alpha: 0.2), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.stressColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.psychology_rounded,
                      color: AppTheme.stressColor, size: 16),
                ),
                const SizedBox(width: 8),
                const Text(
                  'STRESS',
                  style: TextStyle(
                    color: AppTheme.stressColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textSec, size: 16),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('DAILY AVERAGE',
                        style: TextStyle(
                            color: AppTheme.textSec,
                            fontSize: 9,
                            letterSpacing: 0.5)),
                    const Text('--',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            height: 1.1)),
                    const Text('Normal',
                        style: TextStyle(
                            color: AppTheme.success, fontSize: 11)),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: CustomPaint(painter: _StressBarPainter()),
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('DAILY RANGE',
                        style: TextStyle(
                            color: AppTheme.textSec,
                            fontSize: 9,
                            letterSpacing: 0.5)),
                    const Text('--',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                    const Text('Normal',
                        style: TextStyle(
                            color: AppTheme.success, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StressBarPainter extends CustomPainter {
  static const _data = [0.30, 0.38, 0.45, 0.35, 0.48, 0.52, 0.38, 0.42, 0.55, 0.47, 0.38, 0.30];
  static const _colors = [
    Color(0xFF34D399), Color(0xFF34D399), Color(0xFF6EE7B7),
    Color(0xFFFBBF24), Color(0xFFFBBF24), Color(0xFFF59E0B),
    Color(0xFFF97316), Color(0xFFF97316), Color(0xFFFBBF24),
    Color(0xFF6EE7B7), Color(0xFF34D399), Color(0xFF34D399),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final n = _data.length;
    final barW = size.width / n * 0.6;
    final gap = size.width / n * 0.4;

    for (int i = 0; i < n; i++) {
      final x = i * (barW + gap) + gap / 2;
      final barH = (_data[i] * size.height * 0.9).clamp(3.0, size.height);
      final y = size.height - barH;
      canvas.drawRRect(
        RRect.fromLTRBR(x, y, x + barW, size.height, const Radius.circular(3)),
        Paint()..color = _colors[i],
      );
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
