import 'package:flutter/material.dart';

/// A footer spacer widget placed at the bottom of scrollable screens
/// (such as Home Screen and Settings Page) to adjust for the floating
/// bottom navigation bar so all content can be scrolled comfortably above it.
class FooterSpacer extends StatelessWidget {
  final double extraHeight;

  const FooterSpacer({super.key, this.extraHeight = 0.0});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return SizedBox(height: 100.0 + bottomInset + extraHeight);
  }
}
