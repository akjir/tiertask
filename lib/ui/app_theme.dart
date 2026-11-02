// TierTask
// Copyright (C) 2026  Stefan Stark
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option)
// any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with
// this program.  If not, see <https://www.gnu.org/licenses/>.

/// Unified application theme definition and Material 3 [ThemeData] builder.
library;

import 'package:flutter/material.dart';

import '../models/webdav_config.dart';

/// Immutable semantic palette and Material 3 theme definition for TierTask.
///
/// Every visual surface, text style, icon accent, indicator dot, and vector
/// logo gradient across the application derives from the active [AppTheme].
/// Registered as a [ThemeExtension] inside [toThemeData] so widgets can read
/// both standard [Theme.of] properties and [AppTheme.of] semantic tokens.
@immutable
class AppTheme extends ThemeExtension<AppTheme> {
  /// Creates an [AppTheme] with explicit semantic color tokens.
  const AppTheme({
    required this.brightness,
    required this.canvasColor,
    required this.cardColor,
    required this.dividerColor,
    required this.elevatedSurfaceColor,
    required this.errorColor,
    required this.errorContainerColor,
    required this.indicatorActiveIconColor,
    required this.indicatorInactiveDotColor,
    required this.indicatorIntermediateColor,
    required this.logoBackgroundEnd,
    required this.logoBackgroundStart,
    required this.logoTier1End,
    required this.logoTier1Start,
    required this.logoTier2End,
    required this.logoTier2Start,
    required this.logoTier3End,
    required this.logoTier3Start,
    required this.mutedTextColor,
    required this.onErrorContainerColor,
    required this.onPrimaryColor,
    required this.onPrimaryContainerColor,
    required this.onSecondaryColor,
    required this.onSecondaryContainerColor,
    required this.primaryAccent,
    required this.primaryContainerColor,
    required this.primaryTextColor,
    required this.secondaryAccent,
    required this.secondaryContainerColor,
    required this.tertiaryAccent,
    required this.warningAccent,
  });

  /// Default dark theme (aliases [slateDark]).
  static const AppTheme dark = slateDark;

  /// Default light theme (aliases [slateLight]).
  static const AppTheme light = slateLight;

  /// Signature TierTask navy and indigo dark theme.
  static const AppTheme navyDark = AppTheme(
    brightness: Brightness.dark,
    canvasColor: Color(0xFF344FA1),
    cardColor: Color(0xFF071A52),
    dividerColor: Color(0x3DFFFFFF),
    elevatedSurfaceColor: Color(0xFF10256B),
    errorColor: Color(0xFFFF5252),
    errorContainerColor: Color(0xFF3B1229),
    indicatorActiveIconColor: Color(0xFFFFFFFF),
    indicatorInactiveDotColor: Color(0x8A9BA8E5),
    indicatorIntermediateColor: Color(0xC5CED4F2),
    logoBackgroundEnd: Color(0xFF071A52),
    logoBackgroundStart: Color(0xFF0D256C),
    logoTier1End: Color(0xFF00BFA5),
    logoTier1Start: Color(0xFF00E5FF),
    logoTier2End: Color(0xFF009688),
    logoTier2Start: Color(0xFF26A69A),
    logoTier3End: Color(0xFF004D40),
    logoTier3Start: Color(0xFF00796B),
    mutedTextColor: Color(0xFF9BA8E5),
    onErrorContainerColor: Color(0xFFFFB4AB),
    onPrimaryColor: Color(0xFFFFFFFF),
    onPrimaryContainerColor: Color(0xFFFAD4FF),
    onSecondaryColor: Color(0xFFFFFFFF),
    onSecondaryContainerColor: Color(0xFFD8E4FF),
    primaryAccent: Color(0xFFEB06FF),
    primaryContainerColor: Color(0xFF4A156B),
    primaryTextColor: Color(0xFFFFFFFF),
    secondaryAccent: Color(0xFF2196F3),
    secondaryContainerColor: Color(0xFF15387A),
    tertiaryAccent: Color(0xFF00E5FF),
    warningAccent: Color(0xFFFFB300),
  );

