import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ble_provider.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/app_typography.dart';

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
          style: AppTypography.inter(
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
                    onTap: () => _confirmDeleteAccount(context),
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
                    titleColor: AppTheme.danger,
                    iconColor: AppTheme.danger,
                    onTap: () => _confirmFactoryReset(context),
                  ),
                  _divider(),
                  _AccountRow(
                    icon: Icons.power_settings_new_rounded,
                    title: 'Shut down ring',
                    titleColor: AppTheme.danger,
                    iconColor: AppTheme.danger,
                    onTap: () => _confirmShutDownRing(context),
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
        style: AppTypography.inter(
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
            style: AppTypography.inter(color: Colors.white, fontWeight: FontWeight.w600)),
        content: Text(
            'Logging out clears your session and all personal data stored on this device (health history, emergency contacts, ring pairing). Are you sure?',
            style: AppTypography.inter(color: AppTheme.textSec)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: AppTypography.inter(color: AppTheme.textSec)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Log out',
                style: AppTypography.inter(
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

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final passwordController = TextEditingController();
    bool isLoading = false;
    
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: AppTheme.card2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Delete Account',
                style: AppTypography.inter(color: Colors.white, fontWeight: FontWeight.w600)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This action is permanent and cannot be undone. All your health data and settings will be permanently erased. Please enter your password to confirm.',
                  style: AppTypography.inter(color: AppTheme.textSec),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  style: AppTypography.inter(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Password',
                    hintStyle: AppTypography.inter(color: AppTheme.textSec),
                    filled: true,
                    fillColor: AppTheme.card,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              if (!isLoading)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: AppTypography.inter(color: AppTheme.textSec)),
                ),
              TextButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        final password = passwordController.text.trim();
                        if (password.isEmpty) return;
                        
                        setState(() => isLoading = true);
                        try {
                          await SupabaseService.deleteAccount(password);
                          if (context.mounted) {
                            Navigator.pop(context); // close dialog
                            Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
                          }
                        } catch (e) {
                          debugPrint('Error deleting account: $e');
                          setState(() => isLoading = false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: ${e.toString()}')),
                            );
                          }
                        }
                      },
                child: isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.danger))
                    : Text('Delete Permanently',
                        style: AppTypography.inter(color: AppTheme.danger, fontWeight: FontWeight.w600)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmFactoryReset(BuildContext context) async {
    final ble = Provider.of<BleProvider>(context, listen: false);
    if (!ble.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ring is not connected.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Factory Reset Ring',
            style: AppTypography.inter(color: Colors.white, fontWeight: FontWeight.w600)),
        content: Text(
            'This will restore the ring to factory default settings and erase stored ring metrics. Are you sure?',
            style: AppTypography.inter(color: AppTheme.textSec)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: AppTypography.inter(color: AppTheme.textSec)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Reset',
                style: AppTypography.inter(
                    color: AppTheme.danger, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      final success = await ble.factoryReset();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Ring factory reset completed.' : 'Failed to factory reset ring.'),
          ),
        );
      }
    }
  }

  Future<void> _confirmShutDownRing(BuildContext context) async {
    final ble = Provider.of<BleProvider>(context, listen: false);
    if (!ble.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ring is not connected.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Shut Down Ring',
            style: AppTypography.inter(color: Colors.white, fontWeight: FontWeight.w600)),
        content: Text(
            'This will power off the ring. You will need to place it on its charger to turn it back on. Continue?',
            style: AppTypography.inter(color: AppTheme.textSec)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: AppTypography.inter(color: AppTheme.textSec)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Shut Down',
                style: AppTypography.inter(
                    color: AppTheme.danger, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      final success = await ble.shutDownRing();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Shut down command sent to ring.' : 'Failed to shut down ring.'),
          ),
        );
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
                style: AppTypography.inter(
                  color: titleColor ?? Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (value != null)
              Flexible(
                child: Text(
                  value!,
                  style: AppTypography.inter(color: AppTheme.textSec, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textAlign: TextAlign.end,
                ),
              )
            else if (onTap != null)
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textSec, size: 20),
          ],
        ),
      ),
    );
  }
}
