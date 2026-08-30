import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central design tokens for the app. Every screen pulls color, spacing,
/// and type decisions from here so the UI stays consistent.
class AppColors {
  AppColors._();

  // Surfaces
  static const Color background = Color(0xFFF8F9FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color sidebar = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE9ECEF);
  static const Color divider = Color(0xFFF1F3F5);

  // Text
  static const Color textPrimary = Color(0xFF212529);
  static const Color textSecondary = Color(0xFF6C757D);
  static const Color textMuted = Color(0xFFADB5BD);

  // Accents
  static const Color primary = Color.fromARGB(255, 255, 73, 73);
  static const Color primarySoft = Color(0xFFEFF4FF);
  static const Color success = Color(0xFF16A34A);
  static const Color successSoft = Color(0xFFEBF9EF);
  static const Color warning = Color(0xFFD97706);
  static const Color warningSoft = Color(0xFFFEF6E7);
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerSoft = Color(0xFFFDECEC);
  static const Color neutralSoft = Color(0xFFF1F3F5);
}

class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

class AppRadius {
  AppRadius._();
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double pill = 999;
}

class AppTextStyles {
  AppTextStyles._();

  static TextStyle get _base => GoogleFonts.inter(color: AppColors.textPrimary);

  static TextStyle get h1 => _base.copyWith(fontSize: 28, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.5);
  static TextStyle get h2 => _base.copyWith(fontSize: 22, fontWeight: FontWeight.w700, height: 1.25, letterSpacing: -0.3);
  static TextStyle get h3 => _base.copyWith(fontSize: 18, fontWeight: FontWeight.w600, height: 1.3);
  static TextStyle get bodyLarge => _base.copyWith(fontSize: 15, fontWeight: FontWeight.w500, height: 1.4);
  static TextStyle get body => _base.copyWith(fontSize: 14, fontWeight: FontWeight.w400, height: 1.4);
  static TextStyle get bodyMedium => _base.copyWith(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4);
  static TextStyle get caption => _base.copyWith(fontSize: 12.5, fontWeight: FontWeight.w500, color: AppColors.textSecondary, height: 1.3);
  static TextStyle get label => _base.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary, letterSpacing: 0.2);
  static TextStyle get statValue => _base.copyWith(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5, height: 1.1);
  static TextStyle get mono => GoogleFonts.robotoMono(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary, height: 1.4);
}

ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    surface: AppColors.surface,
    error: AppColors.danger,
    brightness: Brightness.light,
  ).copyWith(
    primaryContainer: AppColors.primarySoft,
    surface: AppColors.surface,
    surfaceContainerHighest: AppColors.background,
    outline: AppColors.border,
    outlineVariant: AppColors.divider,
    surfaceTint: Colors.transparent,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.background,
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    textTheme: GoogleFonts.interTextTheme(base.textTheme),
    dividerColor: AppColors.divider,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: AppColors.primary.withValues(alpha: 0.04),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(AppColors.border),
      thickness: WidgetStateProperty.all(6),
      radius: const Radius.circular(4),
    ),
  );
}
