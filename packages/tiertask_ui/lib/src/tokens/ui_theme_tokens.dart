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

import 'package:material_ui/material_ui.dart';

import 'ui_color_tokens.dart';
import 'ui_focus_tokens.dart';
import 'ui_radius_tokens.dart';
import 'ui_spacing_tokens.dart';
import 'ui_typography_tokens.dart';

/// Identifies the current container surface tier for automatic surface alternation (`U-SURFACE-003`).
enum UiSurfaceLevel {
  /// Standard `panel` surface where inputs and chips rest on `bg`.
  panel,

  /// Nested `bg` inset well where inputs, pills, and rows re-elevate to `panel`.
  insetWell,
}

/// Propagates the active [UiSurfaceLevel] down the widget tree so nested controls re-elevate automatically.
class UiSurfaceScope extends InheritedWidget {
  /// Creates a [UiSurfaceScope] declaring [level] for descendants in [child].
  const UiSurfaceScope({super.key, required this.level, required super.child});

  /// Surface tier provided to descendant fields, pills, and interactive rows.
  final UiSurfaceLevel level;

  /// Returns the nearest ancestor [UiSurfaceLevel], defaulting to [UiSurfaceLevel.panel].
  static UiSurfaceLevel of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<UiSurfaceScope>();
    return scope?.level ?? UiSurfaceLevel.panel;
  }

  @override
  bool updateShouldNotify(covariant UiSurfaceScope oldWidget) {
    return oldWidget.level != level;
  }
}

/// Unified [ThemeExtension] carrying all Layer 1 visual design tokens and Material 3 [ThemeData] builder.
@immutable
class UiThemeTokens extends ThemeExtension<UiThemeTokens> {
  /// Creates a [UiThemeTokens] bundle for one preset and [brightness].
  const UiThemeTokens({
    required this.brightness,
    required this.colors,
    this.typography = UiTypographyTokens.standard,
    this.spacing = UiSpacingTokens.standard,
    this.radii = UiRadiusTokens.standard,
    this.focus = UiFocusTokens.standard,
  });

  /// Active theme brightness (`Brightness.light` or `Brightness.dark`).
  final Brightness brightness;

  /// Semantic 19-role color token palette.
  final UiColorTokens colors;

  /// Focus ring, motion duration, dimmed opacity, and allowlisted shadow tokens.
  final UiFocusTokens focus;

  /// Corner radius and stroke width tokens.
  final UiRadiusTokens radii;

  /// Spacing, hit-target density, icon size, and shell geometry tokens.
  final UiSpacingTokens spacing;

  /// Typography scale and monospace/tabular helpers.
  final UiTypographyTokens typography;

  /// Resolves the active [UiThemeTokens] from [context], falling back deterministically to `Calm` by brightness.
  static UiThemeTokens of(BuildContext context) {
    final theme = Theme.of(context);
    final extension = theme.extension<UiThemeTokens>();
    if (extension != null) {
      return extension;
    }
    return theme.brightness == Brightness.dark
        ? UiThemePresets.calm.dark
        : UiThemePresets.calm.light;
  }

  @override
  UiThemeTokens copyWith({
    Brightness? brightness,
    UiColorTokens? colors,
    UiTypographyTokens? typography,
    UiSpacingTokens? spacing,
    UiRadiusTokens? radii,
    UiFocusTokens? focus,
  }) {
    return UiThemeTokens(
      brightness: brightness ?? this.brightness,
      colors: colors ?? this.colors,
      typography: typography ?? this.typography,
      spacing: spacing ?? this.spacing,
      radii: radii ?? this.radii,
      focus: focus ?? this.focus,
    );
  }

