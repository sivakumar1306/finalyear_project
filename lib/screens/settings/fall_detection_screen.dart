import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/ble_provider.dart';
import '../../providers/fall_prediction/fall_prediction_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/fall_prediction/fall_risk_score_card.dart';
import '../../widgets/fall_prediction/explainable_ai_dashboard.dart';
import '../../widgets/app_typography.dart';

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

  bool _simulateConnection = false;

  // Persisted natively (Room), not widget state — fetched on load, seeded with two
  // defaults the first time the table is empty.
  List<_EmergencyContact> _contacts = [];
  bool _loadingContacts = true;

  String _address = _kDefaultAddress;
  String _instructions = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialHighAlert) _debugTier = _FallTier.high;
    _loadRealRisk();
    _loadContacts();
    _loadAddressAndInstructions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<BleProvider>().refreshEmergencySmsStatus();
    });
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
    await context.read<BleProvider>().getFallRiskScore();
  }

  Future<void> _loadContacts() async {
    final ble = context.read<BleProvider>();
    final rows = await ble.getEmergencyContacts();
    if (!mounted) return;
    setState(() {
      _contacts = rows
          .map(
            (r) => _EmergencyContact(
              id: (r['id'] as num?)?.toInt(),
              name: r['name'] as String? ?? '',
              phone: r['phone'] as String? ?? '',
            ),
          )
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
      const SnackBar(
        content: Text(
          'Posted a real 135bpm reading — risk score above should update',
        ),
      ),
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

  // Call opens the dialer for the primary contact. Message uses Android SmsManager to
  // send immediately to **all** saved emergency contacts (true background send).
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
      builder: (_) =>
          _AlertContactSheet(contact: contact, contactCount: _contacts.length),
    );
    if (action == null || !mounted) return;

    if (action == 'call') {
      final uri = Uri(scheme: 'tel', path: phone);
      final ok = await launchUrl(uri);
      if (!ok && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not reach $phone')));
      }
      return;
    }

    // Message — SmsManager to every contact, no messaging-app UI.
    final ble = context.read<BleProvider>();
    final result = await ble.sendEmergencySms();
    if (!mounted) return;
    final ok = result['ok'] == true;
    final sent = (result['sentCount'] as num?)?.toInt() ?? 0;
    final err = result['error'] as String?;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'SMS sent to $sent emergency contact${sent == 1 ? '' : 's'}'
              : (err ?? 'Failed to send emergency SMS'),
        ),
      ),
    );
  }

  Future<void> _ignoreWarning() async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.card2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Why are you ignoring this?',
                style: AppTypography.inter(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              _ActionRow(
                icon: Icons.check_circle_outline,
                label: 'I\'m okay (False Alarm)',
                onTap: () => Navigator.pop(context, 'false_alarm'),
              ),
              const SizedBox(height: 8),
              _ActionRow(
                icon: Icons.sports_martial_arts,
                label: 'I was just exercising',
                onTap: () => Navigator.pop(context, 'exercising'),
              ),
              const SizedBox(height: 8),
              _ActionRow(
                icon: Icons.cancel_outlined,
                label: 'Cancel',
                onTap: () => Navigator.pop(context, null),
              ),
            ],
          ),
        ),
      ),
    );

    if (reason == null) return;

    setState(() => _ignoredForTier = _FallTier.high);
    if (!mounted) return;
    await context.read<BleProvider>().cancelEmergencySms();
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
    await ble.updateEmergencyContact(
      contact.id!,
      nameCtl.text.trim(),
      phoneCtl.text.trim(),
    );
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
            decoration: const InputDecoration(
              hintText: 'e.g. Gate code, floor, pets...',
            ),
          ),
        ],
      ),
    );
    if (saved != true) return;
    setState(() => _instructions = ctl.text.trim());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kInstructionsPrefKey, _instructions);
  }

  Future<void> _onAutoCallToggle(bool enabled) async {
    final ble = context.read<BleProvider>();
    if (enabled) {
      final status = await Permission.phone.request();
      if (!status.isGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Phone permission is required to auto-call your emergency contact',
            ),
          ),
        );
        await ble.setAutoCallOnFallEnabled(false);
        return;
      }
    }
    await ble.setAutoCallOnFallEnabled(enabled);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? 'Auto-call on fall detection enabled'
              : 'Auto-call on fall detection disabled',
        ),
      ),
    );
  }

  Future<void> _onAutoCallPredictionToggle(bool enabled) async {
    final ble = context.read<BleProvider>();
    if (enabled) {
      final status = await Permission.phone.request();
      if (!status.isGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Phone permission is required to auto-call your emergency contact',
            ),
          ),
        );
        await ble.setAutoCallOnFallPredictionEnabled(false);
        return;
      }
    }
    await ble.setAutoCallOnFallPredictionEnabled(enabled);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? 'Auto-call on fall prediction enabled'
              : 'Auto-call on fall prediction disabled',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final fallProvider = context.watch<FallPredictionProvider>();
    final realScore = fallProvider.currentResult?.frs24.value.toInt() ?? 0;
    final tier = _debugTier ?? _tierFromScore(realScore);
    final isDemo = _debugTier != null && _debugTier != _FallTier.low;

    final int hr = isDemo
        ? (tier == _FallTier.high ? 122 : 118)
        : ble.todayMaxHr;
    final showAlert = tier != _FallTier.low && _ignoredForTier != tier;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: const GlassBackButton(),
        title: Text(
          'Fall Detection',
          style: AppTypography.inter(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
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
                  context.read<FallPredictionProvider>().simulateTier('high');
                  setState(() {
                    _debugTier = _FallTier.high;
                    _ignoredForTier = null;
                  });
                  break;
                case 'medium':
                  context.read<FallPredictionProvider>().simulateTier('medium');
                  setState(() {
                    _debugTier = _FallTier.medium;
                    _ignoredForTier = null;
                  });
                  break;
                case 'clear':
                  context.read<FallPredictionProvider>().simulateTier('clear');
                  setState(() {
                    _debugTier = null;
                    _ignoredForTier = null;
                  });
                  break;
                case 'clear_mock_data':
                  context.read<BleProvider>().clearMockVitals();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Mock data cleared! Restart the app to refresh all UI.',
                      ),
                    ),
                  );
                  break;
                case 'notify':
                  context.read<BleProvider>().simulateFallEvent();
                  context.read<BleProvider>().refreshEmergencySmsStatus();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Simulated fall — notification only. No SMS or call was triggered.',
                      ),
                    ),
                  );
                  break;
                case 'risk_trigger':
                  _simulateRiskTrigger();
                  break;
                case 'prediction':
                  context.read<BleProvider>().simulateFallPrediction();
                  context.read<BleProvider>().refreshEmergencySmsStatus();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Simulated prediction — notification only. No SMS was scheduled.',
                      ),
                    ),
                  );
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'high',
                child: Text(
                  'Simulate: High risk',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              const PopupMenuItem(
                value: 'medium',
                child: Text(
                  'Simulate: Medium risk',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Text(
                  'Simulate: Clear (auto)',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'notify',
                child: Text(
                  'Simulate: Fall notification',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              const PopupMenuItem(
                value: 'risk_trigger',
                child: Text(
                  'Simulate: Trigger risk analysis',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              const PopupMenuItem(
                value: 'prediction',
                child: Text(
                  'Simulate Fall prediction',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (showAlert || ble.emergencySmsActive) ...[
            _HeroCard(
              tier: ble.emergencySmsActive ? _FallTier.high : tier,
              hr: hr,
              smsSecondsRemaining: ble.emergencySmsActive
                  ? ble.emergencySmsSecondsRemaining
                  : null,
              smsHasPermission: ble.emergencySmsHasPermission,
              onPrimaryAction:
                  (ble.emergencySmsActive || tier == _FallTier.high)
                  ? _alertContact
                  : () => setState(() => _ignoredForTier = tier),
            ),
            const SizedBox(height: 20),
            _SectionLabel(
              (ble.emergencySmsActive || tier == _FallTier.high)
                  ? 'OTHER ACTIONS'
                  : 'RECOMMENDED ACTIONS',
            ),
            const SizedBox(height: 8),
            if (ble.emergencySmsActive)
              _ActionRow(
                icon: Icons.sms_failed_outlined,
                label:
                    'Cancel emergency SMS (${ble.emergencySmsSecondsRemaining}s)',
                onTap: _ignoreWarning,
              )
            else
              _ActionRow(
                icon: tier == _FallTier.high
                    ? Icons.close_rounded
                    : Icons.call_rounded,
                label: tier == _FallTier.high
                    ? 'Ignore warning'
                    : 'Alert emergency contact',
                onTap: tier == _FallTier.high ? _ignoreWarning : _alertContact,
              ),
            const SizedBox(height: 20),
          ],
          if (ble.isConnected || _simulateConnection) ...[
            if (_simulateConnection)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.gold.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.gold.withAlpha(100)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.science, color: AppTheme.gold, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Simulation Mode: UI is shown as if ring is connected.',
                        style: AppTypography.inter(color: AppTheme.gold, fontSize: 13),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _simulateConnection = false),
                      child: const Icon(Icons.close, color: AppTheme.gold, size: 20),
                    )
                  ],
                ),
              ),
            const _SectionLabel('FALL RISK SCORE (LIVE)'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => Scaffold(
                      backgroundColor: AppTheme.bg,
                      appBar: AppBar(
                        backgroundColor: AppTheme.bg,
                        leading: const GlassBackButton(),
                        title: Text(
                          'Risk Score Details',
                          style: AppTypography.inter(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        centerTitle: true,
                        elevation: 0,
                      ),
                      body: ListView(
                        padding: const EdgeInsets.all(16.0),
                        children: const [
                          ExplainableAIDashboard(),
                        ],
                      ),
                    ),
                  ),
                );
              },
              child: const FallRiskScoreCard(),
            ),
            const SizedBox(height: 20),
          ] else if (!ble.isConnected && !_simulateConnection) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: Colors.amber,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'connect ring to enable fall detection',
                      style: AppTypography.inter(
                        color: Colors.amber,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _ActionRow(
              icon: Icons.visibility_outlined,
              label: 'Simulate Connected UI',
              onTap: () => setState(() => _simulateConnection = true),
            ),
            const SizedBox(height: 20),
          ],
          _ActionRow(
            icon: Icons.directions_run_rounded,
            label: 'View Fall history',
            onTap: _openFallHistory,
          ),
          const SizedBox(height: 12),
          _ToggleRow(
            icon: Icons.phone_in_talk_rounded,
            title: 'Auto-call on fall detection',
            value: ble.autoCallOnFallEnabled,
            onChanged: _onAutoCallToggle,
          ),
          const SizedBox(height: 12),
          _ToggleRow(
            icon: Icons.phone_in_talk_rounded,
            title: 'Auto call on fall prediction',
            subtitle:
                'Call emergency contact when fall risk score hits 9.0 or higher',
            value: ble.autoCallOnFallPredictionEnabled,
            onChanged: _onAutoCallPredictionToggle,
          ),
          const SizedBox(height: 20),
          const _SectionLabel('EMERGENCY DETAILS'),
          const SizedBox(height: 8),
          if (_loadingContacts)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.gold),
              ),
            )
          else if (_contacts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.danger.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppTheme.danger,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No emergency contacts saved. Add at least one real contact '
                        'before fall alerts can reach anyone — SMS and auto-call stay '
                        'blocked until then.',
                        style: AppTypography.inter(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._contacts.asMap().entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ContactRow(
                  contact: e.value,
                  onTap: () => _editContact(e.value),
                ),
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
        style: AppTypography.inter(
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
  final int? smsSecondsRemaining;
  final bool smsHasPermission;
  final VoidCallback onPrimaryAction;

  const _HeroCard({
    required this.tier,
    required this.hr,
    this.smsSecondsRemaining,
    this.smsHasPermission = true,
    required this.onPrimaryAction,
  });

  @override
  Widget build(BuildContext context) {
    final countdown = smsSecondsRemaining;
    final isHigh = tier == _FallTier.high || countdown != null;
    final accent = isHigh ? AppTheme.hrColor : AppTheme.tempColor;
    final title = countdown != null
        ? 'Emergency SMS in ${countdown}s'
        : (isHigh ? 'You might fall soon...' : 'We are concerned ...');
    final body = countdown != null
        ? (!smsHasPermission
              ? 'SMS permission is missing. Grant SEND_SMS so contacts can be alerted automatically.'
              : 'SMS will be sent to all emergency contacts in $countdown seconds unless you cancel. '
                    'You can also alert them immediately below.')
        : (isHigh
              ? 'We have detected multiple signs that you might fall down in the next 2-3 minutes. '
                    'Take a seat and contact your caretaker.'
              : 'Your heart rate rose to $hr BPM while you seemed to be in-active for the last 10 minutes.');

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
                countdown != null ? 'EMERGENCY SMS' : 'FALL PREDICTION',
                style: AppTypography.inter(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: AppTypography.inter(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: AppTypography.inter(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
              height: 1.45,
            ),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: Text(
                  countdown != null
                      ? 'Alert now (all contacts)'
                      : 'Alert emergency contact',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            )
          else
            Center(
              child: TextButton(
                onPressed: onPrimaryAction,
                child: Text(
                  'ignore',
                  style: AppTypography.inter(
                    color: AppTheme.danger,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
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
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

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
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: AppTypography.inter(color: Colors.white, fontSize: 14),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.3),
              size: 20,
            ),
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
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_hospital_outlined,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                contact.name,
                style: AppTypography.inter(color: Colors.white, fontSize: 14),
              ),
            ),
            Text(
              contact.phone,
              style: AppTypography.inter(color: AppTheme.textSec, fontSize: 13),
            ),
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
  const _EditableRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

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
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.edit_outlined,
                color: Colors.white,
                size: 15,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: AppTypography.inter(color: Colors.white, fontSize: 14),
              ),
            ),
            Flexible(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.inter(
                  color: AppTheme.textSec,
                  fontSize: 13,
                ),
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
            child: Text(
              'Delete',
              style: AppTypography.inter(color: AppTheme.danger),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            'Cancel',
            style: AppTypography.inter(color: AppTheme.textSec),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            'Save',
            style: AppTypography.inter(
              color: AppTheme.gold,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}


class _AlertContactSheet extends StatelessWidget {
  final _EmergencyContact contact;
  final int contactCount;
  const _AlertContactSheet({required this.contact, this.contactCount = 1});

  @override
  Widget build(BuildContext context) {
    final smsLabel = contactCount > 1
        ? 'Message all $contactCount contacts'
        : 'Message ${contact.name}';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Alert emergency contacts',
              style: AppTypography.inter(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Call opens the dialer for ${contact.name}. Message sends SMS to every saved contact.',
              style: AppTypography.inter(
                color: AppTheme.textSec,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            _ActionRow(
              icon: Icons.call_rounded,
              label: 'Call ${contact.name}',
              onTap: () => Navigator.pop(context, 'call'),
            ),
            const SizedBox(height: 8),
            _ActionRow(
              icon: Icons.message_rounded,
              label: smsLabel,
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
              style: AppTypography.inter(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Logged by the on-device motion detector — real events only.',
              style: AppTypography.inter(color: AppTheme.textSec, fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (events.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No fall events logged yet.',
                  style: AppTypography.inter(
                    color: AppTheme.textSec,
                    fontSize: 13,
                  ),
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
                    final confidence = ((e['confidence'] as num?) ?? 0)
                        .toDouble();
                    final corroborated = e['corroborated'] as bool? ?? false;
                    final source =
                        e['corroborationSource'] as String? ?? 'none';
                    final eventType = e['eventType'] as String? ?? 'DETECTED';
                    final isPrediction = eventType == 'PREDICTED';
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.div),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isPrediction
                                ? Icons.trending_up_rounded
                                : (corroborated
                                      ? Icons.warning_amber_rounded
                                      : Icons.help_outline_rounded),
                            color: isPrediction
                                ? AppTheme.tempColor
                                : (corroborated
                                      ? AppTheme.hrColor
                                      : AppTheme.textSec),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  detectedAt > 0
                                      ? fmt.format(
                                          DateTime.fromMillisecondsSinceEpoch(
                                            detectedAt,
                                          ),
                                        )
                                      : 'Unknown time',
                                  style: AppTypography.inter(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  isPrediction
                                      ? 'Predicted fall risk'
                                      : (corroborated
                                            ? 'Confirmed by $source'
                                            : 'Not confirmed'),
                                  style: AppTypography.inter(
                                    color: AppTheme.textSec,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${(confidence * 100).toInt()}%',
                            style: AppTypography.inter(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
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

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.div),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.card2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: const Color(0xFFAAAAAA), size: 17),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: AppTypography.inter(
                        color: AppTheme.textSec,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Transform.scale(
              scale: 0.85,
              child: Switch(value: value, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}
