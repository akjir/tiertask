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
import 'package:tiertask/ui/layout/ui_responsive_grid.dart';

import '../test_helpers.dart';

void main() {
  group('UiResponsiveGrid', () {
    test('computes exact column counts across all presets and boundary widths', () {
      const cases = <(UiGridPreset, double, int)>[
        (UiGridPreset.twoColumnMediumCollapse, 390.0, 1),
        (UiGridPreset.twoColumnMediumCollapse, 720.0, 1),
        (UiGridPreset.twoColumnMediumCollapse, 721.0, 1),
        (UiGridPreset.twoColumnMediumCollapse, 820.0, 1),
        (UiGridPreset.twoColumnMediumCollapse, 821.0, 2),
        (UiGridPreset.twoColumnMediumCollapse, 1280.0, 2),
        (UiGridPreset.twoColumnCompactCollapse, 390.0, 1),
        (UiGridPreset.twoColumnCompactCollapse, 720.0, 1),
        (UiGridPreset.twoColumnCompactCollapse, 721.0, 2),
        (UiGridPreset.twoColumnCompactCollapse, 820.0, 2),
        (UiGridPreset.twoColumnCompactCollapse, 821.0, 2),
        (UiGridPreset.twoColumnCompactCollapse, 1280.0, 2),
        (UiGridPreset.fourActionCompactTwo, 390.0, 2),
        (UiGridPreset.fourActionCompactTwo, 720.0, 2),
        (UiGridPreset.fourActionCompactTwo, 721.0, 4),
        (UiGridPreset.fourActionCompactTwo, 820.0, 4),
        (UiGridPreset.fourActionCompactTwo, 821.0, 4),
        (UiGridPreset.fourActionCompactTwo, 1280.0, 4),
      ];

      for (final (preset, width, expectedColumns) in cases) {
        expect(
          UiResponsiveGrid.columnsForWidth(preset, width),
          equals(expectedColumns),
          reason:
              'Preset ${preset.name} at width $width must resolve $expectedColumns column(s)',
        );
      }
    });

    testWidgets(
      'lays out equal-width top-aligned rows without horizontal overflow at 390, 720, 721, 820, 821, and 1280',
      (tester) async {
        for (final width in const <double>[390, 720, 721, 820, 821, 1280]) {
          await pumpUiWidget(
            tester,
            SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  for (final preset in UiGridPreset.values)
                    UiResponsiveGrid(
                      preset: preset,
                      children: <Widget>[
                        for (var i = 0; i < 4; i++)
                          SizedBox(
                            key: ValueKey<String>('${preset.name}_$i'),
                            height: 40,
                            child: Text('Cell $i'),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            surfaceSize: Size(width, 900),
          );

          final c0 = tester.getTopLeft(
            find.byKey(const ValueKey<String>('twoColumnMediumCollapse_0')),
          );
          final c1 = tester.getTopLeft(
            find.byKey(const ValueKey<String>('twoColumnMediumCollapse_1')),
          );
          if (width > 820) {
            expect(
              c0.dy,
              equals(c1.dy),
              reason:
                  'twoColumnMediumCollapse should be side-by-side at $width',
            );
          } else {
            expect(
              c1.dy,
              greaterThan(c0.dy),
              reason:
                  'twoColumnMediumCollapse should stack vertically at $width',
            );
          }
        }
      },
    );
  });
}
