import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/incident_service.dart';
import '../../services/supabase_service.dart';
import '../../services/unit_prefs.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/glass_icon_button.dart';
import '../auth/login_screen.dart';
import 'account_system_settings_screen.dart';
import 'settings_screen.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/glass_pill.dart';
import '../../widgets/footer_spacer.dart';

class ProfileEditScreen extends StatefulWidget {
  final bool showBackButton;
  const ProfileEditScreen({super.key, this.showBackButton = true});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _EmergencyContact {
  final int? id;
  final String name;
  final String phone;
  _EmergencyContact({this.id, required this.name, required this.phone});
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  bool _loading = true;
  bool _saving = false;

  String _name = '';
  String _gender = '';
  int _age = 0;
  int _heightCm = 0;
  double _weightKg = 0;
  UnitSystem _unitSystem = UnitSystem.metric;

  // Emergency Details — same Room-backed data as Fall Prediction (BleProvider),
  // not a separate copy, so edits stay consistent across both screens.
  List<_EmergencyContact> _contacts = [];

  String _phone = '';
  String _address = '';
  String _instructions = '';
  String _defaultEmergencyContact = '101';

  bool get _loggedIn => SupabaseService.isLoggedIn;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    if (_loggedIn) _loadContacts();
    UnitPrefs.loadSystem().then((s) {
      if (mounted) setState(() => _unitSystem = s);
    });
  }

