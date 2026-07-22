import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/ble_provider.dart';
import '../../theme/app_theme.dart';

// Local-only (SharedPreferences), same pattern as device_name/device_address in
// BleProvider — no backend table for these two fields yet, just a single local user.
const _kAddressPrefKey = 'fall_emergency_address';
const _kInstructionsPrefKey = 'fall_emergency_instructions';
const _kDefaultAddress = 'Flat 101, SingleBar avenue...';

// Tier labels for display only — the actual score comes from the native
// FallRiskAnalyzer (see BleProvider.getFallRiskScore), not computed here.
enum _FallTier { low, medium, high }

class _EmergencyContact {
  final int? id;
  final String name;
  final String phone;
  _EmergencyContact({this.id, required this.name, required this.phone});
}

class FallDetectionScreen extends StatefulWidget {
  // Set when navigating here from the Home fall-prediction banner ("Take action") so the
  // high-tier hero card shows immediately, without needing the debug ⋮ menu.
  final bool initialHighAlert;
  const FallDetectionScreen({super.key, this.initialHighAlert = false});

  @override
  State<FallDetectionScreen> createState() => _FallDetectionScreenState();
}

class _FallDetectionScreenState extends State<FallDetectionScreen> {
  // Lets you preview all three alert states from the ⋮ menu without needing
  // real elevated vitals — purely a demo aid, no effect on stored data.
  _FallTier? _debugTier;
  _FallTier? _ignoredForTier;

  // Persisted natively (Room), not widget state — fetched on load, seeded with two
  // defaults the first time the table is empty.
  List<_EmergencyContact> _contacts = [];
  bool _loadingContacts = true;

  String _address = _kDefaultAddress;
  String _instructions = '';