  /// Harmonized light theme preserving TierTask navy brand accents on light surfaces.
  static const AppTheme navyLight = AppTheme(
    brightness: Brightness.light,
    canvasColor: Color(0xFFEEF2FF),
    cardColor: Color(0xFFFFFFFF),
    dividerColor: Color(0x29071A52),
    elevatedSurfaceColor: Color(0xFFE0E7FF),
    errorColor: Color(0xFFD32F2F),
    errorContainerColor: Color(0xFFFDECEA),
    indicatorActiveIconColor: Color(0xFF071A52),
    indicatorInactiveDotColor: Color(0x8A4A5B8C),
    indicatorIntermediateColor: Color(0xC5283A6F),
    logoBackgroundEnd: Color(0xFF071A52),
    logoBackgroundStart: Color(0xFF0D256C),
    logoTier1End: Color(0xFF00BFA5),
    logoTier1Start: Color(0xFF00E5FF),
    logoTier2End: Color(0xFF009688),
    logoTier2Start: Color(0xFF26A69A),
    logoTier3End: Color(0xFF004D40),
    logoTier3Start: Color(0xFF00796B),
    mutedTextColor: Color(0xFF4A5B8C),
    onErrorContainerColor: Color(0xFF7F1D1D),
    onPrimaryColor: Color(0xFFFFFFFF),
    onPrimaryContainerColor: Color(0xFF380042),
    onSecondaryColor: Color(0xFFFFFFFF),
    onSecondaryContainerColor: Color(0xFF071A52),
    primaryAccent: Color(0xFFEB06FF),
    primaryContainerColor: Color(0xFFF8D8FF),
    primaryTextColor: Color(0xFF071A52),
    secondaryAccent: Color(0xFF2196F3),
    secondaryContainerColor: Color(0xFFD8E2FF),
    tertiaryAccent: Color(0xFF0097A7),
    warningAccent: Color(0xFFF59E0B),
  );

  /// Chromium-inspired Material 3 slate blue-grey dark theme.
  static const AppTheme slateDark = AppTheme(
    brightness: Brightness.dark,
    canvasColor: Color(0xFF47545E),
    cardColor: Color(0xFF243037),
    dividerColor: Color(0x3DF3F5F6),
    elevatedSurfaceColor: Color(0xFF39434B),
    errorColor: Color(0xFFFFB4AB),
    errorContainerColor: Color(0xFF690005),
    indicatorActiveIconColor: Color(0xFFF3F5F6),
    indicatorInactiveDotColor: Color(0x8AB8C4CC),
    indicatorIntermediateColor: Color(0xC5DCE3E8),
    logoBackgroundEnd: Color(0xFF243037),
    logoBackgroundStart: Color(0xFF2D3B44),
    logoTier1End: Color(0xFF7EBAB1),
    logoTier1Start: Color(0xFF8AB4F8),
    logoTier2End: Color(0xFF4A7880),
    logoTier2Start: Color(0xFF628687),
    logoTier3End: Color(0xFF004C6B),
    logoTier3Start: Color(0xFF1D617E),
    mutedTextColor: Color(0xFFB8C4CC),
    onErrorContainerColor: Color(0xFFFFDAD6),
    onPrimaryColor: Color(0xFF003258),
    onPrimaryContainerColor: Color(0xFFCCE1F0),
    onSecondaryColor: Color(0xFF003731),
    onSecondaryContainerColor: Color(0xFFD0E8F2),
    primaryAccent: Color(0xFF8AB4F8),
    primaryContainerColor: Color(0xFF004C6B),
    primaryTextColor: Color(0xFFF3F5F6),
    secondaryAccent: Color(0xFF7EBAB1),
    secondaryContainerColor: Color(0xFF1F4E5B),
    tertiaryAccent: Color(0xFFA8C7FA),
    warningAccent: Color(0xFFFFCA62),
  );

