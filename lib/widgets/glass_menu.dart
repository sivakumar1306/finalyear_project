import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A single row in a [showGlassMenu] dropdown.
class GlassMenuItem {
  final String label;
  final VoidCallback onTap;
  const GlassMenuItem({required this.label, required this.onTap});
}

const double _kMenuWidth = 166.5;

/// Anchored glassmorphic dropdown menu — per DESIGN.md's soft-glassmorphism
/// card spec (blur, translucent surface, hairline border), used for
/// contextual "..." menus. Opens below [anchorKey]'s widget, shifted left.
Future<void> showGlassMenu({
  required BuildContext context,
  required GlobalKey anchorKey,
  required List<GlassMenuItem> items,
}) async {
  final anchorBox = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  final overlayBox =
      Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
  if (anchorBox == null || overlayBox == null) return;

  final anchorRect =
      anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox) &
          anchorBox.size;
  final overlayRect = Offset.zero & overlayBox.size;

  final menuAnchorRect = Rect.fromLTWH(
    anchorRect.left,
    anchorRect.bottom + 8.0,
    anchorRect.width,
    0,
  );

  final position = RelativeRect.fromRect(menuAnchorRect, overlayRect);

  await showMenu<void>(
    context: context,
    position: position,
    color: Colors.transparent,
    elevation: 0,
    shadowColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    constraints: const BoxConstraints.tightFor(width: _kMenuWidth),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(20)),
    ),
    items: [
      PopupMenuItem<void>(
        padding: EdgeInsets.zero,
        // Disabling the built-in tap keeps the outer PopupMenuItem from
        // eating/duplicating the row taps below — each row closes the menu
        // and fires its own callback explicitly instead.
        enabled: false,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              width: _kMenuWidth,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.09),
                  width: 0.5,
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final item in items)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                          item.onTap();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 13,
                          ),
                          child: Text(
                            item.label,
                            textAlign: TextAlign.left,
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.92),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
