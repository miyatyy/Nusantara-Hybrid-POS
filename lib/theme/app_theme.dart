import 'package:flutter/material.dart';

class AppTheme {
  // Primary Palette: Royal Blue & Electric Cobalt
  static const Color royalBlue = Color(0xFF1E3A8A);
  static const Color cobaltBlue = Color(0xFF2563EB);
  static const Color lightBlueTint = Color(0xFFEFF6FF);
  static const Color blueSubtle = Color(0xFFDBEAFE);

  // Secondary & Accent: Vibrant Golden Amber Yellow
  static const Color goldenAmber = Color(0xFFF59E0B);
  static const Color brightYellow = Color(0xFFFACC15);
  static const Color warmGoldDark = Color(0xFFD97706);
  static const Color yellowSubtle = Color(0xFFFEF3C7);

  // Neutral & Typography
  static const Color darkNavy = Color(0xFF0F172A);
  static const Color slateMuted = Color(0xFF64748B);
  static const Color slateLight = Color(0xFF94A3B8);
  static const Color cardBorder = Color(0xFFE2E8F0);
  static const Color iceBlueScaffold = Color(0xFFF4F7FB);
  static const Color cardBg = Color(0xFFFFFFFF);

  // Status & Utility Colors
  static const Color emeraldGreen = Color(0xFF10B981);
  static const Color roseRed = Color(0xFFEF4444);

  static ThemeData get themeData {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: royalBlue,
        primary: royalBlue,
        onPrimary: Colors.white,
        secondary: goldenAmber,
        onSecondary: darkNavy,
        surface: cardBg,
        onSurface: darkNavy,
      ),
      scaffoldBackgroundColor: iceBlueScaffold,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: royalBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 1.5,
        shadowColor: const Color(0x1A1E3A8A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: cardBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: goldenAmber,
          foregroundColor: darkNavy,
          elevation: 1,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: royalBlue,
          side: const BorderSide(color: royalBlue, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: royalBlue,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        secondaryLabelStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
        side: const BorderSide(color: cardBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: royalBlue,
        unselectedItemColor: slateLight,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        unselectedLabelStyle: TextStyle(fontSize: 11),
        elevation: 8,
      ),
    );
  }
}
