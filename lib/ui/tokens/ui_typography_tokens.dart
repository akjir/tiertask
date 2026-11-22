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

/// Immutable typography scale and font helpers (`U-TOKEN-001`).
@immutable
class UiTypographyTokens {
  /// Creates a [UiTypographyTokens] scale with explicit font families and styles.
  const UiTypographyTokens({
    required this.sansFontFamily,
    required this.monoFontFamily,
    required this.pageTitle,
    required this.brand,
    required this.modalTitle,
    required this.compactBrand,
    required this.cardTitle,
    required this.body,
    required this.control,
    required this.rawCode,
    required this.meta,
    required this.chip,
    required this.monoSmall,
    required this.eyebrow,
    required this.micro,
    required this.devBadge,
  });

  /// Canonical sans-serif font fallback chain.
  static const List<String> sansFallback = <String>[
    'Inter',
    'Segoe UI',
    'Roboto',
    'sans-serif',
  ];

  /// Canonical monospace font fallback chain.
  static const List<String> monoFallback = <String>[
    'Cascadia Code',
    'JetBrains Mono',
    'Menlo',
    'Consolas',
    'monospace',
  ];

  /// Default TierTask typography token scale matching `U-TOKEN-001`.
  static const UiTypographyTokens standard = UiTypographyTokens(
    sansFontFamily: null,
    monoFontFamily: 'monospace',
    pageTitle: TextStyle(
      fontSize: 28.0,
      fontWeight: FontWeight.w600,
      height: 1.2,
      letterSpacing: -0.7,
      fontFamilyFallback: sansFallback,
    ),
    brand: TextStyle(
      fontSize: 18.0,
      fontWeight: FontWeight.w600,
      height: 1.2,
      letterSpacing: -0.5,
      fontFamilyFallback: sansFallback,
    ),
    modalTitle: TextStyle(
      fontSize: 17.0,
      fontWeight: FontWeight.w600,
      height: 1.3,
      fontFamilyFallback: sansFallback,
    ),
    compactBrand: TextStyle(
      fontSize: 16.0,
      fontWeight: FontWeight.w600,
      height: 1.2,
      letterSpacing: -0.3,
      fontFamilyFallback: sansFallback,
    ),
    cardTitle: TextStyle(
      fontSize: 15.0,
      fontWeight: FontWeight.w600,
      height: 1.45,
      fontFamilyFallback: sansFallback,
    ),
    body: TextStyle(
      fontSize: 14.0,
      fontWeight: FontWeight.w400,
      height: 1.45,
      fontFamilyFallback: sansFallback,
    ),
    control: TextStyle(
      fontSize: 13.0,
      fontWeight: FontWeight.w500,
      height: 1.45,
      fontFamilyFallback: sansFallback,
    ),
    rawCode: TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: monoFallback,
      fontSize: 12.5,
      fontWeight: FontWeight.w400,
      height: 1.55,
    ),
    meta: TextStyle(
      fontSize: 12.0,
      fontWeight: FontWeight.w400,
      height: 1.45,
      fontFamilyFallback: sansFallback,
    ),
    chip: TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w500,
      height: 1.45,
      fontFamilyFallback: sansFallback,
    ),
    monoSmall: TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: monoFallback,
      fontSize: 11.5,
      fontWeight: FontWeight.w400,
      height: 1.45,
    ),
    eyebrow: TextStyle(
      fontSize: 11.0,
      fontWeight: FontWeight.w600,
      height: 1.2,
      letterSpacing: 0.9,
      fontFamilyFallback: sansFallback,
    ),
    micro: TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w400,
      height: 1.45,
      fontFamilyFallback: sansFallback,
    ),
    devBadge: TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: monoFallback,
      fontSize: 10.0,
      fontWeight: FontWeight.w700,
      height: 1.2,
      letterSpacing: 0.7,
    ),
  );

  /// Default body copy (`14px`).
  final TextStyle body;

  /// Top bar brand wordmark and desktop inline active label (`18px`).
  final TextStyle brand;

  /// Entity titles, draft inputs, and mono previews (`15px`).
  final TextStyle cardTitle;

  /// Tag chips, meta pills, scope filters, and color presets (`11.5px`).
  final TextStyle chip;

  /// Compact active-label top bar button and mobile quick-add input (`16px`).
  final TextStyle compactBrand;

  /// Navigation rows, danger buttons, checkboxes, and card bodies (`13px`).
  final TextStyle control;

  /// Inline `DEV` build profile pill (`10px` bold mono).
  final TextStyle devBadge;

  /// Uppercase section eyebrows and pill badges (`11px`).
  final TextStyle eyebrow;

  /// Subtitles, field labels, count pills, banners, and log lines (`12px`).
  final TextStyle meta;

  /// Scoped queue subtitles and keyboard shortcut hints (`10.5px`).
  final TextStyle micro;

  /// Primary monospace font family name.
  final String monoFontFamily;

  /// Small monospace identifiers, paths, URLs, and coordinates (`11.5px`).
  final TextStyle monoSmall;

  /// Modal dialog header title (`17px`).
  final TextStyle modalTitle;

  /// Top-level view heading (`28px`).
  final TextStyle pageTitle;

  /// Raw `.tdf` code preview style (`12.5px` mono).
  final TextStyle rawCode;

  /// Optional primary sans-serif font family name (defaults to platform sans).
  final String? sansFontFamily;

  /// Linearly interpolates between two [UiTypographyTokens] scales at factor [t].
  static UiTypographyTokens lerp(
    UiTypographyTokens a,
    UiTypographyTokens b,
    double t,
  ) {
    if (t <= 0.0) {
      return a;
    }
    if (t >= 1.0) {
      return b;
    }
    return UiTypographyTokens(
      sansFontFamily: t < 0.5 ? a.sansFontFamily : b.sansFontFamily,
      monoFontFamily: t < 0.5 ? a.monoFontFamily : b.monoFontFamily,
      pageTitle: TextStyle.lerp(a.pageTitle, b.pageTitle, t) ?? a.pageTitle,
      brand: TextStyle.lerp(a.brand, b.brand, t) ?? a.brand,
      modalTitle: TextStyle.lerp(a.modalTitle, b.modalTitle, t) ?? a.modalTitle,
      compactBrand:
          TextStyle.lerp(a.compactBrand, b.compactBrand, t) ?? a.compactBrand,
      cardTitle: TextStyle.lerp(a.cardTitle, b.cardTitle, t) ?? a.cardTitle,
      body: TextStyle.lerp(a.body, b.body, t) ?? a.body,
      control: TextStyle.lerp(a.control, b.control, t) ?? a.control,
      rawCode: TextStyle.lerp(a.rawCode, b.rawCode, t) ?? a.rawCode,
      meta: TextStyle.lerp(a.meta, b.meta, t) ?? a.meta,
      chip: TextStyle.lerp(a.chip, b.chip, t) ?? a.chip,
      monoSmall: TextStyle.lerp(a.monoSmall, b.monoSmall, t) ?? a.monoSmall,
      eyebrow: TextStyle.lerp(a.eyebrow, b.eyebrow, t) ?? a.eyebrow,
      micro: TextStyle.lerp(a.micro, b.micro, t) ?? a.micro,
      devBadge: TextStyle.lerp(a.devBadge, b.devBadge, t) ?? a.devBadge,
    );
  }

  /// Applies the canonical monospace font family and fallbacks to [style].
  static TextStyle mono(TextStyle style) {
    return style.copyWith(
      fontFamily: standard.monoFontFamily,
      fontFamilyFallback: monoFallback,
    );
  }

  /// Attaches `FontFeature.tabularFigures()` to [style] for jitter-free counts.
  static TextStyle tabular(TextStyle style) {
    final existing = style.fontFeatures ?? const <FontFeature>[];
    if (existing.contains(const FontFeature.tabularFigures())) {
      return style;
    }
    return style.copyWith(
      fontFeatures: <FontFeature>[
        ...existing,
        const FontFeature.tabularFigures(),
      ],
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is UiTypographyTokens &&
        other.sansFontFamily == sansFontFamily &&
        other.monoFontFamily == monoFontFamily &&
        other.pageTitle == pageTitle &&
        other.brand == brand &&
        other.modalTitle == modalTitle &&
        other.compactBrand == compactBrand &&
        other.cardTitle == cardTitle &&
        other.body == body &&
        other.control == control &&
        other.rawCode == rawCode &&
        other.meta == meta &&
        other.chip == chip &&
        other.monoSmall == monoSmall &&
        other.eyebrow == eyebrow &&
        other.micro == micro &&
        other.devBadge == devBadge;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    sansFontFamily,
    monoFontFamily,
    pageTitle,
    brand,
    modalTitle,
    compactBrand,
    cardTitle,
    body,
    control,
    rawCode,
    meta,
    chip,
    monoSmall,
    eyebrow,
    micro,
    devBadge,
  ]);
}
