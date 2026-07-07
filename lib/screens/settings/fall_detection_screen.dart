import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../theme/app_theme.dart';

// Simple, rule-based risk tiering — no ML/sensor fusion, just thresholds over
// data we already have (heart rate + stress). Good enough for a UI/demo pass.
enum _FallTier { low, medium, high }

class _EmergencyContact {
  String name;
  String phone;
  _EmergencyContact(this.name, this.phone);
}

class FallDetectionScreen extends StatefulWidget {
  const FallDetectionScreen({super.key});

  @override
  State<FallDetectionScreen> createState() => _FallDetectionScreenState();
}

class _FallDetectionScreenState extends State<FallDetectionScreen> {
  // Lets you preview all three alert states from the ⋮ menu without needing
  // real elevated vitals — purely a demo aid, no effect on stored data.
  _FallTier? _debugTier;
  _FallTier? _ignoredForTier;

  final List<_EmergencyContact> _contacts = [
    _EmergencyContact('Default Emergency (Default)', '101'),
    _EmergencyContact('Mom', '+91 000 000 0000'),
  ];

  String _address = 'Flat 101, SingleBar avenue...';
  String _instructions = '';

  int _riskScore(BleProvider ble) {
    var score = 0;
    final hr = ble.todayMaxHr;
    if (hr >= 130) {
      score += 45;
    } else if (hr >= 110) {
      score += 30;
    } else if (hr >= 95) {
      score += 15;
    }
    final stress = ble.todayAvgStress;
    if (stress >= 70) {
      score += 25;
    } else if (stress >= 50) {
      score += 10;
    }
    return score.clamp(0, 100);
  }

  _FallTier _tierFromScore(int score) {
    if (score >= 55) return _FallTier.high;
    if (score >= 25) return _FallTier.medium;
    return _FallTier.low;
  }

  void _alertContact() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Emergency contact alerted')),
    );
  }

  Future<void> _addContact() async {
    final nameCtl = TextEditingController();
    final phoneCtl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _FormDialog(
        title: 'Add a new contact',
        fields: [
          TextField(
            controller: nameCtl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(hintText: 'Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: phoneCtl,
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: 'Phone number'),
          ),
        ],
      ),
    );
    if (saved == true && nameCtl.text.trim().isNotEmpty) {
      setState(() {
        _contacts.add(_EmergencyContact(nameCtl.text.trim(), phoneCtl.text.trim()));
      });
    }
  }

  Future<void> _editAddress() async {
    final ctl = TextEditingController(text: _address);
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _FormDialog(
        title: 'Address',
        fields: [
          TextField(
            controller: ctl,
            style: const TextStyle(color: Colors.white),
            maxLines: 2,
            decoration: const InputDecoration(hintText: 'Address'),
          ),
        ],
      ),
    );
    if (saved == true) setState(() => _address = ctl.text.trim());
  }

  Future<void> _editInstructions() async {
    final ctl = TextEditingController(text: _instructions);
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _FormDialog(
        title: 'Additional instructions',
        fields: [
          TextField(
            controller: ctl,
            style: const TextStyle(color: Colors.white),
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'e.g. Gate code, floor, pets...'),
          ),
        ],
      ),
    );
    if (saved == true) setState(() => _instructions = ctl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final realScore = _riskScore(ble);
    final tier = _debugTier ?? _tierFromScore(realScore);
    final isDemo = _debugTier != null && _debugTier != _FallTier.low;

    final int hr = isDemo ? (tier == _FallTier.high ? 122 : 118) : ble.todayMaxHr;
    final double temp = isDemo ? 36.0 : ble.latestTempC;
    final int score = isDemo ? (tier == _FallTier.high ? 43 : 38) : realScore;
    final showAlert = tier != _FallTier.low && _ignoredForTier != tier;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Fall Detection',
          style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          PopupMenuButton<_FallTier?>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            color: AppTheme.card2,
            onSelected: (value) => setState(() {
              _debugTier = value;
              _ignoredForTier = null;
            }),
            itemBuilder: (_) => [
              const PopupMenuItem(value: _FallTier.high, child: Text('Simulate: High risk', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: _FallTier.medium, child: Text('Simulate: Medium risk', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: null, child: Text('Simulate: Clear (auto)', style: TextStyle(color: Colors.white))),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (showAlert) ...[
            _HeroCard(
              tier: tier,
              hr: hr,
              onPrimaryAction: tier == _FallTier.high
                  ? _alertContact
                  : () => setState(() => _ignoredForTier = tier),
            ),
            const SizedBox(height: 20),
            _SectionLabel(tier == _FallTier.high ? 'OTHER ACTIONS' : 'RECOMMENDED ACTIONS'),
            const SizedBox(height: 8),
            _ActionRow(
              icon: tier == _FallTier.high ? Icons.close_rounded : Icons.call_rounded,
              label: tier == _FallTier.high ? 'Ignore warning' : 'Alert emergency contact',
              onTap: tier == _FallTier.high
                  ? () => setState(() => _ignoredForTier = tier)
                  : _alertContact,
            ),
            const SizedBox(height: 20),
          ],
          const _SectionLabel('FALL RISK SCORE'),
          const SizedBox(height: 8),
          _RiskScoreCard(score: score),
          const SizedBox(height: 16),
          if (tier == _FallTier.high)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _HeartRateCard(hr: hr, compact: true)),
                const SizedBox(width: 12),
                Expanded(child: _TemperatureCard(temp: temp)),
              ],
            )
          else
            _HeartRateCard(hr: hr, compact: false),
          const SizedBox(height: 16),
          _ActionRow(
            icon: Icons.directions_run_rounded,
            label: 'View Fall history',
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Fall history — coming soon')),
            ),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('EMERGENCY DETAILS'),
          const SizedBox(height: 8),
          ..._contacts.asMap().entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ContactRow(contact: e.value),
                ),
              ),
          _ActionRow(
            icon: Icons.add_rounded,
            label: 'Add a new contact',
            onTap: _addContact,
          ),
          const SizedBox(height: 20),
          const _SectionLabel('ADDRESS'),
          const SizedBox(height: 8),
          _EditableRow(label: 'Address', value: _address, onTap: _editAddress),
          const SizedBox(height: 8),
          _EditableRow(
            label: 'Additional instructions',
            value: _instructions.isEmpty ? 'Add' : _instructions,
            onTap: _editInstructions,
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: Colors.white.withValues(alpha: 0.35),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final _FallTier tier;
  final int hr;
  final VoidCallback onPrimaryAction;

  const _HeroCard({required this.tier, required this.hr, required this.onPrimaryAction});

  @override
  Widget build(BuildContext context) {
    final isHigh = tier == _FallTier.high;
    final accent = isHigh ? AppTheme.hrColor : AppTheme.tempColor;
    final title = isHigh ? 'You might fall soon...' : 'We are concerned ...';
    final body = isHigh
        ? 'We have detected multiple signs that you might fall down in the next 2-3 minutes. Take a seat and contact your caretaker.'
        : 'Your heart rate rose to $hr BPM while you seemed to be in-active for the last 10 minutes.';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.25), width: 0.5),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.30), AppTheme.card],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'FALL PREDICTION',
                style: GoogleFonts.inter(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 16),
          if (isHigh)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onPrimaryAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.14),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
                child: const Text('Alert emergency contact', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            )
          else
            Center(
              child: TextButton(
                onPressed: onPrimaryAction,
                child: Text('ignore', style: GoogleFonts.inter(color: AppTheme.danger, fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
    );
  }
}

class _RiskScoreCard extends StatelessWidget {
  final int score;
  const _RiskScoreCard({required this.score});

  @override
  Widget build(BuildContext context) {
    final label = score >= 55
        ? 'High chance of falling'
        : score >= 25
            ? 'Moderate chance of falling'
            : 'Low chance of falling';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$score',
            style: GoogleFonts.inter(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w300),
          ),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.inter(color: AppTheme.textSec, fontSize: 13)),
        ],
      ),
    );
  }
}