  @override
  UiThemeTokens lerp(ThemeExtension<UiThemeTokens>? other, double t) {
    if (other is! UiThemeTokens) {
      return this;
    }
    if (t <= 0.0) {
      return this;
    }
    if (t >= 1.0) {
      return other;
    }
    return UiThemeTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      colors: UiColorTokens.lerp(colors, other.colors, t),
      typography: UiTypographyTokens.lerp(typography, other.typography, t),
      spacing: UiSpacingTokens.lerp(spacing, other.spacing, t),
      radii: UiRadiusTokens.lerp(radii, other.radii, t),
      focus: UiFocusTokens.lerp(focus, other.focus, t),
    );
  }

  /// Builds a flat zero-elevation Material 3 [ThemeData] configured with this [UiThemeTokens] extension.
  ThemeData toThemeData() {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: colors.accent,
      onPrimary: colors.onAccent,
      primaryContainer: colors.soft,
      onPrimaryContainer: colors.accent,
      secondary: colors.accent,
      onSecondary: colors.onAccent,
      secondaryContainer: colors.soft,
      onSecondaryContainer: colors.accent,
      tertiary: colors.success,
      onTertiary: colors.onAccent,
      tertiaryContainer: colors.successBg,
      onTertiaryContainer: colors.success,
      error: colors.danger,
      onError: colors.onAccent,
      errorContainer: colors.dangerBg,
      onErrorContainer: colors.danger,
      surface: colors.panel,
      onSurface: colors.ink,
      surfaceContainerLowest: colors.pageBg,
      surfaceContainerLow: colors.bg,
      surfaceContainer: colors.bg,
      surfaceContainerHigh: colors.panel,
      surfaceContainerHighest: colors.panel,
      onSurfaceVariant: colors.muted,
      outline: colors.line,
      outlineVariant: colors.line,
      scrim: colors.scrim,
    );

    final textTheme = TextTheme(
      headlineLarge: typography.pageTitle.copyWith(color: colors.ink),
      headlineMedium: typography.pageTitle.copyWith(color: colors.ink),
      titleLarge: typography.brand.copyWith(color: colors.ink),
      titleMedium: typography.cardTitle.copyWith(color: colors.ink),
      titleSmall: typography.control.copyWith(color: colors.ink),
      bodyLarge: typography.body.copyWith(color: colors.ink),
      bodyMedium: typography.body.copyWith(color: colors.ink),
      bodySmall: typography.meta.copyWith(color: colors.muted),
      labelLarge: typography.control.copyWith(color: colors.ink),
      labelMedium: typography.meta.copyWith(color: colors.ink),
      labelSmall: typography.eyebrow.copyWith(color: colors.muted),
    );

    final borderRadius = BorderRadius.circular(radii.md);
    final restingBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: colors.line, width: radii.borderWidth),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: colors.accent, width: radii.borderWidth),
    );
    final errorBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: colors.danger, width: radii.borderWidth),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.bg,
      canvasColor: colors.panel,
      cardColor: colors.panel,
      dividerColor: colors.line,
      focusColor: colors.soft,
      hoverColor: colors.soft,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.panel,
        foregroundColor: colors.ink,
        elevation: 0.0,
        scrolledUnderElevation: 0.0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: colors.panel,
        elevation: 0.0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radii.card),
          side: BorderSide(color: colors.line, width: radii.borderWidth),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.panel,
        elevation: 0.0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radii.shell),
          side: BorderSide(color: colors.line, width: radii.borderWidth),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.line,
        thickness: radii.borderWidth,
        space: radii.borderWidth,
      ),
      iconTheme: IconThemeData(color: colors.muted, size: spacing.iconSm),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.bg,
        isDense: true,
        hintStyle: typography.control.copyWith(color: colors.muted),
        border: restingBorder,
        enabledBorder: restingBorder,
        focusedBorder: focusedBorder,
        errorBorder: errorBorder,
        focusedErrorBorder: errorBorder,
        disabledBorder: restingBorder,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll<Color>(colors.line),
        radius: Radius.circular(radii.pill),
        thickness: const WidgetStatePropertyAll<double>(6.0),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.accent,
        selectionColor: colors.soft,
        selectionHandleColor: colors.accent,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.ink,
          borderRadius: BorderRadius.circular(radii.tag),
        ),
        textStyle: typography.meta.copyWith(color: colors.panel),
      ),
      extensions: <ThemeExtension<UiThemeTokens>>[this],
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is UiThemeTokens &&
        other.brightness == brightness &&
        other.colors == colors &&
        other.typography == typography &&
        other.spacing == spacing &&
        other.radii == radii &&
        other.focus == focus;
  }

  @override
  int get hashCode =>
      Object.hash(brightness, colors, typography, spacing, radii, focus);
}

/// Extensible Light and Dark [UiThemeTokens] preset pair.
@immutable
class UiThemePreset {
  /// Creates a [UiThemePreset] identified by [id] with [light] and [dark] token bundles.
  const UiThemePreset({
    required this.id,
    required this.light,
    required this.dark,
  });

  /// Dark mode theme tokens.
  final UiThemeTokens dark;

  /// Stable preset identifier (`'calm'`, `'plum_umber'`).
  final String id;

  /// Light mode theme tokens.
  final UiThemeTokens light;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is UiThemePreset &&
        other.id == id &&
        other.light == light &&
        other.dark == dark;
  }

  @override
  int get hashCode => Object.hash(id, light, dark);
}

/// Built-in WCAG AA verified TierTask theme preset registry (`U-TOKEN-005`).
class UiThemePresets {
  const UiThemePresets._();

  /// Ordered list of all built-in TierTask theme presets.
  static const List<UiThemePreset> all = <UiThemePreset>[calm, plumUmber];

