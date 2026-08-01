import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import 'profile_edit_screen.dart';

class AccountSystemSettingsScreen extends StatelessWidget {
  const AccountSystemSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final email = SupabaseService.currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: const GlassBackButton(),
        title: Text(
          'Account & System settings',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 28),
            _sectionLabel('ACCOUNT SETTINGS'),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _AccountRow(
                    icon: Icons.person_outline_rounded,
                    title: 'Edit Profile',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfileEditScreen()),
                    ),
                  ),
                  _divider(),
                  _AccountRow(
                    icon: Icons.person_rounded,
                    title: 'Account',
                    value: email,
                  ),
                  _divider(),
                  _AccountRow(
                    icon: Icons.lock_outline_rounded,
                    title: 'Password',
                    value: '*** ****',
                  ),
                  _divider(),
                  _AccountRow(
                    icon: Icons.edit_outlined,
                    title: 'Change Password',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _AccountRow(
                    icon: Icons.logout_rounded,
                    title: 'Log out',
                    onTap: () => _confirmLogout(context),
                  ),
                  _divider(),
                  _AccountRow(
                    icon: Icons.delete_outline_rounded,
                    title: 'Delete account',
                    titleColor: AppTheme.danger,
                    iconColor: AppTheme.danger,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            _sectionLabel('SYSTEM SETTINGS'),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _AccountRow(
                    icon: Icons.settings_backup_restore_rounded,
                    title: 'Factory reset',
                  ),
                  _divider(),
                  _AccountRow(
                    icon: Icons.power_settings_new_rounded,
                    title: 'Shut down ring',
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

  Widget _sectionLabel(String text) => Text(
        text,
        style: GoogleFonts.inter(
          color: AppTheme.textSec,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
        ),
      );

  Widget _divider() => const Divider(height: 1, color: AppTheme.div);

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Log out',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
        content: Text(
            'Logging out clears your session and all personal data stored on this device (health history, emergency contacts, ring pairing). Are you sure?',
            style: GoogleFonts.inter(color: AppTheme.textSec)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textSec)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Log out',
                style: GoogleFonts.inter(
                    color: AppTheme.danger, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await SupabaseService.logoutAndClearLocalData();
      if (context.mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
      }
    }
  }
}

class _AccountRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? value;
  final Color? titleColor;
  final Color? iconColor;
  final VoidCallback? onTap;

  const _AccountRow({
    required this.icon,
    required this.title,
    this.value,
    this.titleColor,
    this.iconColor,
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
              child: Icon(icon, color: iconColor ?? const Color(0xFFAAAAAA), size: 17),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.inter(
                  color: titleColor ?? Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            if (value != null)
              Text(
                value!,
                style: GoogleFonts.inter(color: AppTheme.textSec, fontSize: 13),
              )
            else if (onTap != null)
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textSec, size: 20),
          ],
        ),
      ),
    );
  }
}