  /// Chromium-inspired Material 3 slate blue-grey light theme.
  static const AppTheme slateLight = AppTheme(
    brightness: Brightness.light,
    canvasColor: Color(0xFFEEF3F7),
    cardColor: Color(0xFFFFFFFF),
    dividerColor: Color(0x26243037),
    elevatedSurfaceColor: Color(0xFFDCE4EC),
    errorColor: Color(0xFFBA1A1A),
    errorContainerColor: Color(0xFFFFDAD6),
    indicatorActiveIconColor: Color(0xFF1B242B),
    indicatorInactiveDotColor: Color(0x8A52606B),
    indicatorIntermediateColor: Color(0xC52F3D47),
    logoBackgroundEnd: Color(0xFF243037),
    logoBackgroundStart: Color(0xFF2D3B44),
    logoTier1End: Color(0xFF7EBAB1),
    logoTier1Start: Color(0xFF8AB4F8),
    logoTier2End: Color(0xFF4A7880),
    logoTier2Start: Color(0xFF628687),
    logoTier3End: Color(0xFF004C6B),
    logoTier3Start: Color(0xFF1D617E),
    mutedTextColor: Color(0xFF52606B),
    onErrorContainerColor: Color(0xFF410002),
    onPrimaryColor: Color(0xFFFFFFFF),
    onPrimaryContainerColor: Color(0xFF001E2D),
    onSecondaryColor: Color(0xFFFFFFFF),
    onSecondaryContainerColor: Color(0xFF0E2430),
    primaryAccent: Color(0xFF00648B),
    primaryContainerColor: Color(0xFFC7E7FF),
    primaryTextColor: Color(0xFF1B242B),
    secondaryAccent: Color(0xFF2B6A63),
    secondaryContainerColor: Color(0xFFD2E5F3),
    tertiaryAccent: Color(0xFF285EA7),
    warningAccent: Color(0xFFD97706),
  );

  /// Overall brightness of this theme (`Brightness.dark` or `Brightness.light`).
  final Brightness brightness;

  /// Primary screen scaffold background color.
  final Color canvasColor;

  /// Card, pill, app bar, drawer, dialog, and input surface color.
  final Color cardColor;

  /// Subtle border and divider stroke color.
  final Color dividerColor;

  /// Elevated container and secondary chip surface color.
  final Color elevatedSurfaceColor;

  /// Destructive action and validation error color.
  final Color errorColor;

  /// Background surface color for error banners.
  final Color errorContainerColor;

  /// Active icon color in the bottom tier page indicator.
  final Color indicatorActiveIconColor;

  /// Inactive dot color in the bottom tier page indicator.
  final Color indicatorInactiveDotColor;

  /// Intermediate wave neighbor and hover color in the tier page indicator.
  final Color indicatorIntermediateColor;

  /// Ending gradient color for the application logo background.
  final Color logoBackgroundEnd;

  /// Starting gradient color for the application logo background.
  final Color logoBackgroundStart;

  /// Ending gradient color for the top logo tier bar.
  final Color logoTier1End;

  /// Starting gradient color for the top logo tier bar.
  final Color logoTier1Start;

  /// Ending gradient color for the middle logo tier bar.
  final Color logoTier2End;

  /// Starting gradient color for the middle logo tier bar.
  final Color logoTier2Start;

  /// Ending gradient color for the bottom logo tier bar.
  final Color logoTier3End;

  /// Starting gradient color for the bottom logo tier bar.
  final Color logoTier3Start;

  /// Secondary label, hint, subtitle, and unselected icon color.
  final Color mutedTextColor;

  /// Foreground text and icon color inside error banners.
  final Color onErrorContainerColor;

  /// Foreground text and icon color rendered atop [primaryAccent].
  final Color onPrimaryColor;

  /// Foreground text and icon color rendered atop [primaryContainerColor].
  final Color onPrimaryContainerColor;

  /// Foreground text and icon color rendered atop [secondaryAccent].
  final Color onSecondaryColor;

  /// Foreground text and icon color rendered atop [secondaryContainerColor].
  final Color onSecondaryContainerColor;

  /// Primary brand accent color (priority ring, filled CTA buttons, focus border).
  final Color primaryAccent;

  /// Tonal primary container fill color (primary FAB, tonal banners).
  final Color primaryContainerColor;

  /// Primary foreground text and active icon color.
  final Color primaryTextColor;

