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
  group('UiAppLogo', () {
    test('exposes exact three-bar stepped geometry and opacity ratios', () {
      expect(UiAppLogo.barSpecs, hasLength(3));
      expect(
        UiAppLogo.barSpecs[0].rect,
        equals(const Rect.fromLTWH(0, 2, 22, 4)),
      );
      expect(UiAppLogo.barSpecs[0].opacity, equals(1.0));
      expect(
        UiAppLogo.barSpecs[1].rect,
        equals(const Rect.fromLTWH(0, 9, 16.5, 4)),
      );
      expect(UiAppLogo.barSpecs[1].opacity, equals(0.72));
      expect(
        UiAppLogo.barSpecs[2].rect,
        equals(const Rect.fromLTWH(0, 16, 11, 4)),
      );
      expect(UiAppLogo.barSpecs[2].opacity, equals(0.42));
    });

    testWidgets('renders ExcludeSemantics CustomPaint in active accent color', (
      tester,
    ) async {
      await pumpUiWidget(
        tester,
        const Center(child: UiAppLogo(size: 28.0)),
        tokens: UiThemePresets.plumUmber.light,
      );

      final logoFinder = find.byType(UiAppLogo);
      expect(logoFinder, findsOneWidget);
      expect(
        find.descendant(
          of: logoFinder,
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: logoFinder, matching: find.byType(CustomPaint)),
        findsOneWidget,
      );
      expect(tester.getSize(logoFinder), equals(const Size.square(28.0)));
    });

    testWidgets('accepts custom color override across dark presets', (
      tester,
    ) async {
      const overrideColor = Color(0xFFFF9100);
      await pumpUiWidget(
        tester,
        const Center(child: UiAppLogo(color: overrideColor)),
        tokens: UiThemePresets.calm.dark,
      );

      expect(find.byType(UiAppLogo), findsOneWidget);
      expect(
        tester.getSize(find.byType(UiAppLogo)),
        equals(const Size.square(22.0)),
      );
    });
  });
}
