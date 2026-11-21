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
import 'package:tiertask_ui/tiertask_ui.dart';

void main() {
  group('UiBreakpoints', () {
    test('classifies exact boundary widths across all viewport classes', () {
      const cases = <(double, UiViewportClass)>[
        (0.0, UiViewportClass.compact),
        (390.0, UiViewportClass.compact),
        (720.0, UiViewportClass.compact),
        (721.0, UiViewportClass.medium),
        (760.0, UiViewportClass.medium),
        (820.0, UiViewportClass.medium),
        (821.0, UiViewportClass.expanded),
        (1280.0, UiViewportClass.expanded),
      ];

      for (final (width, expected) in cases) {
        expect(
          UiBreakpoints.classify(width),
          equals(expected),
          reason: 'Width $width must classify as $expected',
        );
        expect(
          UiBreakpoints.isCompact(width),
          equals(expected == UiViewportClass.compact),
          reason: 'isCompact($width) must match compact classification',
        );
        expect(
          UiBreakpoints.isMediumOrSmaller(width),
          equals(expected != UiViewportClass.expanded),
          reason: 'isMediumOrSmaller($width) must match <= 820 boundary',
        );
        expect(
          UiBreakpoints.isExpanded(width),
          equals(expected == UiViewportClass.expanded),
          reason: 'isExpanded($width) must match > 820 boundary',
        );
      }
    });

    test('exposes canonical numeric breakpoint constants', () {
      expect(UiBreakpoints.compactMaxWidth, equals(720.0));
      expect(UiBreakpoints.mediumMaxWidth, equals(820.0));
    });
  });
}
