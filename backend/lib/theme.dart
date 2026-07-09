import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MedAlertTheme {
  // Custom Color Constants matching Azure Horizon / Aman Health
  static const Color primaryLight = Color(0xFF005AB4);
  static const Color primaryContainerLight = Color(0xFF0A73E0);
  static const Color secondaryLight = Color(0xFF465F88);
  static const Color secondaryContainerLight = Color(0xFFB6D0FF);
  static const Color tertiaryLight = Color(0xFF964400);
  static const Color tertiaryContainerLight = Color(0xFFBD5700);
  static const Color backgroundLight = Color(0xFFF9F9FF);
  static const Color onBackgroundLight = Color(0xFF181C22);
  static const Color surfaceLight = Color(0xFFF9F9FF);
  static const Color onSurfaceLight = Color(0xFF181C22);
  static const Color onSurfaceVariantLight = Color(0xFF414753);
  static const Color outlineLight = Color(0xFF717785);
  static const Color outlineVariantLight = Color(0xFFC1C6D5);

  static const Color surfaceContainerLowestLight = Color(0xFFFFFFFF);
  static const Color surfaceContainerLowLight = Color(0xFFF1F3FC);
  static const Color surfaceContainerLight = Color(0xFFEBEDF7);
  static const Color surfaceContainerHighLight = Color(0xFFE6E8F1);
  static const Color surfaceContainerHighestLight = Color(0xFFE0E2EB);

  // Dark theme colors from design screens
  static const Color primaryDark = Color(0xFFAAC7FF);
  static const Color primaryContainerDark = Color(0xFF0A73E0);
  static const Color secondaryDark = Color(0xFFAEC7F7);
  static const Color secondaryContainerDark = Color(0xFF3F5881);
  static const Color tertiaryDark = Color(0xFFFFB68C);
  static const Color tertiaryContainerDark = Color(0xFF763400);
  static const Color backgroundDark = Color(0xFF111418);
  static const Color onBackgroundDark = Color(0xFFE2E2E9);
  static const Color surfaceDark = Color(0xFF191C20);
  static const Color onSurfaceDark = Color(0xFFE2E2E9);
  static const Color onSurfaceVariantDark = Color(0xFFC2C6D0);
  static const Color outlineDark = Color(0xFF8E9099);
  static const Color outlineVariantDark = Color(0xFF44474E);

  static const Color surfaceContainerLowestDark = Color(0xFF0C0F12);
  static const Color surfaceContainerLowDark = Color(0xFF15181C);
  static const Color surfaceContainerDark = Color(0xFF1D2024);
  static const Color surfaceContainerHighDark = Color(0xFF282A2F);
  static const Color surfaceContainerHighestDark = Color(0xFF303339);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: primaryLight,
        primaryContainer: primaryContainerLight,
        secondary: secondaryLight,
        secondaryContainer: secondaryContainerLight,
        tertiary: tertiaryLight,
        tertiaryContainer: tertiaryContainerLight,

        surface: surfaceLight,
        onSurface: onSurfaceLight,
        onSurfaceVariant: onSurfaceVariantLight,
        outline: outlineLight,
        outlineVariant: outlineVariantLight,
        error: Color(0xFFBA1A1A),
        errorContainer: Color(0xFFFFDAD6),
        onError: Colors.white,
        onErrorContainer: Color(0xFF93000A),
      ),
      textTheme: GoogleFonts.interTextTheme(
        ThemeData.light().textTheme,
      ),
      scaffoldBackgroundColor: backgroundLight,
      cardColor: surfaceContainerLowestLight,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainerLowLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
          borderSide: const BorderSide(color: Color(0x22717785), width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
          borderSide: const BorderSide(color: primaryLight, width: 2.0),
        ),
        prefixIconColor: outlineLight,
        suffixIconColor: outlineLight,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryLight,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16.0),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryLight,
          side: const BorderSide(color: outlineVariantLight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16.0),
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: primaryDark,
        primaryContainer: primaryContainerDark,
        secondary: secondaryDark,
        secondaryContainer: secondaryContainerDark,
        tertiary: tertiaryDark,
        tertiaryContainer: tertiaryContainerDark,

        surface: surfaceDark,
        onSurface: onSurfaceDark,
        onSurfaceVariant: onSurfaceVariantDark,
        outline: outlineDark,
        outlineVariant: outlineVariantDark,
        error: Color(0xFFBA1A1A),
        errorContainer: Color(0xFFFFDAD6),
        onError: Colors.white,
        onErrorContainer: Color(0xFF93000A),
      ),
      textTheme: GoogleFonts.interTextTheme(
        ThemeData.dark().textTheme,
      ),
      scaffoldBackgroundColor: backgroundDark,
      cardColor: surfaceContainerDark,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainerLowDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
          borderSide: const BorderSide(color: Color(0x228E9099), width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
          borderSide: const BorderSide(color: primaryDark, width: 2.0),
        ),
        prefixIconColor: outlineDark,
        suffixIconColor: outlineDark,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryDark,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16.0),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryDark,
          side: const BorderSide(color: outlineVariantDark),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16.0),
        ),
      ),
    );
  }
}
