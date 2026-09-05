import 'package:flutter/material.dart';

class AgroTheme {
  // Paleta CSS
  static const Color colorBg = Color(0xFFF3F5F1);
  static const Color colorSurface = Color(0xFFFFFFFF);
  static const Color colorText = Color(0xFF1B231D);
  static const Color colorTextSecondary = Color(0xFF5F6B62);
  static const Color colorAccent = Color(0xFF1E6B4C);
  static const Color colorAccentDark = Color(0xFF123F2C);
  static const Color colorAccentSoft = Color(0x1A1E6B4C); // rgba(30, 107, 76, 0.10)
  static const Color colorGold = Color(0xFFB8862A);
  static const Color colorGoldSoft = Color(0x24B8862A); // rgba(184, 134, 42, 0.14)
  static const Color colorDanger = Color(0xFFC0483C);
  static const Color colorBorder = Color(0x1A1B231D); // rgba(27, 35, 29, 0.10)

  // Estados interactivos / pulsado
  static const Color colorActiveBg = Color(0xFFFFFDE7);
  static const Color colorActiveBorder = Color(0xFFFBC02D);

  static const double radiusLg = 24.0;
  static const double radiusMd = 14.0;

  static ThemeData get themeData {
    return ThemeData(
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: colorBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: colorAccent,
        surface: colorSurface,
        background: colorBg,
      ),
      useMaterial3: true,
    );
  }
}