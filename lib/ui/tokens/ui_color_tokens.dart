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

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Immutable semantic color palette for a single theme preset and brightness (`U-TOKEN-005`).
@immutable
class UiColorTokens {
  /// Creates a [UiColorTokens] instance with all 19 semantic color roles.
  const UiColorTokens({
    required this.pageBg,
    required this.bg,
    required this.panel,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.soft,
    required this.onAccent,
    required this.danger,
    required this.dangerBg,
    required this.dangerBorder,
    required this.warning,
    required this.warningBg,
    required this.warningBorder,
    required this.success,
    required this.successBg,
    required this.successBorder,
    required this.scrim,
  });

  /// Primary brand accent foreground and active border color.
  final Color accent;

  /// Application shell canvas, list background, and inset well fill.
  final Color bg;

  /// High-contrast destructive and error foreground color.
  final Color danger;

  /// Soft tinted danger surface background.
  final Color dangerBg;

  /// Mid-contrast danger border color.
  final Color dangerBorder;

  /// Primary high-contrast body and heading foreground ink.
  final Color ink;

  /// Hairline `1px` border and divider color.
  final Color line;

  /// Secondary muted text and inactive icon color.
  final Color muted;

  /// Foreground ink placed directly on top of [accent] fills.
  final Color onAccent;

  /// Outer canvas backdrop outside the primary shell frame.
  final Color pageBg;

  /// Elevated flat resting surface for chrome, sidebar, cards, and overlays.
  final Color panel;

  /// Translucent backdrop scrim behind drawers, bottom sheets, and modals.
  final Color scrim;

  /// Accent-tinted active/selected surface paired exclusively with [accent].
  final Color soft;

  /// High-contrast success foreground color.
  final Color success;

  /// Soft tinted success surface background.
  final Color successBg;

  /// Mid-contrast success border color.
  final Color successBorder;

  /// High-contrast warning foreground color.
  final Color warning;

  /// Soft tinted warning surface background.
  final Color warningBg;

  /// Mid-contrast warning border color.
  final Color warningBorder;

  /// Returns a copy of this palette with selected roles replaced.
  UiColorTokens copyWith({
    Color? pageBg,
    Color? bg,
    Color? panel,
    Color? ink,
    Color? muted,
    Color? line,
    Color? accent,
    Color? soft,
    Color? onAccent,
    Color? danger,
    Color? dangerBg,
    Color? dangerBorder,
    Color? warning,
    Color? warningBg,
    Color? warningBorder,
    Color? success,
    Color? successBg,
    Color? successBorder,
    Color? scrim,
  }) {
    return UiColorTokens(
      pageBg: pageBg ?? this.pageBg,
      bg: bg ?? this.bg,
      panel: panel ?? this.panel,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      line: line ?? this.line,
      accent: accent ?? this.accent,
      soft: soft ?? this.soft,
      onAccent: onAccent ?? this.onAccent,
      danger: danger ?? this.danger,
      dangerBg: dangerBg ?? this.dangerBg,
      dangerBorder: dangerBorder ?? this.dangerBorder,
      warning: warning ?? this.warning,
      warningBg: warningBg ?? this.warningBg,
      warningBorder: warningBorder ?? this.warningBorder,
      success: success ?? this.success,
      successBg: successBg ?? this.successBg,
      successBorder: successBorder ?? this.successBorder,
      scrim: scrim ?? this.scrim,
    );
  }

