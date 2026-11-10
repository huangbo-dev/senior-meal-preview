import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A consistent system type scale for browsing, choices and review.
/// Apple fonts are resolved from the OS and are never redistributed as app assets.
abstract final class AppColors {
  static const accent = Color(0xFF137A43);
  static const ink = Color(0xFF202420);
  static const background = Color(0xFFF8F9F6);
  static const textSecondary = Color(0xFF60665F);
  static const surface = Colors.white;
  static const surfaceSubtle = Color(0xFFEEF0EB);
  static const cardSelected = Color(0xFFEAF3EA);
  static const chipSelected = Colors.white;
  static const noticeSurface = Color(0xFFEEF0EB);
  static const errorSurface = Color(0xFFFFF0ED);
  static const errorText = Color(0xFF842B20);
  static const errorIcon = Color(0xFF9C3325);
  static const strongOutline = Color(0xFF778075);
  static const divider = Color(0xFFE2E6DE);
  static const progressInactive = Color(0xFFE2E6DE);
  static const plateCardSurface = Color(0xFFF3F4EF);
}

abstract final class AppRadius {
  static const mealCard = 14.0;
  static const changeCard = 14.0;
  static const plateCard = 18.0;
  static const notice = 12.0;
  static const button = 14.0;
}

abstract final class AppLayout {
  static const maxOuterWidth = 620.0;
  static const pagePadding = EdgeInsets.fromLTRB(20, 12, 20, 28);
  static const compactMealMaxTextScale = 1.3;
}

abstract final class AppTypography {
  static bool get isApple =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
  static String get fontFamily => isApple ? '.SF Pro Text' : 'Roboto';
  static String get editorialFamily => fontFamily;

  static TextStyle style(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.ink,
    double height = 1.3,
  }) => TextStyle(
    fontFamily: fontFamily,
    fontSize: size,
    height: height,
    fontWeight: weight,
    letterSpacing: -.2,
    color: color,
  );

  static TextStyle get editorial => TextStyle(
    fontFamily: editorialFamily,
    fontSize: 30,
    height: 1.15,
    fontWeight: FontWeight.w600,
    letterSpacing: -.7,
    color: AppColors.ink,
  );

  static TextTheme get textTheme => TextTheme(
    displaySmall: style(32, weight: FontWeight.w700, height: 1.15),
    headlineSmall: style(21, weight: FontWeight.w600),
    titleLarge: style(22, weight: FontWeight.w500),
    titleMedium: style(18, weight: FontWeight.w500),
    bodyLarge: style(18, height: 1.4),
    bodyMedium: style(16, color: AppColors.textSecondary, height: 1.4),
    labelLarge: style(18, weight: FontWeight.w500),
    labelMedium: style(16, color: AppColors.textSecondary),
  );
}

double textScaleOf(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(100) / 100;

ThemeData buildAppTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: AppTypography.fontFamily,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    primary: AppColors.accent,
    surface: AppColors.surface,
    error: AppColors.errorIcon,
  ),
  scaffoldBackgroundColor: AppColors.background,
  textTheme: AppTypography.textTheme,
  splashFactory: NoSplash.splashFactory,
  dividerColor: AppColors.divider,
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      textStyle: AppTypography.style(17),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
  ),
);