  /// Secondary brand accent color (standard task ring, Someday accent).
  final Color secondaryAccent;

  /// Tonal secondary container fill color (segmented buttons, badges, drawer selection, tonal icon buttons).
  final Color secondaryContainerColor;

  /// Tertiary brand accent color (location/time condition highlights, banners).
  final Color tertiaryAccent;

  /// Warning and condition badge accent color.
  final Color warningAccent;

  /// Resolves the active [AppTheme] extension from [context].
  static AppTheme of(BuildContext context) {
    return Theme.of(context).extension<AppTheme>() ?? AppTheme.dark;
  }

  @override
  AppTheme copyWith({
    Brightness? brightness,
    Color? canvasColor,
    Color? cardColor,
    Color? dividerColor,
    Color? elevatedSurfaceColor,
    Color? errorColor,
    Color? errorContainerColor,
    Color? indicatorActiveIconColor,
    Color? indicatorInactiveDotColor,
    Color? indicatorIntermediateColor,
    Color? logoBackgroundEnd,
    Color? logoBackgroundStart,
    Color? logoTier1End,
    Color? logoTier1Start,
    Color? logoTier2End,
    Color? logoTier2Start,
    Color? logoTier3End,
    Color? logoTier3Start,
    Color? mutedTextColor,
    Color? onErrorContainerColor,
    Color? onPrimaryColor,
    Color? onPrimaryContainerColor,
    Color? onSecondaryColor,
    Color? onSecondaryContainerColor,
    Color? primaryAccent,
    Color? primaryContainerColor,
    Color? primaryTextColor,
    Color? secondaryAccent,
    Color? secondaryContainerColor,
    Color? tertiaryAccent,
    Color? warningAccent,
  }) {
    return AppTheme(
      brightness: brightness ?? this.brightness,
      canvasColor: canvasColor ?? this.canvasColor,
      cardColor: cardColor ?? this.cardColor,
      dividerColor: dividerColor ?? this.dividerColor,
      elevatedSurfaceColor: elevatedSurfaceColor ?? this.elevatedSurfaceColor,
      errorColor: errorColor ?? this.errorColor,
      errorContainerColor: errorContainerColor ?? this.errorContainerColor,
      indicatorActiveIconColor:
          indicatorActiveIconColor ?? this.indicatorActiveIconColor,
      indicatorInactiveDotColor:
          indicatorInactiveDotColor ?? this.indicatorInactiveDotColor,
      indicatorIntermediateColor:
          indicatorIntermediateColor ?? this.indicatorIntermediateColor,
      logoBackgroundEnd: logoBackgroundEnd ?? this.logoBackgroundEnd,
      logoBackgroundStart: logoBackgroundStart ?? this.logoBackgroundStart,
      logoTier1End: logoTier1End ?? this.logoTier1End,
      logoTier1Start: logoTier1Start ?? this.logoTier1Start,
      logoTier2End: logoTier2End ?? this.logoTier2End,
      logoTier2Start: logoTier2Start ?? this.logoTier2Start,
      logoTier3End: logoTier3End ?? this.logoTier3End,
      logoTier3Start: logoTier3Start ?? this.logoTier3Start,
      mutedTextColor: mutedTextColor ?? this.mutedTextColor,
      onErrorContainerColor:
          onErrorContainerColor ?? this.onErrorContainerColor,
      onPrimaryColor: onPrimaryColor ?? this.onPrimaryColor,
      onPrimaryContainerColor:
          onPrimaryContainerColor ?? this.onPrimaryContainerColor,
      onSecondaryColor: onSecondaryColor ?? this.onSecondaryColor,
      onSecondaryContainerColor:
          onSecondaryContainerColor ?? this.onSecondaryContainerColor,
      primaryAccent: primaryAccent ?? this.primaryAccent,
      primaryContainerColor:
          primaryContainerColor ?? this.primaryContainerColor,
      primaryTextColor: primaryTextColor ?? this.primaryTextColor,
      secondaryAccent: secondaryAccent ?? this.secondaryAccent,
      secondaryContainerColor:
          secondaryContainerColor ?? this.secondaryContainerColor,
      tertiaryAccent: tertiaryAccent ?? this.tertiaryAccent,
      warningAccent: warningAccent ?? this.warningAccent,
    );
  }