  /// Linearly interpolates between two [UiColorTokens] palettes at factor [t].
  static UiColorTokens lerp(UiColorTokens a, UiColorTokens b, double t) {
    if (t <= 0.0) {
      return a;
    }
    if (t >= 1.0) {
      return b;
    }
    return UiColorTokens(
      pageBg: Color.lerp(a.pageBg, b.pageBg, t) ?? a.pageBg,
      bg: Color.lerp(a.bg, b.bg, t) ?? a.bg,
      panel: Color.lerp(a.panel, b.panel, t) ?? a.panel,
      ink: Color.lerp(a.ink, b.ink, t) ?? a.ink,
      muted: Color.lerp(a.muted, b.muted, t) ?? a.muted,
      line: Color.lerp(a.line, b.line, t) ?? a.line,
      accent: Color.lerp(a.accent, b.accent, t) ?? a.accent,
      soft: Color.lerp(a.soft, b.soft, t) ?? a.soft,
      onAccent: Color.lerp(a.onAccent, b.onAccent, t) ?? a.onAccent,
      danger: Color.lerp(a.danger, b.danger, t) ?? a.danger,
      dangerBg: Color.lerp(a.dangerBg, b.dangerBg, t) ?? a.dangerBg,
      dangerBorder:
          Color.lerp(a.dangerBorder, b.dangerBorder, t) ?? a.dangerBorder,
      warning: Color.lerp(a.warning, b.warning, t) ?? a.warning,
      warningBg: Color.lerp(a.warningBg, b.warningBg, t) ?? a.warningBg,
      warningBorder:
          Color.lerp(a.warningBorder, b.warningBorder, t) ?? a.warningBorder,
      success: Color.lerp(a.success, b.success, t) ?? a.success,
      successBg: Color.lerp(a.successBg, b.successBg, t) ?? a.successBg,
      successBorder:
          Color.lerp(a.successBorder, b.successBorder, t) ?? a.successBorder,
      scrim: Color.lerp(a.scrim, b.scrim, t) ?? a.scrim,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is UiColorTokens &&
        other.pageBg == pageBg &&
        other.bg == bg &&
        other.panel == panel &&
        other.ink == ink &&
        other.muted == muted &&
        other.line == line &&
        other.accent == accent &&
        other.soft == soft &&
        other.onAccent == onAccent &&
        other.danger == danger &&
        other.dangerBg == dangerBg &&
        other.dangerBorder == dangerBorder &&
        other.warning == warning &&
        other.warningBg == warningBg &&
        other.warningBorder == warningBorder &&
        other.success == success &&
        other.successBg == successBg &&
        other.successBorder == successBorder &&
        other.scrim == scrim;
  }

  @override
  int get hashCode => Object.hashAll(<Object>[
    pageBg,
    bg,
    panel,
    ink,
    muted,
    line,
    accent,
    soft,
    onAccent,
    danger,
    dangerBg,
    dangerBorder,
    warning,
    warningBg,
    warningBorder,
    success,
    successBg,
    successBorder,
    scrim,
  ]);
}

/// Named foreground/background color pair evaluated by [UiContrastChecker].
@immutable
class UiContrastPair {
  /// Creates a [UiContrastPair].
  const UiContrastPair({
    required this.name,
    required this.foreground,
    required this.background,
  });

  /// Background surface color.
  final Color background;

  /// Foreground text or icon color.
  final Color foreground;

  /// Human-readable label for the color pair.
  final String name;
}

/// Describes a WCAG AA contrast violation detected by [UiContrastChecker].
@immutable
class UiContrastFailure {
  /// Creates a [UiContrastFailure].
  const UiContrastFailure({
    required this.pairName,
    required this.ratio,
    required this.requiredRatio,
  });

  /// Descriptive name of the failing foreground/background pair.
  final String pairName;

  /// Computed WCAG 2.1 contrast ratio.
  final double ratio;

  /// Minimum required contrast ratio (`4.5`).
  final double requiredRatio;

  @override
  String toString() {
    return 'UiContrastFailure($pairName: '
        '${ratio.toStringAsFixed(2)}:1 < ${requiredRatio.toStringAsFixed(1)}:1)';
  }
}

/// Stateless WCAG 2.1 contrast calculator and token validator (`U-TOKEN-006`).
class UiContrastChecker {
  const UiContrastChecker._();

  /// Minimum WCAG AA normal-text contrast ratio (`4.5:1`).
  static const double wcagAaMinimum = 4.5;

  /// Composites a potentially translucent [foreground] over opaque [background].
  static Color compositeOver(Color foreground, Color background) {
    final alpha = foreground.a;
    if (alpha >= 1.0) {
      return foreground;
    }
    final inverse = 1.0 - alpha;
    final red = foreground.r * alpha + background.r * inverse;
    final green = foreground.g * alpha + background.g * inverse;
    final blue = foreground.b * alpha + background.b * inverse;
    return Color.from(alpha: 1.0, red: red, green: green, blue: blue);
  }

