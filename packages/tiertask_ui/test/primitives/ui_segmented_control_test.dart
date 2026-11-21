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

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tiertask_ui/tiertask_ui.dart';

import '../test_helpers.dart';

void main() {
  group('UiSegmentedControl', () {
    testWidgets(
      'selects segments on tap and steps with ArrowRight and ArrowLeft keys',
      (tester) async {
        var selected = 'queue';

        await pumpUiWidget(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              return Center(
                child: SizedBox(
                  width: 360,
                  child: UiSegmentedControl<String>(
                    value: selected,
                    segments: const <UiSegment<String>>[
                      UiSegment<String>(value: 'queue', label: 'Queue'),
                      UiSegment<String>(value: 'priority', label: 'Priority'),
                      UiSegment<String>(value: 'someday', label: 'Someday'),
                    ],
                    onChanged: (next) => setState(() => selected = next),
                  ),
                ),
              );
            },
          ),
        );

        expect(find.text('Queue'), findsOneWidget);
        expect(find.text('Priority'), findsOneWidget);
        expect(find.text('Someday'), findsOneWidget);

        await tester.tap(find.text('Priority'));
        await tester.pump();
        expect(selected, equals('priority'));

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(selected, equals('someday'));

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(selected, equals('priority'));
      },
    );

    testWidgets('skips disabled segments and respects control disabled state', (
      tester,
    ) async {
      var selected = 'a';
      await pumpUiWidget(
        tester,
        Center(
          child: SizedBox(
            width: 300,
            child: UiSegmentedControl<String>(
              value: selected,
              segments: const <UiSegment<String>>[
                UiSegment<String>(value: 'a', label: 'Alpha'),
                UiSegment<String>(value: 'b', label: 'Beta', enabled: false),
                UiSegment<String>(value: 'c', label: 'Gamma'),
              ],
              onChanged: (next) => selected = next,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Beta'));
      await tester.pump();
      expect(selected, equals('a'));
    });
  });
}
