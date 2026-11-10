import 'package:flutter/material.dart';

/// Explicit design tokens from `docs/design-tokens.json`. Material 3 still derives
/// additional scheme colours from the seed; these are the values the UI sets directly.
abstract final class AppColors {
  static const ink = Color(0xFF163D34);
  static const background = Color(0xFFF8F6EF);
  static const textSecondary = Color(0xFF52655C);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSubtle = Color(0xFFF2EFE4);
  static const cardSelected = Color(0xFFEAF0E2);
  static const chipSelected = Color(0xFFE1EBD7);
  static const noticeSurface = Color(0xFFEEE8D5);
  static const errorSurface = Color(0xFFFBE9E3);
  static const errorText = Color(0xFF7E211E);
  static const errorIcon = Color(0xFF9C2520);

  /// Interactive boundary for unselected cards and chips: 3.99:1 on white, 3.69:1 on cream.
  static const strongOutline = Color(0xFF718476);
  static const divider = Color(0xFFCCD3C7);
  static const progressInactive = Color(0xFFDEE4D8);
  static const plateCardSurface = Color(0xFFEAEDE2);
}

abstract final class AppRadius {
  static const mealCard = 20.0;
  static const changeCard = 18.0;
  static const plateCard = 22.0;
  static const notice = 16.0;
  static const button = 16.0;
}

abstract final class AppLayout {
  static const maxOuterWidth = 800.0;
  static const pagePadding = EdgeInsets.fromLTRB(20, 16, 20, 28);

  /// Inner-width (after padding) breakpoints, not device-width breakpoints.
  static const mealRowMinInnerWidth = 500.0;
  static const comparisonColumnsMinInnerWidth = 600.0;

  /// Compact meal card illustration size at narrow widths (design range 72–88).
  static const compactMealIllustration = 76.0;

  /// Above this text scale the compact meal card stacks its illustration above the text,
  /// so names and descriptions get the full card width instead of being squeezed.
  static const compactMealMaxTextScale = 1.3;
}

/// Unified typography tokens using the bundled font family so iOS, Android, and Web
/// never mix platform fallback fonts (`SF Pro` vs `Roboto`) or unbundled italics.
abstract final class AppTypography {
  static const fontFamily = 'Roboto';

  static const textTheme = TextTheme(
    displaySmall: TextStyle(
      fontFamily: fontFamily,
      fontSize: 28,
      height: 1.18,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      color: AppColors.ink,
    ),
    headlineSmall: TextStyle(
      fontFamily: fontFamily,
      fontSize: 22,
      height: 1.25,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.15,
      color: AppColors.ink,
    ),
    titleLarge: TextStyle(
      fontFamily: fontFamily,
      fontSize: 20,
      height: 1.28,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.0,
      color: AppColors.ink,
    ),
    titleMedium: TextStyle(
      fontFamily: fontFamily,
      fontSize: 18,
      height: 1.35,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.0,
      color: AppColors.ink,
    ),
    bodyLarge: TextStyle(
      fontFamily: fontFamily,
      fontSize: 18,
      height: 1.45,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.1,
      color: AppColors.ink,
    ),
    bodyMedium: TextStyle(
      fontFamily: fontFamily,
      fontSize: 16.5,
      height: 1.42,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.1,
      color: AppColors.textSecondary,
    ),
    labelLarge: TextStyle(
      fontFamily: fontFamily,
      fontSize: 18,
      height: 1.3,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1,
      color: AppColors.ink,
    ),
    // Progress metadata & helper status: sentence case, 16sp minimum (DESIGN.md P1).
    labelMedium: TextStyle(
      fontFamily: fontFamily,
      fontSize: 16,
      height: 1.38,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      color: AppColors.textSecondary,
    ),
  );
}

/// Effective text scale factor, used only to choose between layouts (never to cap it).
double textScaleOf(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(100) / 100;

ThemeData buildAppTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: AppTypography.fontFamily,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.ink,
    primary: AppColors.ink,
    surface: AppColors.background,
    error: AppColors.errorIcon,
  ),
  scaffoldBackgroundColor: AppColors.background,
  textTheme: AppTypography.textTheme,
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      textStyle: AppTypography.textTheme.labelLarge,
      minimumSize: const Size(64, 56),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      textStyle: AppTypography.textTheme.labelLarge,
      minimumSize: const Size(64, 56),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      side: const BorderSide(color: AppColors.ink, width: 1.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      textStyle: AppTypography.textTheme.labelMedium!.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w700,
      ),
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
  ),
  chipTheme: const ChipThemeData(
    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    labelStyle: TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: 17,
      height: 1.3,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      color: AppColors.ink,
    ),
    side: BorderSide(color: AppColors.strongOutline),
  ),
);
