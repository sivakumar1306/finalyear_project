import 'package:flutter/material.dart';

import 'glass_back_button.dart';
import './app_typography.dart';

/// Shared glass screen header: back button, centered title, optional trailing
/// action — matches the Figma header used across Edit Cards / schedule screens.
class GlassHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  const GlassHeader({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          GlassBackButton(onTap: onBack),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTypography.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.005,
                color: Colors.white.withValues(alpha: 0.88),
              ),
            ),
          ),
          trailing ?? const SizedBox(width: 36),
        ],
      ),
    );
  }
}
