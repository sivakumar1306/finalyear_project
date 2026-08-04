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
        decoration: decoration,
        decorationColor: decorationColor,
        fontStyle: fontStyle,
        shadows: shadows,
        overflow: overflow,
      );
}
