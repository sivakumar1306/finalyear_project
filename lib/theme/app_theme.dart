import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // ---- Surfaces ----
  static const Color bg = Color(0xFF050505);
  static const Color surfaceDeep = Color(0xFF141414);
  static const Color surfaceMid = Color(0xFF1E1E1E);
  static const Color surfaceRaised = Color(0xFF2A2A2A);
  static const Color surfaceWarm = Color(0xFF16130E);
  static const Color card = Color(0xFF111111);
  static const Color card2 = Color(0xFF1A1A1A);
  static const Color div = Color(0xFF242424);
  static const Color dividerSoft = Color(0xFF2E2E2E);
  static const Color grid = Color(0xFF222222);
  static const Color bgDim = Color(0xD9050505);
  static const Color bgFaint = Color(0xED050505);

  // ---- Brand accent ----
  static const Color gold = Color(0xFFC9A86E);
  static const Color goldBorder = Color(0xFF3A2A08);
  static const Color goldTransparent = Color(0x00C9A86E);
  static const Color goldGlow = Color(0x0DC9A86E);
  static const Color goldTint = Color(0x33C9A86E);
  static const Color goldPale = Color(0xFFE8D3A7);
  static const Color goldMuted = Color(0xFFE0BC85);
  static const Color goldDark = Color(0xFF8A6B34);
  static const Color goldDusk = Color(0xFF8E7A55);
  static const Color amber = Color(0xFFFBBF24);

  // ---- Text & icons ----
  static const Color textPrimary = Colors.white;
  static const Color textSec = Color(0xFF888888);
  static const Color textTertiary = Color(0xFF666666);
  static const Color iconMuted = Color(0xFF999999);
  static const Color iconFaint = Color(0xFFAAAAAA);

  // ---- Glass surfaces (DESIGN.md) ----
  static const Color glassCard = Color(0x0FFFFFFF); // card fill, 6%
  static const Color glassBorder = Color(0x17FFFFFF); // card border, 9%
  static const Color glassButton = Color(0x08FFFFFF); // button fill, 3%
  static const Color glassButtonBorder = Color(0x14FFFFFF); // button border, 8%
  static const Color gridLine = Color(0x0DFFFFFF); // chart grid, 5%

  // ---- White opacity scale ----
  static const Color white04 = Color(0x0AFFFFFF);
  static const Color white10 = Color(0x1AFFFFFF);
  static const Color white15 = Color(0x26FFFFFF);
  static const Color white40 = Color(0x66FFFFFF);
  static const Color white42 = Color(0x6BFFFFFF);
  static const Color white45 = Color(0x73FFFFFF);
  static const Color white50 = Color(0x80FFFFFF);
  static const Color white52 = Color(0x85FFFFFF);
  static const Color white60 = Color(0x99FFFFFF);
  static const Color white85 = Color(0xD9FFFFFF);
  static const Color white92 = Color(0xEBFFFFFF);
  static const Color white93 = Color(0xEDFFFFFF);
  static const Color white96 = Color(0xF5FFFFFF);

  // ---- Feedback ----
  static const Color success = Color(0xFF34D399);
  static const Color danger = Color(0xFFEF4444);
  static const Color focus = Color(0xFFE08A4A);

  // ---- Metric colors (active) ----
  static const Color hrColor = Color(0xFFFF4757);
  static const Color sleepColor = Color(0xFF8B5CF6);
  static const Color stressColor = Color(0xFFF97316);
  static const Color hrvColor = Color(0xFF2DD4BF);
  static const Color spo2Color = Color(0xFF38BDF8);
  static const Color bpColor = Color(0xFF818CF8);
  static const Color tempColor = Color(0xFFFBBF24);
  static const Color womenColor = Color(0xFFEC4899);
  static const Color stepsColor = Color(0xFFF59E0B);

  // ---- Sleep stages ----
  static const Color sleepAwake = Color(0xFFFFE99C);
  static const Color sleepLight = Color(0xFF9B85FF);
  static const Color sleepDeep = Color(0xFF6719FE);

  // ---- Activity ----
  static const Color softBlue = Color(0xFF60A5FA);
  static const Color softGreen = Color(0xFF4ADE80);
  static const Color softOrange = Color(0xFFFB923C);
  static const Color warmOrange = Color(0xFFFF6B35);
  static const Color softViolet = Color(0xFFC084FC);

  // ---- Base spacing / radius tokens (DESIGN.md: padding 16px, card radius 20px) ----
  static const double kPad = 16;
  static const double kRadiusCard = 20;

  static ThemeData darkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        primary: gold,
        secondary: gold,
        surface: card,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.black : Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? gold : const Color(0xFF3A3A3A)),
      ),
      dividerColor: div,
      useMaterial3: true,
    );
  }
}