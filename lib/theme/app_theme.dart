import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color bg = Color(0xFF050505);
  static const Color card = Color(0xFF111111);
  static const Color card2 = Color(0xFF1A1A1A);
  static const Color gold = Color(0xFFC9A86E);
  static const Color goldLight = Color(0xFFF0C060);
  static const Color goldBorder = Color(0xFF3A2A08);
  static const Color textPrimary = Colors.white;
  static const Color textSec = Color(0xFF888888);
  static const Color div = Color(0xFF242424);
  static const Color success = Color(0xFF34D399);
  static const Color danger = Color(0xFFEF4444);
  static const Color focus = Color(0xFFE08A4A);
  static const Color base = Color(0xFFC9A86E);

  static const Color goldAccent = Color(0xFFC9A86E);
  static const Color sleepAwake = Color(0xFFFFE99C);
  static const Color sleepLight = Color(0xFF9B85FF);
  static const Color sleepDeep = Color(0xFF6719FE);

  static const Color hrColor = Color(0xFFFF4757);
  static const Color bpColor = Color(0xFF818CF8);
  static const Color spo2Color = Color(0xFF38BDF8);
  static const Color stepsColor = Color(0xFFF59E0B);
  static const Color sleepColor = Color(0xFF8B5CF6);
  static const Color hrvColor = Color(0xFF2DD4BF);
  static const Color stressColor = Color(0xFFF97316);
  static const Color tempColor = Color(0xFFFBBF24);
  static const Color womenColor = Color(0xFFEC4899);

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
