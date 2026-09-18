import 'package:flutter/material.dart';

/// System font text styles. Method name kept for existing call sites.
class AppTypography {
  static const String? fontFamily = null;

  static TextStyle inter({
    double? fontSize,
    FontWeight? fontWeight,
    FontWeight? weight,
    Color? color,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
    Color? decorationColor,
    FontStyle? fontStyle,
    List<Shadow>? shadows,
    TextOverflow? overflow,
  }) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        fontWeight: weight ?? fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
        // Default to no underline so Text rendered outside a Material
        // ancestor (e.g. Overlay toasts) can't inherit the yellow
        // double-underline fallback style. Pass an explicit decoration
        // to opt back into underlining where wanted.
        decoration: decoration ?? TextDecoration.none,
        decorationColor: decorationColor,
        fontStyle: fontStyle,
        shadows: shadows,
        overflow: overflow,
      );
}
