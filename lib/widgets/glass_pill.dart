import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'app_typography.dart';

/// Glassmorphism pill notification that drops from the top of the screen.
/// Matches DevicePill design tokens.
///
/// Usage:
///   showGlassPill(context, 'Settings saved');
///   showGlassPill(context, 'Connection failed', isError: true);
enum GlassPillType { success, error, info }

void showGlassPill(
  BuildContext context,
  String message, {
  GlassPillType type = GlassPillType.info,
  Duration duration = const Duration(seconds: 5),
}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _GlassPillOverlay(
      message: message,
      type: type,
      duration: duration,
      onDismiss: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _GlassPillOverlay extends StatefulWidget {
  final String message;
  final GlassPillType type;
  final Duration duration;
  final VoidCallback onDismiss;

  const _GlassPillOverlay({
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_GlassPillOverlay> createState() => _GlassPillOverlayState();
}

class _GlassPillOverlayState extends State<_GlassPillOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnim;
  late Animation<double> _fadeAnim;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnim = Tween<double>(begin: -1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
    _dismissTimer = Timer(widget.duration, _dismiss);
  }

  void _dismiss() {
    if (!mounted) return;
    _controller.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Color get _accentColor {
    switch (widget.type) {
      case GlassPillType.success:
        return AppTheme.success;
      case GlassPillType.error:
        return AppTheme.danger;
      case GlassPillType.info:
        return AppTheme.gold;
    }
  }

  IconData get _icon {
    switch (widget.type) {
      case GlassPillType.success:
        return Icons.check_circle_rounded;
      case GlassPillType.error:
        return Icons.error_rounded;
      case GlassPillType.info:
        return Icons.info_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Positioned(
      top: 0,
      left: 16,
      right: 16,
      // Transparent Material gives the overlay a proper DefaultTextStyle.
      // Without it, Text inherits the fallback style (yellow double
      // underline) since OverlayEntries sit outside any Scaffold/Material.
      child: Material(
        type: MaterialType.transparency,
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, _slideAnim.value * (topPadding + 80)),
              child: Opacity(
                opacity: _fadeAnim.value,
                child: child,
              ),
            );
          },
          child: GestureDetector(
            onTap: _dismiss,
            child: Padding(
              padding: EdgeInsets.only(top: topPadding + 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.glassCard,
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: AppTheme.glassBorder, width: 0.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_icon, color: _accentColor, size: 16),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            widget.message,
                            style: AppTypography.inter(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.none,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