  @override
  AppTheme lerp(ThemeExtension<AppTheme>? other, double t) {
    if (other is! AppTheme) {
      return this;
    }
    return AppTheme(
      brightness: t < 0.5 ? brightness : other.brightness,
      canvasColor: Color.lerp(canvasColor, other.canvasColor, t) ?? canvasColor,
      cardColor: Color.lerp(cardColor, other.cardColor, t) ?? cardColor,
      dividerColor:
          Color.lerp(dividerColor, other.dividerColor, t) ?? dividerColor,
      elevatedSurfaceColor:
          Color.lerp(elevatedSurfaceColor, other.elevatedSurfaceColor, t) ??
          elevatedSurfaceColor,
      errorColor: Color.lerp(errorColor, other.errorColor, t) ?? errorColor,
      errorContainerColor:
          Color.lerp(errorContainerColor, other.errorContainerColor, t) ??
          errorContainerColor,
      indicatorActiveIconColor:
          Color.lerp(
            indicatorActiveIconColor,
            other.indicatorActiveIconColor,
            t,
          ) ??
          indicatorActiveIconColor,
      indicatorInactiveDotColor:
          Color.lerp(
            indicatorInactiveDotColor,
            other.indicatorInactiveDotColor,
            t,
          ) ??
          indicatorInactiveDotColor,
      indicatorIntermediateColor:
          Color.lerp(
            indicatorIntermediateColor,
            other.indicatorIntermediateColor,
            t,
          ) ??
          indicatorIntermediateColor,
      logoBackgroundEnd:
          Color.lerp(logoBackgroundEnd, other.logoBackgroundEnd, t) ??
          logoBackgroundEnd,
      logoBackgroundStart:
          Color.lerp(logoBackgroundStart, other.logoBackgroundStart, t) ??
          logoBackgroundStart,
      logoTier1End:
          Color.lerp(logoTier1End, other.logoTier1End, t) ?? logoTier1End,
      logoTier1Start:
          Color.lerp(logoTier1Start, other.logoTier1Start, t) ?? logoTier1Start,
      logoTier2End:
          Color.lerp(logoTier2End, other.logoTier2End, t) ?? logoTier2End,
      logoTier2Start:
          Color.lerp(logoTier2Start, other.logoTier2Start, t) ?? logoTier2Start,
      logoTier3End:
          Color.lerp(logoTier3End, other.logoTier3End, t) ?? logoTier3End,
      logoTier3Start:
          Color.lerp(logoTier3Start, other.logoTier3Start, t) ?? logoTier3Start,
      mutedTextColor:
          Color.lerp(mutedTextColor, other.mutedTextColor, t) ?? mutedTextColor,
      onErrorContainerColor:
          Color.lerp(onErrorContainerColor, other.onErrorContainerColor, t) ??
          onErrorContainerColor,
      onPrimaryColor:
          Color.lerp(onPrimaryColor, other.onPrimaryColor, t) ?? onPrimaryColor,
      onPrimaryContainerColor:
          Color.lerp(
            onPrimaryContainerColor,
            other.onPrimaryContainerColor,
            t,
          ) ??
          onPrimaryContainerColor,
      onSecondaryColor:
          Color.lerp(onSecondaryColor, other.onSecondaryColor, t) ??
          onSecondaryColor,
      onSecondaryContainerColor:
          Color.lerp(
            onSecondaryContainerColor,
            other.onSecondaryContainerColor,
            t,
          ) ??
          onSecondaryContainerColor,
      primaryAccent:
          Color.lerp(primaryAccent, other.primaryAccent, t) ?? primaryAccent,
      primaryContainerColor:
          Color.lerp(primaryContainerColor, other.primaryContainerColor, t) ??
          primaryContainerColor,
      primaryTextColor:
          Color.lerp(primaryTextColor, other.primaryTextColor, t) ??
          primaryTextColor,
      secondaryAccent:
          Color.lerp(secondaryAccent, other.secondaryAccent, t) ??
          secondaryAccent,
      secondaryContainerColor:
          Color.lerp(
            secondaryContainerColor,
            other.secondaryContainerColor,
            t,
          ) ??
          secondaryContainerColor,
      tertiaryAccent:
          Color.lerp(tertiaryAccent, other.tertiaryAccent, t) ?? tertiaryAccent,
      warningAccent:
          Color.lerp(warningAccent, other.warningAccent, t) ?? warningAccent,
    );
  }

