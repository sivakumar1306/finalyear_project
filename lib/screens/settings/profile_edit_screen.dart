import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  bool _loading = true;
  bool _saving = false;

  String _name = '';
  String _gender = '';
  int _age = 0;
  int _heightCm = 0;
  double _weightKg = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
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
          });
        }
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() => _saving = true);
    try {
      await SupabaseService.upsertProfile(
        userId: user.id,
        fullName: _name,
        age: _age,
        gender: _gender,
        heightCm: _heightCm,
        weightKg: _weightKg,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile saved', style: GoogleFonts.inter()),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e', style: GoogleFonts.inter()),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
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
        title: 'Nickname',
        controller: ctrl,
        keyboardType: TextInputType.name,
      ),
    );
    if (result != null) setState(() => _name = result);
  }

  void _editGender() async {
    final options = ['Male', 'Female', 'Other'];
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _PickerDialog(
        title: 'Gender',
        options: options,
        selected: _gender,
      ),
    );
    if (result != null) setState(() => _gender = result);
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
      if (v != null) setState(() => _age = v);
    }
  }

  void _editHeight() async {
    final ctrl = TextEditingController(text: _heightCm > 0 ? _heightCm.toString() : '');
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _InputDialog(
        title: 'Height',
        controller: ctrl,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        suffix: 'cm',
      ),
    );
    if (result != null) {
      final v = int.tryParse(result);
      if (v != null) setState(() => _heightCm = v);
    }
  }

  void _editWeight() async {
    final ctrl = TextEditingController(
        text: _weightKg > 0 ? _weightKg.toStringAsFixed(1) : '');
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _InputDialog(
        title: 'Weight',
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,1}'))],
        suffix: 'kg',
      ),
    );
    if (result != null) {
      final v = double.tryParse(result);
      if (v != null) setState(() => _weightKg = v);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Profile',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.gold,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check_rounded, color: Colors.white, size: 24),
              onPressed: _save,
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
                  const SizedBox(height: 28),
                  Text(
                    'PROFILE',
                    style: GoogleFonts.inter(
                      color: AppTheme.textSec,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                    ),
                  ),
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
                          value: _name.isNotEmpty ? _name : '—',
                          onTap: _editName,
                        ),
                        _divider(),
                        _ProfileRow(
                          icon: Icons.transgender_rounded,
                          label: 'Gender',
                          value: _gender.isNotEmpty ? _gender : '—',
                          onTap: _editGender,
                        ),
                        _divider(),
                        _ProfileRow(
                          icon: Icons.cake_outlined,
                          label: 'Age',
                          value: _age > 0 ? '$_age years' : '—',
                          onTap: _editAge,
                        ),
                        _divider(),
                        _ProfileRow(
                          icon: Icons.height_rounded,
                          label: 'Height',
                          value: _heightCm > 0 ? '$_heightCm cm' : '—',
                          onTap: _editHeight,
                        ),
                        _divider(),
                        _ProfileRow(
                          icon: Icons.monitor_weight_outlined,
                          label: 'Weight',
                          value: _weightKg > 0 ? '${_weightKg.toStringAsFixed(1)} kg' : '—',
                          onTap: _editWeight,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _divider() => const Divider(height: 1, color: AppTheme.div);
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.value,
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
              child: Icon(icon, color: const Color(0xFFAAAAAA), size: 17),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            Text(
              value,
              style: GoogleFonts.inter(color: AppTheme.textSec, fontSize: 13),
            ),
          ],
        ),
      ),
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
      title: Text(title,
          style: GoogleFonts.inter(
              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
      content: TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        autofocus: true,
        style: GoogleFonts.inter(color: Colors.white),
        decoration: InputDecoration(
          suffixText: suffix,
          suffixStyle: GoogleFonts.inter(color: AppTheme.textSec),
          enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppTheme.div)),
          focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppTheme.gold)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textSec)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: Text('OK',
              style: GoogleFonts.inter(
                  color: AppTheme.gold, fontWeight: FontWeight.w600)),
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
      title: Text(widget.title,
          style: GoogleFonts.inter(
              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
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
                    child: Text(opt,
                        style: GoogleFonts.inter(
                          color: selected ? AppTheme.gold : Colors.white,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          fontSize: 15,
                        )),
                  ),
                  if (selected)
                    const Icon(Icons.check_rounded, color: AppTheme.gold, size: 18),
                ],
              ),
            ),
          );
        }).toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textSec)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _current),
          child: Text('OK',
              style: GoogleFonts.inter(
                  color: AppTheme.gold, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