  // Real score from the native FallRiskAnalyzer — null until it has logged at
  // least one computation (i.e. a vital reading has actually been saved).
  Map<String, dynamic>? _realRisk;
  bool _loadingRisk = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialHighAlert) _debugTier = _FallTier.high;
    _loadRealRisk();
    _loadContacts();
    _loadAddressAndInstructions();
  }

  Future<void> _loadAddressAndInstructions() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _address = prefs.getString(_kAddressPrefKey) ?? _kDefaultAddress;
      _instructions = prefs.getString(_kInstructionsPrefKey) ?? '';
    });
  }

  Future<void> _loadRealRisk() async {
    final risk = await context.read<BleProvider>().getFallRiskScore();
    if (!mounted) return;
    setState(() {
      _realRisk = risk;
      _loadingRisk = false;
    });
  }

  Future<void> _loadContacts() async {
    final ble = context.read<BleProvider>();
    var rows = await ble.getEmergencyContacts();
    if (rows.isEmpty) {
      // First run — seed the same two defaults the old in-memory demo used, but for real.
      // Uses a fake test number (not a real emergency line) since the debug menu's
      // "Alert emergency contact" actually opens the dialer/SMS app with this number.
      await ble.addEmergencyContact('Default Emergency (Default)', '9999999999');
      await ble.addEmergencyContact('Mom', '+91 000 000 0000');
      rows = await ble.getEmergencyContacts();
    }
    if (!mounted) return;
    setState(() {
      _contacts = rows
          .map((r) => _EmergencyContact(
                id: (r['id'] as num?)?.toInt(),
                name: r['name'] as String? ?? '',
                phone: r['phone'] as String? ?? '',
              ))
          .toList();
      _loadingContacts = false;
    });
  }

  Future<void> _simulateRiskTrigger() async {
    final ble = context.read<BleProvider>();
    await ble.simulateFallRiskTrigger();
    // The native side computes and logs this asynchronously (EventBus + a background
    // coroutine) — give it a moment before re-fetching.
    await Future.delayed(const Duration(milliseconds: 600));
    await _loadRealRisk();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Posted a real 135bpm reading — risk score above should update')),
    );
  }

  _FallTier _tierFromScore(int score) {
    if (score >= 55) return _FallTier.high;
    if (score >= 25) return _FallTier.medium;
    return _FallTier.low;
  }

  Future<void> _openFallHistory() async {
    final events = await context.read<BleProvider>().getFallEvents(limit: 30);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.card2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FallHistorySheet(events: events),
    );
  }

  // Lets the user pick Call or Message for the primary emergency contact — launching both
  // tel: and sms: back-to-back buries the dialer behind the SMS app, which just looks like
  // calling silently stopped working. Neither auto-dials nor auto-sends: tel: opens the
  // dialer (ACTION_DIAL) pre-filled, sms: opens the messaging app with the body already typed.
  Future<void> _alertContact() async {
    if (_contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No emergency contact saved yet')),
      );
      return;
    }
    final contact = _contacts.first;
    final phone = contact.phone.trim();
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.card2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AlertContactSheet(contact: contact),
    );
    if (action == null || !mounted) return;

    final uri = action == 'call'
        ? Uri(scheme: 'tel', path: phone)
        : Uri(scheme: 'sms', path: phone, queryParameters: {
            'body': 'I may have fallen and need help. Please check on me as soon as possible.',
          });
    final ok = await launchUrl(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reach $phone')),
      );
    }
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
    if (saved != true || nameCtl.text.trim().isEmpty) return;
    if (!mounted) return;
    final ble = context.read<BleProvider>();
    await ble.addEmergencyContact(nameCtl.text.trim(), phoneCtl.text.trim());
    await _loadContacts();
  }

  Future<void> _editContact(_EmergencyContact contact) async {
    final nameCtl = TextEditingController(text: contact.name);
    final phoneCtl = TextEditingController(text: contact.phone);
    final ble = context.read<BleProvider>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _FormDialog(
        title: 'Edit contact',
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
        onDelete: contact.id == null
            ? null
            : () async {
                await ble.deleteEmergencyContact(contact.id!);
                await _loadContacts();
              },
      ),
    );
    if (saved != true || contact.id == null) return;
    if (!mounted) return;
    await ble.updateEmergencyContact(contact.id!, nameCtl.text.trim(), phoneCtl.text.trim());
    await _loadContacts();
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
    if (saved != true) return;
    setState(() => _address = ctl.text.trim());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAddressPrefKey, _address);
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
    if (saved != true) return;
    setState(() => _instructions = ctl.text.trim());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kInstructionsPrefKey, _instructions);
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final realScore = (_realRisk?['score'] as num?)?.toInt() ?? 0;
    final hasLiveData = _realRisk != null;
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
          'Fall Prediction',
          style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            color: AppTheme.card2,
            onSelected: (value) {
              switch (value) {
                case 'high':
                  setState(() { _debugTier = _FallTier.high; _ignoredForTier = null; });
                  break;
                case 'medium':
                  setState(() { _debugTier = _FallTier.medium; _ignoredForTier = null; });
                  break;
                case 'clear':
                  setState(() { _debugTier = null; _ignoredForTier = null; });
                  break;
                case 'notify':
                  context.read<BleProvider>().simulateFallEvent();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Simulated fall event — check your notification shade')),
                  );
                  break;
                case 'risk_trigger':
                  _simulateRiskTrigger();
                  break;
                case 'prediction':
                  context.read<BleProvider>().simulateFallPrediction();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Simulated fall prediction — check your notification shade')),
                  );
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'high', child: Text('Simulate: High risk', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'medium', child: Text('Simulate: Medium risk', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'clear', child: Text('Simulate: Clear (auto)', style: TextStyle(color: Colors.white))),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'notify', child: Text('Simulate: Fall notification', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'risk_trigger', child: Text('Simulate: Trigger risk analysis', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'prediction', child: Text('Simulate Fall prediction', style: TextStyle(color: Colors.white))),
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
          _RiskScoreCard(
            score: score,
            hasLiveData: isDemo || hasLiveData,
            loading: !isDemo && _loadingRisk,
          ),
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
            onTap: _openFallHistory,
          ),
          const SizedBox(height: 20),
          const _SectionLabel('EMERGENCY DETAILS'),
          const SizedBox(height: 8),
          if (_loadingContacts)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator(color: AppTheme.gold)),
            )
          else
            ..._contacts.asMap().entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ContactRow(contact: e.value, onTap: () => _editContact(e.value)),
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
  final bool hasLiveData;
  final bool loading;
  const _RiskScoreCard({required this.score, required this.hasLiveData, required this.loading});

  @override
  Widget build(BuildContext context) {
    final label = !hasLiveData
        ? (loading ? 'Loading…' : 'No live data yet — waiting for a vital reading')
        : score >= 55
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
            hasLiveData ? '$score' : '—',
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
  final VoidCallback? onTap;
  const _ContactRow({required this.contact, this.onTap});

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
            child: const Icon(Icons.local_hospital_outlined, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(contact.name, style: GoogleFonts.inter(color: Colors.white, fontSize: 14))),
          Text(contact.phone, style: GoogleFonts.inter(color: AppTheme.textSec, fontSize: 13)),
        ],
      ),
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
  final VoidCallback? onDelete;
  const _FormDialog({required this.title, required this.fields, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.card2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      content: Column(mainAxisSize: MainAxisSize.min, children: fields),
      actions: [
        if (onDelete != null)
          TextButton(
            onPressed: () {
              Navigator.pop(context, false);
              onDelete!();
            },
            child: Text('Delete', style: GoogleFonts.inter(color: AppTheme.danger)),
          ),
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

class _AlertContactSheet extends StatelessWidget {
  final _EmergencyContact contact;
  const _AlertContactSheet({required this.contact});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Alert ${contact.name}',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              contact.phone,
              style: GoogleFonts.inter(color: AppTheme.textSec, fontSize: 12),
            ),
            const SizedBox(height: 16),
            _ActionRow(
              icon: Icons.call_rounded,
              label: 'Call',
              onTap: () => Navigator.pop(context, 'call'),
            ),
            const SizedBox(height: 8),
            _ActionRow(
              icon: Icons.message_rounded,
              label: 'Message',
              onTap: () => Navigator.pop(context, 'message'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FallHistorySheet extends StatelessWidget {
  final List<Map<String, dynamic>> events;
  const _FallHistorySheet({required this.events});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, HH:mm');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fall history',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Logged by the on-device motion detector — real events only.',
              style: GoogleFonts.inter(color: AppTheme.textSec, fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (events.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No fall events logged yet.',
                  style: GoogleFonts.inter(color: AppTheme.textSec, fontSize: 13),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: events.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final e = events[i];
                    final detectedAt = (e['detectedAt'] as num?)?.toInt() ?? 0;
                    final confidence = ((e['confidence'] as num?) ?? 0).toDouble();
                    final corroborated = e['corroborated'] as bool? ?? false;
                    final source = e['corroborationSource'] as String? ?? 'none';
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.div),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            corroborated ? Icons.warning_amber_rounded : Icons.help_outline_rounded,
                            color: corroborated ? AppTheme.hrColor : AppTheme.textSec,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  detectedAt > 0
                                      ? fmt.format(DateTime.fromMillisecondsSinceEpoch(detectedAt))
                                      : 'Unknown time',
                                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                                Text(
                                  corroborated ? 'Corroborated by $source' : 'Not corroborated',
                                  style: GoogleFonts.inter(color: AppTheme.textSec, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${(confidence * 100).toInt()}%',
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
