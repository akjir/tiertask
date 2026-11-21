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

void main() {
  group('UiColorTokens and UiContrastChecker', () {
    test('verifies exact U-TOKEN-005 hex values for Calm Light and Dark', () {
      final light = UiThemePresets.calm.light.colors;
      expect(light.pageBg, equals(const Color(0xFFE7EEF2)));
      expect(light.bg, equals(const Color(0xFFF0F4F7)));
      expect(light.panel, equals(const Color(0xFFFFFFFF)));
      expect(light.ink, equals(const Color(0xFF202C33)));
      expect(light.muted, equals(const Color(0xFF53646F)));
      expect(light.line, equals(const Color(0xFFD8E2E8)));
      expect(light.accent, equals(const Color(0xFF00648B)));
      expect(light.soft, equals(const Color(0xFFE0EFF7)));
      expect(light.onAccent, equals(const Color(0xFFFFFFFF)));
      expect(light.danger, equals(const Color(0xFFA12A2A)));
      expect(light.dangerBg, equals(const Color(0xFFFDECEC)));
      expect(light.dangerBorder, equals(const Color(0xFFD99B9B)));
      expect(light.warning, equals(const Color(0xFF8A4B00)));
      expect(light.warningBg, equals(const Color(0xFFFFF3DF)));
      expect(light.warningBorder, equals(const Color(0xFFDFB87A)));
      expect(light.success, equals(const Color(0xFF17633B)));
      expect(light.successBg, equals(const Color(0xFFE6F5EC)));
      expect(light.successBorder, equals(const Color(0xFF9BD1B2)));
      expect(light.scrim, equals(const Color.fromRGBO(16, 28, 36, 0.46)));

      final dark = UiThemePresets.calm.dark.colors;
      expect(dark.pageBg, equals(const Color(0xFF111B20)));
      expect(dark.bg, equals(const Color(0xFF19262D)));
      expect(dark.panel, equals(const Color(0xFF243239)));
      expect(dark.ink, equals(const Color(0xFFEDF2F5)));
      expect(dark.muted, equals(const Color(0xFFB5C4CC)));
      expect(dark.line, equals(const Color(0xFF3E505A)));
      expect(dark.accent, equals(const Color(0xFF9AC7E9)));
      expect(dark.soft, equals(const Color(0xFF1C4255)));
      expect(dark.onAccent, equals(const Color(0xFF132A36)));
      expect(dark.danger, equals(const Color(0xFFFFC0C0)));
      expect(dark.dangerBg, equals(const Color(0xFF472529)));
      expect(dark.dangerBorder, equals(const Color(0xFF8D4B52)));
      expect(dark.warning, equals(const Color(0xFFF5C26B)));
      expect(dark.warningBg, equals(const Color(0xFF3B2F1D)));
      expect(dark.warningBorder, equals(const Color(0xFF785B2C)));
      expect(dark.success, equals(const Color(0xFF8BE0AD)));
      expect(dark.successBg, equals(const Color(0xFF1A3B2C)));
      expect(dark.successBorder, equals(const Color(0xFF387556)));
      expect(dark.scrim, equals(const Color.fromRGBO(7, 13, 17, 0.62)));
    });

    test(
      'verifies exact U-TOKEN-005 hex values for Plum Umber Light and Dark',
      () {
        final light = UiThemePresets.plumUmber.light.colors;
        expect(light.pageBg, equals(const Color(0xFFECE5E0)));
        expect(light.bg, equals(const Color(0xFFF6F2EF)));
        expect(light.panel, equals(const Color(0xFFFFFDFB)));
        expect(light.ink, equals(const Color(0xFF2C2220)));
        expect(light.muted, equals(const Color(0xFF63534F)));
        expect(light.line, equals(const Color(0xFFE2D7D2)));
        expect(light.accent, equals(const Color(0xFF6B3FA0)));
        expect(light.soft, equals(const Color(0xFFF0E7F8)));
        expect(light.onAccent, equals(const Color(0xFFFFFFFF)));
        expect(light.danger, equals(const Color(0xFFA12A2A)));
        expect(light.dangerBg, equals(const Color(0xFFFCEBEB)));
        expect(light.dangerBorder, equals(const Color(0xFFD99B9B)));
        expect(light.warning, equals(const Color(0xFF8A4B00)));
        expect(light.warningBg, equals(const Color(0xFFFDF1DF)));
        expect(light.warningBorder, equals(const Color(0xFFDFB87A)));
        expect(light.success, equals(const Color(0xFF17633B)));
        expect(light.successBg, equals(const Color(0xFFE6F4EC)));
        expect(light.successBorder, equals(const Color(0xFF9BD1B2)));
        expect(light.scrim, equals(const Color.fromRGBO(24, 16, 15, 0.48)));

        final dark = UiThemePresets.plumUmber.dark.colors;
        expect(dark.pageBg, equals(const Color(0xFF161110)));
        expect(dark.bg, equals(const Color(0xFF1F1918)));
        expect(dark.panel, equals(const Color(0xFF2B2322)));
        expect(dark.ink, equals(const Color(0xFFF3ECEA)));
        expect(dark.muted, equals(const Color(0xFFC3B4B0)));
        expect(dark.line, equals(const Color(0xFF473A38)));
        expect(dark.accent, equals(const Color(0xFFC5A3F5)));
        expect(dark.soft, equals(const Color(0xFF362945)));
        expect(dark.onAccent, equals(const Color(0xFF1E1429)));
        expect(dark.danger, equals(const Color(0xFFFFB8B8)));
        expect(dark.dangerBg, equals(const Color(0xFF4A2326)));
        expect(dark.dangerBorder, equals(const Color(0xFF8D494E)));
        expect(dark.warning, equals(const Color(0xFFF5C26B)));
        expect(dark.warningBg, equals(const Color(0xFF3E2E1D)));
        expect(dark.warningBorder, equals(const Color(0xFF7A5C2C)));
        expect(dark.success, equals(const Color(0xFF8BE0AD)));
        expect(dark.successBg, equals(const Color(0xFF1D3A2A)));
        expect(dark.successBorder, equals(const Color(0xFF3B7454)));
        expect(dark.scrim, equals(const Color.fromRGBO(12, 8, 8, 0.64)));
      },
    );

    test(
      'passes WCAG AA contrast >= 4.5:1 across all 17 pairs for all 4 presets',
      () {
        final presets = <(String, UiColorTokens)>[
          ('calm.light', UiThemePresets.calm.light.colors),
          ('calm.dark', UiThemePresets.calm.dark.colors),
          ('plumUmber.light', UiThemePresets.plumUmber.light.colors),
          ('plumUmber.dark', UiThemePresets.plumUmber.dark.colors),
        ];

        for (final (name, colors) in presets) {
          final failures = UiContrastChecker.verifyTokens(colors);
          expect(
            failures,
            isEmpty,
            reason: 'Preset $name must have 0 WCAG AA contrast failures',
          );
          final pairs = UiContrastChecker.normativePairs(colors);
          expect(
            pairs.length,
            equals(17),
            reason: 'Preset $name must validate exactly 17 normative pairs',
          );
          for (final pair in pairs) {
            final ratio = UiContrastChecker.contrastRatio(
              pair.foreground,
              pair.background,
            );
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason: '$name pair ${pair.name} had contrast $ratio (< 4.5:1)',
            );
          }
        }
      },
    );

    test('detects low-contrast failures and composites translucent colors', () {
      expect(
        UiContrastChecker.contrastRatio(Colors.black, Colors.white),
        closeTo(21.0, 0.01),
      );
      expect(
        UiContrastChecker.meetsWcagAa(
          const Color(0xFFCCCCCC),
          const Color(0xFFFFFFFF),
        ),
        isFalse,
      );
      final translucentRatio = UiContrastChecker.contrastRatio(
        const Color.fromRGBO(0, 0, 0, 0.5),
        Colors.white,
      );
      expect(translucentRatio, lessThan(21.0));
      expect(translucentRatio, greaterThan(3.5));

      final broken = UiThemePresets.calm.light.colors.copyWith(
        muted: const Color(0xFFEAEAEA),
        onAccent: const Color(0xFF00648B),
      );
      final failures = UiContrastChecker.verifyTokens(broken);
      final failedNames = failures.map((failure) => failure.pairName).toSet();
      expect(failedNames, contains('muted on panel'));
      expect(failedNames, contains('muted on bg'));
      expect(failedNames, contains('onAccent on accent'));
    });

    test('supports copyWith, lerp, and value equality', () {
      final a = UiThemePresets.calm.light.colors;
      final b = UiThemePresets.calm.dark.colors;
      expect(UiColorTokens.lerp(a, b, 0.0), equals(a));
      expect(UiColorTokens.lerp(a, b, 1.0), equals(b));
      final mid = UiColorTokens.lerp(a, b, 0.5);
      expect(mid, isNot(equals(a)));
      expect(mid, isNot(equals(b)));
      expect(a.copyWith(accent: b.accent).accent, equals(b.accent));
      expect(a.hashCode, equals(a.copyWith().hashCode));
    });
  });
}
