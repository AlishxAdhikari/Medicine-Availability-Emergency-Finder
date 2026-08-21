import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// MedAlert's design system.
///
/// Palette: a deep clinical navy as the primary (trust, medical), a teal
/// accent for secondary actions/highlights, a warm coral reserved for
/// alerts/emergency states, and warm neutral grays (not blue-tinted) for
/// surfaces so the UI reads calm and professional rather than flat/cold.
class MedAlertTheme {
  // ---- Light palette ----
  static const Color primaryLight = Color(0xFF0B4F8A); // deep clinical navy
  static const Color primaryContainerLight = Color(0xFFD8E7F7);
  static const Color onPrimaryContainerLight = Color(0xFF06304F);

  static const Color secondaryLight = Color(0xFF0E7C86); // teal accent
  static const Color secondaryContainerLight = Color(0xFFD3EEEF);
  static const Color onSecondaryContainerLight = Color(0xFF06393D);

  static const Color tertiaryLight = Color(0xFFC2410C); // emergency/alert accent
  static const Color tertiaryContainerLight = Color(0xFFFBE4D6);
  static const Color onTertiaryContainerLight = Color(0xFF6B2205);

  static const Color backgroundLight = Color(0xFFF7F8FA);
  static const Color onBackgroundLight = Color(0xFF1B1E23);
  static const Color surfaceLight = Color(0xFFF7F8FA);
  static const Color onSurfaceLight = Color(0xFF1B1E23);
  static const Color onSurfaceVariantLight = Color(0xFF52565D);
  static const Color outlineLight = Color(0xFF7B7F87);
  static const Color outlineVariantLight = Color(0xFFDADCE1);

  static const Color surfaceContainerLowestLight = Color(0xFFFFFFFF);
  static const Color surfaceContainerLowLight = Color(0xFFF1F2F5);
  static const Color surfaceContainerLight = Color(0xFFEBECF0);
  static const Color surfaceContainerHighLight = Color(0xFFE4E6EB);
  static const Color surfaceContainerHighestLight = Color(0xFFDDE0E5);

  static const Color errorLight = Color(0xFFB3261E);
  static const Color errorContainerLight = Color(0xFFF9DEDC);
  static const Color onErrorContainerLight = Color(0xFF410E0B);

  // ---- Dark palette ----
  static const Color primaryDark = Color(0xFF8FC1F2);
  static const Color primaryContainerDark = Color(0xFF0B4F8A);
  static const Color onPrimaryContainerDark = Color(0xFFD8E7F7);

  static const Color secondaryDark = Color(0xFF7ED4DA);
  static const Color secondaryContainerDark = Color(0xFF10555C);
  static const Color onSecondaryContainerDark = Color(0xFFD3EEEF);

  static const Color tertiaryDark = Color(0xFFFFB088);
  static const Color tertiaryContainerDark = Color(0xFF7A2C0B);
  static const Color onTertiaryContainerDark = Color(0xFFFBE4D6);

  static const Color backgroundDark = Color(0xFF14171B);
  static const Color onBackgroundDark = Color(0xFFE4E5E8);
  static const Color surfaceDark = Color(0xFF14171B);
  static const Color onSurfaceDark = Color(0xFFE4E5E8);
  static const Color onSurfaceVariantDark = Color(0xFFC4C6CB);
  static const Color outlineDark = Color(0xFF8D9096);
  static const Color outlineVariantDark = Color(0xFF3A3D42);

  static const Color surfaceContainerLowestDark = Color(0xFF0C0E11);
  static const Color surfaceContainerLowDark = Color(0xFF1B1E22);
  static const Color surfaceContainerDark = Color(0xFF202327);
  static const Color surfaceContainerHighDark = Color(0xFF2A2D32);
  static const Color surfaceContainerHighestDark = Color(0xFF35383D);

  static const Color errorDark = Color(0xFFF2B8B5);
  static const Color errorContainerDark = Color(0xFF8C1D18);
  static const Color onErrorContainerDark = Color(0xFFF9DEDC);

