import 'package:flutter/material.dart';

import 'glass_icon_button.dart';

/// Shared glass back button — [GlassIconButton] with the app's back chevron and
/// a default [Navigator.pop]. Pass [onTap] to override (e.g. `_goBackToHome`).
class GlassBackButton extends StatelessWidget {
  final VoidCallback? onTap;

  const GlassBackButton({
    super.key,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassIconButton(
      icon: Icons.arrow_back_ios_new_rounded,
      size: 36,
      iconSize: 16,
      onTap: onTap ?? () => Navigator.pop(context),
    );
  }
}
