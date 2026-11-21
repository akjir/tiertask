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

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask_ui/tiertask_ui.dart';

import '../test_helpers.dart';

void main() {
  group('UiThemeTokens, UiThemePresets, and UiSurfaceScope', () {
    test('resolves built-in presets by id with Calm fallback', () {
      expect(UiThemePresets.all.length, equals(2));
      expect(UiThemePresets.byId('calm'), equals(UiThemePresets.calm));
      expect(
        UiThemePresets.byId('plum_umber'),
        equals(UiThemePresets.plumUmber),
      );
      expect(UiThemePresets.byId('unknown_id'), equals(UiThemePresets.calm));
      expect(UiThemePresets.calm.id, equals('calm'));
      expect(UiThemePresets.plumUmber.id, equals('plum_umber'));
    });

    test('interpolates UiThemeTokens cleanly at 0.0, 0.5, and 1.0', () {
      final light = UiThemePresets.calm.light;
      final dark = UiThemePresets.plumUmber.dark;
      expect(light.lerp(dark, 0.0), equals(light));
      expect(light.lerp(dark, 1.0), equals(dark));
      final mid = light.lerp(dark, 0.5);
      expect(mid.colors.bg, isNot(equals(light.colors.bg)));
      expect(mid.colors.bg, isNot(equals(dark.colors.bg)));
      expect(light.lerp(null, 0.5), equals(light));
    });

    test('exposes typography scale, mono, and tabular figure helpers', () {
      const typography = UiTypographyTokens.standard;
      expect(typography.pageTitle.fontSize, equals(28.0));
      expect(typography.brand.fontSize, equals(18.0));
      expect(typography.modalTitle.fontSize, equals(17.0));
      expect(typography.compactBrand.fontSize, equals(16.0));
      expect(typography.cardTitle.fontSize, equals(15.0));
      expect(typography.body.fontSize, equals(14.0));
      expect(typography.control.fontSize, equals(13.0));
      expect(typography.rawCode.fontSize, equals(12.5));
      expect(typography.meta.fontSize, equals(12.0));
      expect(typography.chip.fontSize, equals(11.5));
      expect(typography.monoSmall.fontSize, equals(11.5));
      expect(typography.eyebrow.fontSize, equals(11.0));
      expect(typography.micro.fontSize, equals(10.5));
      expect(typography.devBadge.fontSize, equals(10.0));

      final monoStyle = UiTypographyTokens.mono(typography.meta);
      expect(monoStyle.fontFamily, equals(typography.monoFontFamily));

      final tabularStyle = UiTypographyTokens.tabular(typography.meta);
      expect(
        tabularStyle.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    test('exposes canonical spacing, radius, and focus token values', () {
      const spacing = UiSpacingTokens.standard;
      expect(spacing.chromeHeight, equals(62.0));
      expect(spacing.sidebarWidth, equals(244.0));
      expect(spacing.touchTarget, equals(40.0));
      expect(spacing.touchTargetMobile, equals(44.0));
      expect(spacing.iconXs, equals(13.0));
      expect(spacing.iconSm, equals(15.0));
      expect(spacing.iconMd, equals(18.0));
      expect(spacing.iconLg, equals(34.0));
      expect(
        spacing.mainContentPadding(UiViewportClass.compact),
        equals(spacing.mainPaddingCompact),
      );
      expect(
        spacing.mainContentPadding(UiViewportClass.expanded),
        equals(spacing.mainPaddingDesktop),
      );

      const radii = UiRadiusTokens.standard;
      expect(radii.logoBar, equals(2.0));
      expect(radii.tag, equals(6.0));
      expect(radii.sm, equals(7.0));
      expect(radii.md, equals(8.0));
      expect(radii.tierSelect, equals(9.0));
      expect(radii.row, equals(11.0));
      expect(radii.card, equals(13.0));
      expect(radii.shell, equals(16.0));
      expect(radii.pill, equals(999.0));
      expect(radii.borderWidth, equals(1.0));
      expect(radii.circleBorderWidth, equals(1.7));
      expect(radii.spinnerStrokeWidth, equals(2.5));

      const focus = UiFocusTokens.standard;
      expect(focus.ringWidth, equals(1.0));
      expect(focus.ringOffset, equals(1.0));
      expect(focus.hoverDuration, equals(const Duration(milliseconds: 120)));
      expect(focus.expandDuration, equals(const Duration(milliseconds: 220)));
      expect(focus.fadeDuration, equals(const Duration(milliseconds: 180)));
      expect(focus.disabledOpacity, equals(0.48));
      expect(focus.prereqDisabledOpacity, equals(0.50));
      expect(focus.suspendedDimmedOpacity, equals(0.45));
      expect(focus.readonlyOpacity, equals(0.72));
      expect(focus.segmentedShadow, hasLength(1));
      expect(focus.toastShadow, hasLength(1));
      expect(focus.popoverShadow, hasLength(1));
      expect(focus.bottomSheetShadow, hasLength(1));
      expect(focus.modalShadow, hasLength(1));
    });

    testWidgets(
      'UiThemeTokens.of falls back deterministically by brightness without extension',
      (tester) async {
        late UiThemeTokens resolvedLight;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.light(),
            home: Builder(
              builder: (context) {
                resolvedLight = UiThemeTokens.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(resolvedLight, equals(UiThemePresets.calm.light));

        late UiThemeTokens resolvedDark;
        await tester.pumpWidget(
          MaterialApp(
            key: const ValueKey<String>('dark_fallback_app'),
            theme: ThemeData.dark(),
            home: Builder(
              builder: (context) {
                resolvedDark = UiThemeTokens.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(resolvedDark, equals(UiThemePresets.calm.dark));
      },
    );

    testWidgets(
      'toThemeData registers flat Material 3 theme and UiSurfaceScope alternates surface levels',
      (tester) async {
        late ThemeData capturedTheme;
        late UiSurfaceLevel outerLevel;
        late UiSurfaceLevel innerLevel;

        await pumpUiWidget(
          tester,
          Builder(
            builder: (context) {
              capturedTheme = Theme.of(context);
              outerLevel = UiSurfaceScope.of(context);
              return UiSurfaceScope(
                level: UiSurfaceLevel.insetWell,
                child: Builder(
                  builder: (nestedContext) {
                    innerLevel = UiSurfaceScope.of(nestedContext);
                    return const SizedBox.shrink();
                  },
                ),
              );
            },
          ),
          tokens: UiThemePresets.plumUmber.dark,
        );

        expect(
          capturedTheme.extension<UiThemeTokens>(),
          equals(UiThemePresets.plumUmber.dark),
        );
        expect(
          capturedTheme.scaffoldBackgroundColor,
          equals(UiThemePresets.plumUmber.dark.colors.bg),
        );
        expect(
          capturedTheme.cardColor,
          equals(UiThemePresets.plumUmber.dark.colors.panel),
        );
        expect(
          capturedTheme.dividerColor,
          equals(UiThemePresets.plumUmber.dark.colors.line),
        );
        expect(capturedTheme.appBarTheme.elevation, equals(0.0));
        expect(capturedTheme.appBarTheme.scrolledUnderElevation, equals(0.0));
        expect(
          capturedTheme.appBarTheme.surfaceTintColor,
          equals(Colors.transparent),
        );
        expect(outerLevel, equals(UiSurfaceLevel.panel));
        expect(innerLevel, equals(UiSurfaceLevel.insetWell));
      },
    );
  });
}