  static const double _radius = 10.0;

  static ThemeData get lightTheme {
    const scheme = ColorScheme.light(
      primary: primaryLight,
      onPrimary: Colors.white,
      primaryContainer: primaryContainerLight,
      onPrimaryContainer: onPrimaryContainerLight,
      secondary: secondaryLight,
      onSecondary: Colors.white,
      secondaryContainer: secondaryContainerLight,
      onSecondaryContainer: onSecondaryContainerLight,
      tertiary: tertiaryLight,
      onTertiary: Colors.white,
      tertiaryContainer: tertiaryContainerLight,
      onTertiaryContainer: onTertiaryContainerLight,
      surface: surfaceLight,
      onSurface: onSurfaceLight,
      onSurfaceVariant: onSurfaceVariantLight,
      outline: outlineLight,
      outlineVariant: outlineVariantLight,
      error: errorLight,
      errorContainer: errorContainerLight,
      onError: Colors.white,
      onErrorContainer: onErrorContainerLight,
    );

    return _buildTheme(
      brightness: Brightness.light,
      scheme: scheme,
      background: backgroundLight,
      cardColor: surfaceContainerLowestLight,
      fieldFill: surfaceContainerLowLight,
      enabledBorder: const Color(0x1F1B1E23),
      outline: outlineLight,
      dividerColor: outlineVariantLight,
      elevatedFg: Colors.white,
    );
  }

  static ThemeData get darkTheme {
    const scheme = ColorScheme.dark(
      primary: primaryDark,
      onPrimary: Color(0xFF00304F),
      primaryContainer: primaryContainerDark,
      onPrimaryContainer: onPrimaryContainerDark,
      secondary: secondaryDark,
      onSecondary: Color(0xFF00363B),
      secondaryContainer: secondaryContainerDark,
      onSecondaryContainer: onSecondaryContainerDark,
      tertiary: tertiaryDark,
      onTertiary: Color(0xFF4A1A00),
      tertiaryContainer: tertiaryContainerDark,
      onTertiaryContainer: onTertiaryContainerDark,
      surface: surfaceDark,
      onSurface: onSurfaceDark,
      onSurfaceVariant: onSurfaceVariantDark,
      outline: outlineDark,
      outlineVariant: outlineVariantDark,
      error: errorDark,
      errorContainer: errorContainerDark,
      onError: Color(0xFF601410),
      onErrorContainer: onErrorContainerDark,
    );

    return _buildTheme(
      brightness: Brightness.dark,
      scheme: scheme,
      background: backgroundDark,
      cardColor: surfaceContainerDark,
      fieldFill: surfaceContainerLowDark,
      enabledBorder: const Color(0x33FFFFFF),
      outline: outlineDark,
      dividerColor: outlineVariantDark,
      elevatedFg: const Color(0xFF00304F),
    );
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required ColorScheme scheme,
    required Color background,
    required Color cardColor,
    required Color fieldFill,
    required Color enabledBorder,
    required Color outline,
    required Color dividerColor,
    required Color elevatedFg,
  }) {
    final base = brightness == Brightness.light ? ThemeData.light() : ThemeData.dark();
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: background,
      cardColor: cardColor,
      dividerColor: dividerColor,
      splashColor: scheme.primary.withValues(alpha: 0.08),
      highlightColor: Colors.transparent,

      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),

      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius + 2),
          side: BorderSide(color: outline.withValues(alpha: 0.15)),
        ),
      ),

      dividerTheme: DividerThemeData(color: dividerColor, thickness: 1, space: 32),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide(color: enabledBorder, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide(color: scheme.error, width: 1.0),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: elevatedFg,
          disabledBackgroundColor: scheme.primary.withValues(alpha: 0.4),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.1),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: outline.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        selectedColor: scheme.primaryContainer,
        labelStyle: TextStyle(color: scheme.onSurface),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: elevatedFg,
        elevation: 1,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),

      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
      ),
    );
  }
}