  Future<void> _loadProfile() async {
    try {
      final user = SupabaseService.currentUser;
      if (user != null) {
        final p = await SupabaseService.getProfile(user.id);
        if (mounted && p != null) {
          setState(() {
            _name = (p['full_name'] as String?) ?? '';
            _gender = (p['gender'] as String?) ?? '';
            _age = (p['age'] as int?) ?? 0;
            _heightCm = (p['height_cm'] as int?) ?? 0;
            _weightKg = ((p['weight_kg'] as num?) ?? 0).toDouble();
            _phone = (p['phone'] as String?) ?? '';
            _address = (p['address'] as String?) ?? '';
            _instructions = (p['additional_instructions'] as String?) ?? '';
            _defaultEmergencyContact =
                (p['default_emergency_contact'] as String?) ?? '101';
          });
        }
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'profile_edit_screen',
        error: e,
        stackTrace: st,
        customMessage: '_loadProfile failed',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadContacts() async {
    final ble = context.read<BleProvider>();
    await ble.syncEmergencyContactsFromCloud();
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
    });
  }

  Future<void> _autoSave() async {
    final user = SupabaseService.currentUser;
    if (user == null || _saving) return;
    setState(() => _saving = true);
    try {
      await SupabaseService.upsertProfile(
        userId: user.id,
        fullName: _name,
        age: _age,
        gender: _gender,
        heightCm: _heightCm,
        weightKg: _weightKg,
        address: _address,
        phone: _phone,
        additionalInstructions: _instructions,
        defaultEmergencyContact: _defaultEmergencyContact,
      );
    } catch (e) {
      if (mounted) {
        showGlassPill(context, 'Failed to save: $e', type: GlassPillType.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _editName() async {
    final ctrl = TextEditingController(text: _name);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _InputDialog(
        title: 'Name',
        controller: ctrl,
        keyboardType: TextInputType.name,
      ),
    );
    if (result != null && result != _name) {
      setState(() => _name = result);
      await _autoSave();
    }
  }

  void _editGender() async {
    final options = ['Male', 'Female', 'Other'];
    final result = await showDialog<String>(
      context: context,
      builder: (_) =>
          _PickerDialog(title: 'Gender', options: options, selected: _gender),
    );
    if (result != null && result != _gender) {
      setState(() => _gender = result);
      await _autoSave();
    }
  }

  void _editAge() async {
    final ctrl = TextEditingController(text: _age > 0 ? _age.toString() : '');
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _InputDialog(
        title: 'Age',
        controller: ctrl,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        suffix: 'years',
      ),
    );
    if (result != null) {
      final v = int.tryParse(result);
      if (v != null && v != _age) {
        setState(() => _age = v);
        await _autoSave();
      }
    }
  }

  bool get _useUs => _unitSystem == UnitSystem.us;

  void _editHeight() async {
    final displayVal = _useUs
        ? UnitPrefs.cmToInches(_heightCm.toDouble())
        : _heightCm.toDouble();
    final ctrl = TextEditingController(
      text: _heightCm > 0 ? displayVal.round().toString() : '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _InputDialog(
        title: 'Height',
        controller: ctrl,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        suffix: _useUs ? 'in' : 'cm',
      ),
    );
    if (result != null) {
      final v = int.tryParse(result);
      if (v != null) {
        final next = _useUs
            ? UnitPrefs.inchesToCm(v.toDouble()).round()
            : v;
        if (next != _heightCm) {
          setState(() => _heightCm = next);
          await _autoSave();
        }
      }
    }
  }

  void _editWeight() async {
    final displayVal = _useUs ? UnitPrefs.kgToLbs(_weightKg) : _weightKg;
    final ctrl = TextEditingController(
      text: _weightKg > 0 ? displayVal.toStringAsFixed(1) : '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _InputDialog(
        title: 'Weight',
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,1}')),
        ],
        suffix: _useUs ? 'lbs' : 'kg',
      ),
    );
    if (result != null) {
      final v = double.tryParse(result);
      if (v != null) {
        final next = _useUs ? UnitPrefs.lbsToKg(v) : v;
        if (next != _weightKg) {
          setState(() => _weightKg = next);
          await _autoSave();
        }
      }
    }
  }

  void _editPhone() async {
    final ctrl = TextEditingController(text: _phone);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _InputDialog(
        title: 'Phone',
        controller: ctrl,
        keyboardType: TextInputType.phone,
      ),
    );
    if (result != null && result != _phone) {
      setState(() => _phone = result);
      await _autoSave();
    }
  }

  void _editDefaultEmergencyContact() async {
    final ctrl = TextEditingController(text: _defaultEmergencyContact);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _InputDialog(
        title: 'Default Emergency Contact',
        controller: ctrl,
        keyboardType: TextInputType.phone,
      ),
    );
    if (result != null && result != _defaultEmergencyContact) {
      setState(() => _defaultEmergencyContact = result);
      await _autoSave();
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
    final next = ctl.text.trim();
    if (next == _address) return;
    setState(() => _address = next);
    await _autoSave();
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        automaticallyImplyLeading: false,
        leading: widget.showBackButton
            ? const Padding(
                padding: EdgeInsets.only(left: 16),
                child: Center(
                  child: GlassBackButton(),
                ),
              )
            : null,
        title: Text(
          'Profile',
          style: AppTypography.inter(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: GlassIconButton(
                icon: Icons.settings_outlined,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SettingsScreen(showBackButton: true),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.gold))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  _buildTopAccountCard(),
                  const SizedBox(height: 24),
                  _sectionHeader('ABOUT YOU', showEdit: false),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.card,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        _ProfileRow(
                          icon: Icons.person_outline_rounded,
                          label: 'Name',
                          value: _name.isNotEmpty ? _name : 'Sundr',
                          onTap: _editName,
                        ),
                        _divider(),
                        _ProfileRow(
                          icon: Icons.edit_outlined,
                          label: 'Gender',
                          value: _gender.isNotEmpty ? _gender : 'Male',
                          onTap: _editGender,
                        ),
                        _divider(),
                        _ProfileRow(
                          icon: Icons.calendar_today_outlined,
                          label: 'Birthday',
                          value: _age > 0 ? '$_age years' : '—',
                          onTap: _editAge,
                        ),
                        _divider(),
                        _ProfileRow(
                          icon: Icons.height_rounded,
                          label: 'Height',
                          value: _heightCm > 0
                              ? UnitPrefs.formatHeightCm(_heightCm, _unitSystem)
                              : "5' 11\"",
                          onTap: _editHeight,
                        ),
                        _divider(),
                        _ProfileRow(
                          icon: Icons.monitor_weight_outlined,
                          label: 'Weight',
                          value: _weightKg > 0
                              ? UnitPrefs.formatWeightKg(_weightKg, _unitSystem)
                              : '89 kg',
                          onTap: _editWeight,
                        ),
                        _divider(),
                        _ProfileRow(
                          icon: Icons.phone_outlined,
                          label: 'Phone',
                          value: _phone.isNotEmpty
                              ? _phone
                              : '+91 000 000 0000',
                          onTap: _editPhone,
                        ),
                        _divider(),
                        _ProfileRow(
                          icon: Icons.location_on_outlined,
                          label: 'Address',
                          value: _address.isNotEmpty
                              ? _address
                              : 'Flat 101, SingleBar avenue....',
                          onTap: _editAddress,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _sectionHeader('EMERGENCY DETAILS', showEdit: false),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.card,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        _ProfileRow(
                          icon: Icons.local_hospital_outlined,
                          label: 'Default Emergency Contact',
                          value: _defaultEmergencyContact.isNotEmpty
                              ? _defaultEmergencyContact
                              : '101',
                          onTap: _editDefaultEmergencyContact,
                        ),
                        for (var i = 0; i < _contacts.length; i++) ...[
                          _divider(),
                          _ContactRow(
                            contact: _contacts[i],
                            onTap: () => _editContact(_contacts[i]),
                          ),
                        ],
                        _divider(),
                        _AccountActionRow(
                          icon: Icons.add_rounded,
                          label: 'Add a new contact',
                          onTap: _addContact,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (!widget.showBackButton) const FooterSpacer(),
                  if (widget.showBackButton) const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _sectionHeader(String title, {bool showEdit = true, VoidCallback? onEditTap}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: AppTypography.inter(
            color: AppTheme.textSec,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
        if (showEdit)
          GestureDetector(
            onTap: onEditTap,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                children: [
                  Text(
                    'Edit',
                    style: AppTypography.inter(
                      color: AppTheme.textSec,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.edit_outlined,
                    color: AppTheme.textSec,
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTopAccountCard() {
    final email = SupabaseService.currentUser?.email ?? 'AccountName@email.com';
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (_loggedIn) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AccountSystemSettingsScreen(),
              ),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: AppTheme.card2,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  color: AppTheme.gold,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  email,
                  style: AppTypography.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.textSec,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, color: AppTheme.div);
}

class _AccountActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AccountActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.card2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppTheme.iconFaint, size: 17),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: AppTypography.inter(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.card2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppTheme.iconFaint, size: 17),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: AppTypography.inter(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              value,
              textAlign: TextAlign.right,
              style: AppTypography.inter(color: AppTheme.textSec, fontSize: 13),
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
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.card2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.local_hospital_outlined,
                color: AppTheme.iconFaint,
                size: 17,
              ),
            ),
            const SizedBox(width: 14),
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

class _InputDialog extends StatelessWidget {
  final String title;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? suffix;

  const _InputDialog({
    required this.title,
    required this.controller,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.card2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        title,
        style: AppTypography.inter(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
      content: TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        autofocus: true,
        style: AppTypography.inter(color: Colors.white),
        decoration: InputDecoration(
          suffixText: suffix,
          suffixStyle: AppTypography.inter(color: AppTheme.textSec),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: AppTheme.div),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: AppTheme.gold),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: AppTypography.inter(color: AppTheme.textSec),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: Text(
            'OK',
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

class _PickerDialog extends StatefulWidget {
  final String title;
  final List<String> options;
  final String selected;

  const _PickerDialog({
    required this.title,
    required this.options,
    required this.selected,
  });

  @override
  State<_PickerDialog> createState() => _PickerDialogState();
}

class _PickerDialogState extends State<_PickerDialog> {
  late String _current;

  @override
  void initState() {
    super.initState();
    _current = widget.options.contains(widget.selected)
        ? widget.selected
        : widget.options.first;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.card2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.title,
        style: AppTypography.inter(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: widget.options.map((opt) {
          final selected = opt == _current;
          return InkWell(
            onTap: () => setState(() => _current = opt),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      opt,
                      style: AppTypography.inter(
                        color: selected ? AppTheme.gold : Colors.white,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (selected)
                    const Icon(
                      Icons.check_rounded,
                      color: AppTheme.gold,
                      size: 18,
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: AppTypography.inter(color: AppTheme.textSec),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _current),
          child: Text(
            'OK',
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
