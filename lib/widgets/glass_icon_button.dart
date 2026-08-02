import 'dart:ui';

import 'package:flutter/material.dart';

/// Apple-style frosted-glass circular icon button (36px default).
///
/// Translucent white fill, hairline border, backdrop blur, soft shadow —
/// matches the iOS dark-mode "glass" controls used for back/tick actions.
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final Color? iconColor;

  const GlassIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 36,
    this.iconSize = 16,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        shape: CircleBorder(
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.09),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
                ),
                child: Icon(
                  icon,
                  size: iconSize,
                  color: iconColor ?? Colors.white.withValues(alpha: 0.92),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
