import 'package:flutter/material.dart';

import 'glass_icon_button.dart';

/// Shared glass back button — [GlassIconButton] with the app's back chevron and
/// a default [Navigator.pop]. Pass [onTap] to override (e.g. `_goBackToHome`).
class GlassBackButton extends StatelessWidget {
  final VoidCallback? onTap;
  final IconData icon;
  final double size;
  final double iconSize;
  final Color? iconColor;

  const GlassBackButton({
    super.key,
    this.onTap,
    this.icon = Icons.arrow_back_ios_new_rounded,
    this.size = 36,
    this.iconSize = 16,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return GlassIconButton(
      icon: icon,
      size: size,
      iconSize: iconSize,
      iconColor: iconColor,
      onTap: onTap ?? () => Navigator.pop(context),
    );
  }
}
