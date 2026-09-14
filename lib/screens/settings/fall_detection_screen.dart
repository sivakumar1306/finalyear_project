import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
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
import '../../widgets/glass_pill.dart';
import 'fall_detection_widgets.dart';

// Local-only (SharedPreferences), same pattern as device_name/device_address in
// BleProvider — no backend table for these two fields yet, just a single local user.
const _kAddressPrefKey = 'fall_emergency_address';
const _kInstructionsPrefKey = 'fall_emergency_instructions';
const _kDefaultAddress = '';

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
  FallTier? _debugTier;
  FallTier? _ignoredForTier;

  bool _simulateConnection = false;

  // Persisted natively (Room), not widget state — fetched on load, seeded with two
  // defaults the first time the table is empty.
  List<EmergencyContact> _contacts = [];
  bool _loadingContacts = true;

  String _address = _kDefaultAddress;
  String _instructions = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialHighAlert) _debugTier = FallTier.high;
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
            (r) => EmergencyContact(
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
  }

  FallTier _tierFromScore(int score) {
    if (score >= 55) return FallTier.high;
    if (score >= 25) return FallTier.medium;
    return FallTier.low;
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
      builder: (_) => FallHistorySheet(events: events),
    );
  }

  // Call opens the dialer for the primary contact. Message uses Android SmsManager to
  // send immediately to **all** saved emergency contacts (true background send).
  Future<void> _alertContact() async {
    if (_contacts.isEmpty) {
      showGlassPill(context, 'No emergency contact saved yet');
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
          AlertContactSheet(contact: contact, contactCount: _contacts.length),
    );
    if (action == null || !mounted) return;

    if (action == 'call') {
      final uri = Uri(scheme: 'tel', path: phone);
      final ok = await launchUrl(uri);
      if (!ok && mounted) {
        showGlassPill(context, 'Could not reach $phone', type: GlassPillType.error);
      }
      return;
    }

    // Message — SmsManager to every contact, no messaging-app UI.
    final ble = context.read<BleProvider>();
    final result = await ble.sendEmergencySms();
    if (!mounted) return;
    final ok = result['ok'] == true;
    final queued = (result['queuedCount'] as num?)?.toInt() ?? 0;
    final err = result['error'] as String?;
    showGlassPill(
      context,
      ok
          ? 'Sending emergency SMS to $queued contact${queued == 1 ? '' : 's'}… delivery is confirmed as it arrives'
          : (err ?? 'Failed to send emergency SMS'),
      type: ok ? GlassPillType.info : GlassPillType.error,
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
              ActionRow(
                icon: Icons.check_circle_outline,
                label: 'I\'m okay (False Alarm)',
                onTap: () => Navigator.pop(context, 'false_alarm'),
              ),
              const SizedBox(height: 8),
              ActionRow(
                icon: Icons.sports_martial_arts,
                label: 'I was just exercising',
                onTap: () => Navigator.pop(context, 'exercising'),
              ),
              const SizedBox(height: 8),
              ActionRow(
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

    setState(() => _ignoredForTier = FallTier.high);
    if (!mounted) return;
    await context.read<BleProvider>().dismissFallPredictionBanner();
    if (!mounted) return;
    context.read<FallPredictionProvider>().simulateTier('clear');
  }

  Future<void> _addContact() async {
    final nameCtl = TextEditingController();
    final phoneCtl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => FormDialog(
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

  Future<void> _editContact(EmergencyContact contact) async {
    final nameCtl = TextEditingController(text: contact.name);
    final phoneCtl = TextEditingController(text: contact.phone);
    final ble = context.read<BleProvider>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => FormDialog(
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
      builder: (_) => FormDialog(
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
      builder: (_) => FormDialog(
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
        showGlassPill(context, 'Phone permission is required to auto-call your emergency contact', type: GlassPillType.error);
        await ble.setAutoCallOnFallEnabled(false);
        return;
      }
    }
    await ble.setAutoCallOnFallEnabled(enabled);
    if (!mounted) return;
    showGlassPill(
      context,
      enabled ? 'Auto-call on fall detection enabled' : 'Auto-call on fall detection disabled',
    );
  }

  Future<void> _onAutoCallPredictionToggle(bool enabled) async {
    final ble = context.read<BleProvider>();
    if (enabled) {
      final status = await Permission.phone.request();
      if (!status.isGranted) {
        if (!mounted) return;
        showGlassPill(context, 'Phone permission is required to auto-call your emergency contact', type: GlassPillType.error);
        await ble.setAutoCallOnFallPredictionEnabled(false);
        return;
      }
    }
    await ble.setAutoCallOnFallPredictionEnabled(enabled);
    if (!mounted) return;
    showGlassPill(
      context,
      enabled ? 'Auto-call on fall prediction enabled' : 'Auto-call on fall prediction disabled',
    );
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final fallProvider = context.watch<FallPredictionProvider>();
    final realScore = fallProvider.currentResult?.frs24.value.toInt() ?? 0;
    final tier = _debugTier ?? _tierFromScore(realScore);

    final String message = ble.fallPredictionMessage.isNotEmpty
        ? ble.fallPredictionMessage
        : 'Your heart rate rose to 122 BPM while you seemed to be in-active for the last 10 minutes.'; // Fallback
    
    final showAlert = tier != FallTier.low && _ignoredForTier != tier;

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
                    _debugTier = FallTier.high;
                    _ignoredForTier = null;
                  });
                  break;
                case 'medium':
                  context.read<FallPredictionProvider>().simulateTier('medium');
                  setState(() {
                    _debugTier = FallTier.medium;
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
                  showGlassPill(context, 'Mock data cleared! Restart the app to refresh all UI.', type: GlassPillType.success);
                  break;
                case 'notify':
                  context.read<BleProvider>().simulateFallEvent();
                  context.read<BleProvider>().refreshEmergencySmsStatus();
                  break;
                case 'risk_trigger':
                  _simulateRiskTrigger();
                  break;
                case 'prediction':
                  context.read<BleProvider>().simulateFallPrediction();
                  context.read<BleProvider>().refreshEmergencySmsStatus();
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
            HeroCard(
              tier: ble.emergencySmsActive ? FallTier.high : tier,
              message: message,
              smsSecondsRemaining: ble.emergencySmsActive
                  ? ble.emergencySmsSecondsRemaining
                  : null,
              smsHasPermission: ble.emergencySmsHasPermission,
              onPrimaryAction:
                  (ble.emergencySmsActive || tier == FallTier.high)
                  ? _alertContact
                  : () {
                      setState(() => _ignoredForTier = tier);
                      context.read<BleProvider>().dismissFallPredictionBanner();
                      context.read<FallPredictionProvider>().simulateTier('clear');
                    },
            ),
            const SizedBox(height: 20),
            SectionLabel(
              (ble.emergencySmsActive || tier == FallTier.high)
                  ? 'OTHER ACTIONS'
                  : 'RECOMMENDED ACTIONS',
            ),
            const SizedBox(height: 8),
            if (ble.emergencySmsActive)
              ActionRow(
                icon: Icons.sms_failed_outlined,
                label:
                    'Cancel emergency SMS (${ble.emergencySmsSecondsRemaining}s)',
                onTap: _ignoreWarning,
              )
            else
              ActionRow(
                icon: tier == FallTier.high
                    ? Icons.close_rounded
                    : Icons.call_rounded,
                label: tier == FallTier.high
                    ? 'Ignore warning'
                    : 'Alert emergency contact',
                onTap: tier == FallTier.high ? _ignoreWarning : _alertContact,
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
            FallRiskScoreCard(
              onTapRiskDetails: () {
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
              onTapHeartRate: () => Navigator.pushNamed(context, '/heart-rate'),
              onTapTemperature: () => Navigator.pushNamed(context, '/temperature'),
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
            ActionRow(
              icon: Icons.visibility_outlined,
              label: 'Simulate Connected UI',
              onTap: () => setState(() => _simulateConnection = true),
            ),
            const SizedBox(height: 20),
          ],
          ActionRow(
            icon: Icons.directions_run_rounded,
            label: 'View Fall history',
            onTap: _openFallHistory,
          ),
          const SizedBox(height: 12),
          ToggleRow(
            icon: Icons.phone_in_talk_rounded,
            title: 'Auto-call on fall detection',
            value: ble.autoCallOnFallEnabled,
            onChanged: _onAutoCallToggle,
          ),
          const SizedBox(height: 12),
          ToggleRow(
            icon: Icons.phone_in_talk_rounded,
            title: 'Auto call on fall prediction',
            value: ble.autoCallOnFallPredictionEnabled,
            onChanged: _onAutoCallPredictionToggle,
          ),
          const SizedBox(height: 20),
          const SectionLabel('EMERGENCY DETAILS'),
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
                child: ContactRow(
                  contact: e.value,
                  onTap: () => _editContact(e.value),
                ),
              ),
            ),
          ActionRow(
            icon: Icons.add_rounded,
            label: 'Add a new contact',
            onTap: _addContact,
          ),
          const SizedBox(height: 20),
          const SectionLabel('ADDRESS'),
          const SizedBox(height: 8),
          EditableRow(label: 'Address', value: _address.isEmpty ? 'Add' : _address, onTap: _editAddress),
          const SizedBox(height: 8),
          EditableRow(
            label: 'Additional instructions',
            value: _instructions.isEmpty ? 'Add' : _instructions,
            onTap: _editInstructions,
          ),
        ],
      ),
    );
  }
}