  /// Default cool slate-blue `Calm` preset (Light and Dark).
  static const UiThemePreset calm = UiThemePreset(
    id: 'calm',
    light: UiThemeTokens(
      brightness: Brightness.light,
      colors: UiColorTokens(
        pageBg: Color(0xFFE7EEF2),
        bg: Color(0xFFF0F4F7),
        panel: Color(0xFFFFFFFF),
        ink: Color(0xFF202C33),
        muted: Color(0xFF53646F),
        line: Color(0xFFD8E2E8),
        accent: Color(0xFF00648B),
        soft: Color(0xFFE0EFF7),
        onAccent: Color(0xFFFFFFFF),
        danger: Color(0xFFA12A2A),
        dangerBg: Color(0xFFFDECEC),
        dangerBorder: Color(0xFFD99B9B),
        warning: Color(0xFF8A4B00),
        warningBg: Color(0xFFFFF3DF),
        warningBorder: Color(0xFFDFB87A),
        success: Color(0xFF17633B),
        successBg: Color(0xFFE6F5EC),
        successBorder: Color(0xFF9BD1B2),
        scrim: Color.fromRGBO(16, 28, 36, 0.46),
      ),
    ),
    dark: UiThemeTokens(
      brightness: Brightness.dark,
      colors: UiColorTokens(
        pageBg: Color(0xFF111B20),
        bg: Color(0xFF19262D),
        panel: Color(0xFF243239),
        ink: Color(0xFFEDF2F5),
        muted: Color(0xFFB5C4CC),
        line: Color(0xFF3E505A),
        accent: Color(0xFF9AC7E9),
        soft: Color(0xFF1C4255),
        onAccent: Color(0xFF132A36),
        danger: Color(0xFFFFC0C0),
        dangerBg: Color(0xFF472529),
        dangerBorder: Color(0xFF8D4B52),
        warning: Color(0xFFF5C26B),
        warningBg: Color(0xFF3B2F1D),
        warningBorder: Color(0xFF785B2C),
        success: Color(0xFF8BE0AD),
        successBg: Color(0xFF1A3B2C),
        successBorder: Color(0xFF387556),
        scrim: Color.fromRGBO(7, 13, 17, 0.62),
      ),
    ),
  );

  /// Warm purple-and-umber `Plum Umber` preset (Light and Dark).
  static const UiThemePreset plumUmber = UiThemePreset(
    id: 'plum_umber',
    light: UiThemeTokens(
      brightness: Brightness.light,
      colors: UiColorTokens(
        pageBg: Color(0xFFECE5E0),
        bg: Color(0xFFF6F2EF),
        panel: Color(0xFFFFFDFB),
        ink: Color(0xFF2C2220),
        muted: Color(0xFF63534F),
        line: Color(0xFFE2D7D2),
        accent: Color(0xFF6B3FA0),
        soft: Color(0xFFF0E7F8),
        onAccent: Color(0xFFFFFFFF),
        danger: Color(0xFFA12A2A),
        dangerBg: Color(0xFFFCEBEB),
        dangerBorder: Color(0xFFD99B9B),
        warning: Color(0xFF8A4B00),
        warningBg: Color(0xFFFDF1DF),
        warningBorder: Color(0xFFDFB87A),
        success: Color(0xFF17633B),
        successBg: Color(0xFFE6F4EC),
        successBorder: Color(0xFF9BD1B2),
        scrim: Color.fromRGBO(24, 16, 15, 0.48),
      ),
    ),
    dark: UiThemeTokens(
      brightness: Brightness.dark,
      colors: UiColorTokens(
        pageBg: Color(0xFF161110),
        bg: Color(0xFF1F1918),
        panel: Color(0xFF2B2322),
        ink: Color(0xFFF3ECEA),
        muted: Color(0xFFC3B4B0),
        line: Color(0xFF473A38),
        accent: Color(0xFFC5A3F5),
        soft: Color(0xFF362945),
        onAccent: Color(0xFF1E1429),
        danger: Color(0xFFFFB8B8),
        dangerBg: Color(0xFF4A2326),
        dangerBorder: Color(0xFF8D494E),
        warning: Color(0xFFF5C26B),
        warningBg: Color(0xFF3E2E1D),
        warningBorder: Color(0xFF7A5C2C),
        success: Color(0xFF8BE0AD),
        successBg: Color(0xFF1D3A2A),
        successBorder: Color(0xFF3B7454),
        scrim: Color.fromRGBO(12, 8, 8, 0.64),
      ),
    ),
  );

  /// Resolves a built-in [UiThemePreset] by [id], falling back to [calm].
  static UiThemePreset byId(String id) {
    return switch (id) {
      'plum_umber' => plumUmber,
      _ => calm,
    };
  }
}
