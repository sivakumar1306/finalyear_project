import 'package:flutter/material.dart';

const Color kCard = Color(0xFF141414);
const Color kBorder = Color(0xFF242424);
const Color kSec = Color(0xFF666666);
const Color kSec2 = Color(0xFF888888);
const Color kGrid = Color(0xFF222222);

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: child,
    );
  }
}