  /// Compiles this [AppTheme] into a complete Material 3 [ThemeData].
  ThemeData toThemeData() {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primaryAccent,
      onPrimary: onPrimaryColor,
      primaryContainer: primaryContainerColor,
      onPrimaryContainer: onPrimaryContainerColor,
      secondary: secondaryAccent,
      onSecondary: onSecondaryColor,
      secondaryContainer: secondaryContainerColor,
      onSecondaryContainer: onSecondaryContainerColor,
      tertiary: tertiaryAccent,
      onTertiary: cardColor,
      error: errorColor,
      onError: onPrimaryColor,
      errorContainer: errorContainerColor,
      onErrorContainer: onErrorContainerColor,
      surface: canvasColor,
      onSurface: primaryTextColor,
      onSurfaceVariant: mutedTextColor,
      surfaceContainer: cardColor,
      surfaceContainerHighest: elevatedSurfaceColor,
      outline: mutedTextColor,
      outlineVariant: dividerColor,
    );

    final textTheme = TextTheme(
      headlineMedium: TextStyle(
        color: primaryTextColor,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      titleLarge: TextStyle(
        color: primaryTextColor,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: primaryTextColor,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: TextStyle(
        color: mutedTextColor,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.6,
      ),
      bodyLarge: TextStyle(
        color: primaryTextColor,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      bodyMedium: TextStyle(color: primaryTextColor, fontSize: 14),
      bodySmall: TextStyle(color: mutedTextColor, fontSize: 12),
      labelLarge: TextStyle(
        color: mutedTextColor,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: TextStyle(
        color: mutedTextColor,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
      labelSmall: TextStyle(
        color: mutedTextColor,
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: canvasColor,
      canvasColor: canvasColor,
      cardColor: cardColor,
      dividerColor: dividerColor,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: cardColor,
        foregroundColor: primaryTextColor,
        elevation: 0,
        iconTheme: IconThemeData(color: primaryTextColor),
        titleTextStyle: textTheme.titleLarge,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: secondaryContainerColor,
        textColor: onSecondaryContainerColor,
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(color: dividerColor, thickness: 1),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryContainerColor,
        foregroundColor: onPrimaryContainerColor,
        shape: const CircleBorder(),
      ),
      iconTheme: IconThemeData(color: primaryTextColor),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
        labelStyle: TextStyle(color: mutedTextColor),
        hintStyle: TextStyle(color: mutedTextColor),
        prefixIconColor: mutedTextColor,
        suffixIconColor: mutedTextColor,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryAccent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: errorColor),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: errorColor, width: 2),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: dividerColor),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cardColor,
        selectedColor: secondaryContainerColor,
        checkmarkColor: onSecondaryContainerColor,
        deleteIconColor: mutedTextColor,
        labelStyle: TextStyle(color: primaryTextColor, fontSize: 13),
        side: BorderSide(color: dividerColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryAccent,
          foregroundColor: onPrimaryColor,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryTextColor,
          side: BorderSide(color: mutedTextColor),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: mutedTextColor),
      ),
      timePickerTheme: TimePickerThemeData(backgroundColor: cardColor),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return secondaryContainerColor;
            }
            return cardColor;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return onSecondaryContainerColor;
            }
            return primaryTextColor;
          }),
          side: WidgetStateProperty.all(BorderSide(color: dividerColor)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: mutedTextColor,
        textColor: primaryTextColor,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primaryAccent),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: cardColor,
        contentTextStyle: TextStyle(color: primaryTextColor),
      ),
      extensions: <ThemeExtension<AppTheme>>[this],
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is AppTheme &&
        other.brightness == brightness &&
        other.canvasColor == canvasColor &&
        other.cardColor == cardColor &&
        other.dividerColor == dividerColor &&
        other.elevatedSurfaceColor == elevatedSurfaceColor &&
        other.errorColor == errorColor &&
        other.errorContainerColor == errorContainerColor &&
        other.indicatorActiveIconColor == indicatorActiveIconColor &&
        other.indicatorInactiveDotColor == indicatorInactiveDotColor &&
        other.indicatorIntermediateColor == indicatorIntermediateColor &&
        other.logoBackgroundEnd == logoBackgroundEnd &&
        other.logoBackgroundStart == logoBackgroundStart &&
        other.logoTier1End == logoTier1End &&
        other.logoTier1Start == logoTier1Start &&
        other.logoTier2End == logoTier2End &&
        other.logoTier2Start == logoTier2Start &&
        other.logoTier3End == logoTier3End &&
        other.logoTier3Start == logoTier3Start &&
        other.mutedTextColor == mutedTextColor &&
        other.onErrorContainerColor == onErrorContainerColor &&
        other.onPrimaryColor == onPrimaryColor &&
        other.onPrimaryContainerColor == onPrimaryContainerColor &&
        other.onSecondaryColor == onSecondaryColor &&
        other.onSecondaryContainerColor == onSecondaryContainerColor &&
        other.primaryAccent == primaryAccent &&
        other.primaryContainerColor == primaryContainerColor &&
        other.primaryTextColor == primaryTextColor &&
        other.secondaryAccent == secondaryAccent &&
        other.secondaryContainerColor == secondaryContainerColor &&
        other.tertiaryAccent == tertiaryAccent &&
        other.warningAccent == warningAccent;
  }

  @override
  int get hashCode => Object.hashAll(<Object>[
    brightness,
    canvasColor,
    cardColor,
    dividerColor,
    elevatedSurfaceColor,
    errorColor,
    errorContainerColor,
    indicatorActiveIconColor,
    indicatorInactiveDotColor,
    indicatorIntermediateColor,
    logoBackgroundEnd,
    logoBackgroundStart,
    logoTier1End,
    logoTier1Start,
    logoTier2End,
    logoTier2Start,
    logoTier3End,
    logoTier3Start,
    mutedTextColor,
    onErrorContainerColor,
    onPrimaryColor,
    onPrimaryContainerColor,
    onSecondaryColor,
    onSecondaryContainerColor,
    primaryAccent,
    primaryContainerColor,
    primaryTextColor,
    secondaryAccent,
    secondaryContainerColor,
    tertiaryAccent,
    warningAccent,
  ]);
}