  /// Computes the WCAG 2.1 contrast ratio between [foreground] and [background].
  static double contrastRatio(Color foreground, Color background) {
    final composited = compositeOver(foreground, background);
    final lumForeground = relativeLuminance(composited);
    final lumBackground = relativeLuminance(background);
    final lighter = math.max(lumForeground, lumBackground);
    final darker = math.min(lumForeground, lumBackground);
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Returns whether [foreground] over [background] meets WCAG AA (`>= 4.5:1`).
  static bool meetsWcagAa(Color foreground, Color background) {
    return contrastRatio(foreground, background) >= wcagAaMinimum;
  }

  /// Returns all 17 normative foreground/background pairs for [tokens].
  static List<UiContrastPair> normativePairs(UiColorTokens tokens) {
    return <UiContrastPair>[
      UiContrastPair(
        name: 'ink on panel',
        foreground: tokens.ink,
        background: tokens.panel,
      ),
      UiContrastPair(
        name: 'muted on panel',
        foreground: tokens.muted,
        background: tokens.panel,
      ),
      UiContrastPair(
        name: 'accent on panel',
        foreground: tokens.accent,
        background: tokens.panel,
      ),
      UiContrastPair(
        name: 'danger on panel',
        foreground: tokens.danger,
        background: tokens.panel,
      ),
      UiContrastPair(
        name: 'warning on panel',
        foreground: tokens.warning,
        background: tokens.panel,
      ),
      UiContrastPair(
        name: 'success on panel',
        foreground: tokens.success,
        background: tokens.panel,
      ),
      UiContrastPair(
        name: 'ink on bg',
        foreground: tokens.ink,
        background: tokens.bg,
      ),
      UiContrastPair(
        name: 'muted on bg',
        foreground: tokens.muted,
        background: tokens.bg,
      ),
      UiContrastPair(
        name: 'accent on bg',
        foreground: tokens.accent,
        background: tokens.bg,
      ),
      UiContrastPair(
        name: 'danger on bg',
        foreground: tokens.danger,
        background: tokens.bg,
      ),
      UiContrastPair(
        name: 'warning on bg',
        foreground: tokens.warning,
        background: tokens.bg,
      ),
      UiContrastPair(
        name: 'success on bg',
        foreground: tokens.success,
        background: tokens.bg,
      ),
      UiContrastPair(
        name: 'accent on soft',
        foreground: tokens.accent,
        background: tokens.soft,
      ),
      UiContrastPair(
        name: 'onAccent on accent',
        foreground: tokens.onAccent,
        background: tokens.accent,
      ),
      UiContrastPair(
        name: 'danger on dangerBg',
        foreground: tokens.danger,
        background: tokens.dangerBg,
      ),
      UiContrastPair(
        name: 'warning on warningBg',
        foreground: tokens.warning,
        background: tokens.warningBg,
      ),
      UiContrastPair(
        name: 'success on successBg',
        foreground: tokens.success,
        background: tokens.successBg,
      ),
    ];
  }

  /// Computes the WCAG 2.1 relative luminance (`0.0..1.0`) of an sRGB [color].
  static double relativeLuminance(Color color) {
    final red = _linearizeChannel(color.r);
    final green = _linearizeChannel(color.g);
    final blue = _linearizeChannel(color.b);
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
  }

  /// Validates all 17 normative pairs in [tokens] and returns any WCAG AA failures.
  static List<UiContrastFailure> verifyTokens(UiColorTokens tokens) {
    final failures = <UiContrastFailure>[];
    for (final pair in normativePairs(tokens)) {
      final ratio = contrastRatio(pair.foreground, pair.background);
      if (ratio < wcagAaMinimum) {
        failures.add(
          UiContrastFailure(
            pairName: pair.name,
            ratio: ratio,
            requiredRatio: wcagAaMinimum,
          ),
        );
      }
    }
    return List<UiContrastFailure>.unmodifiable(failures);
  }

  /// Linearizes a single normalized sRGB channel value (`0.0..1.0`).
  static double _linearizeChannel(double channel) {
    if (channel <= 0.04045) {
      return channel / 12.92;
    }
    return math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  }
}