class _HeartRateCard extends StatelessWidget {
  final int hr;
  final bool compact;
  const _HeartRateCard({required this.hr, required this.compact});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.div),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Heart Rate', style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/heart-rate'),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), shape: BoxShape.circle),
                  child: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 16),
                ),
              ),
            ],
          ),
          SizedBox(
            height: compact ? 30 : 46,
            child: CustomPaint(
              size: Size.infinite,
              painter: _SparklinePainter(color: AppTheme.hrColor),
            ),
          ),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: '$hr ',
                style: GoogleFonts.inter(color: AppTheme.hrColor, fontSize: compact ? 26 : 34, fontWeight: FontWeight.w700),
              ),
              TextSpan(
                text: 'bpm',
                style: GoogleFonts.inter(color: AppTheme.hrColor, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _TemperatureCard extends StatelessWidget {
  final double temp;
  const _TemperatureCard({required this.temp});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.div),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Temperature', style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 26),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: temp.toStringAsFixed(0),
                style: GoogleFonts.inter(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700),
              ),
              TextSpan(
                text: ' °C',
                style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
              ),
            ]),
          ),
          const SizedBox(height: 4),
          Text(
            '-1 °C in the last 30 seconds',
            style: GoogleFonts.inter(color: AppTheme.hrColor, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionRow({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.div),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: GoogleFonts.inter(color: Colors.white, fontSize: 14))),
            Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.3), size: 20),
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final _EmergencyContact contact;
  const _ContactRow({required this.contact});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.div),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), shape: BoxShape.circle),
            child: const Icon(Icons.local_hospital_outlined, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(contact.name, style: GoogleFonts.inter(color: Colors.white, fontSize: 14))),
          Text(contact.phone, style: GoogleFonts.inter(color: AppTheme.textSec, fontSize: 13)),
        ],
      ),
    );
  }
}

class _EditableRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  const _EditableRow({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.div),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), shape: BoxShape.circle),
              child: const Icon(Icons.edit_outlined, color: Colors.white, size: 15),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: GoogleFonts.inter(color: Colors.white, fontSize: 14))),
            Flexible(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(color: AppTheme.textSec, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormDialog extends StatelessWidget {
  final String title;
  final List<Widget> fields;
  const _FormDialog({required this.title, required this.fields});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.card2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      content: Column(mainAxisSize: MainAxisSize.min, children: fields),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textSec)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('Save', style: GoogleFonts.inter(color: AppTheme.gold, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final Color color;
  _SparklinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final w = size.width;
    final h = size.height;
    final points = [0.6, 0.5, 0.55, 0.3, 0.45, 0.2, 0.4, 0.35, 0.5, 0.42];
    for (var i = 0; i < points.length; i++) {
      final x = w * i / (points.length - 1);
      final y = h * points[i];
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) => oldDelegate.color != color;
}