/// Pair of light and dark [AppTheme] definitions active in the application.
@immutable
class AppThemeSet {
  /// Creates an [AppThemeSet] with explicit [light] and [dark] themes.
  const AppThemeSet({required this.light, required this.dark});

  /// Creates an [AppThemeSet] that uses [theme] for both light and dark modes.
  const AppThemeSet.uniform(AppTheme theme) : light = theme, dark = theme;

  /// Signature TierTask navy and indigo light and dark theme pair.
  static const AppThemeSet navy = AppThemeSet(
    light: AppTheme.navyLight,
    dark: AppTheme.navyDark,
  );

  /// Chromium-inspired Material 3 slate blue-grey light and dark theme pair.
  static const AppThemeSet slate = AppThemeSet(
    light: AppTheme.slateLight,
    dark: AppTheme.slateDark,
  );

  /// Default TierTask light and dark theme pair (aliases [slate]).
  static const AppThemeSet standard = slate;

  /// Active dark [AppTheme].
  final AppTheme dark;

  /// Active light [AppTheme].
  final AppTheme light;

  /// Returns the [AppThemeSet] matching [palette].
  static AppThemeSet forPalette(AppThemePalette palette) {
    return switch (palette) {
      AppThemePalette.slate => slate,
      AppThemePalette.navy => navy,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is AppThemeSet && other.light == light && other.dark == dark;
  }

  @override
  int get hashCode => Object.hash(light, dark);
}
