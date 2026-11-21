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
  group('UiPageHeader', () {
    testWidgets(
      'renders back button, 28px title, inline active filter on desktop, count pill, trailing, and subtitle',
      (tester) async {
        var backTapped = false;
        var filterCleared = false;

        await pumpUiWidget(
          tester,
          UiPageHeader(
            title: 'Focus',
            subtitle: 'Highest priority tasks currently in progress.',
            countLabel: '2 / 3',
            activeFilterLabel: 'Backend',
            activeFilterTooltip: 'Clear Backend filter',
            onClearActiveFilter: () => filterCleared = true,
            backLabel: 'Back to tasks',
            onBack: () => backTapped = true,
            trailing: UiButton(
              label: 'Copy',
              density: UiButtonDensity.compact,
              onPressed: () {},
            ),
          ),
          surfaceSize: const Size(1280, 800),
        );

        expect(find.text('Focus'), findsOneWidget);
        expect(find.text('2 / 3'), findsOneWidget);
        expect(find.text('Backend'), findsOneWidget);
        expect(
          find.text('Highest priority tasks currently in progress.'),
          findsOneWidget,
        );
        expect(find.text('Copy'), findsOneWidget);

        await tester.tap(find.text('Back to tasks'));
        await tester.pump();
        expect(backTapped, isTrue);

        await tester.tap(find.text('Backend'));
        await tester.pump();
        expect(filterCleared, isTrue);
      },
    );

    testWidgets(
      'hides inline active filter on compact by default and shows it when showInlineFilterOnCompact is true',
      (tester) async {
        await pumpUiWidget(
          tester,
          UiPageHeader(
            title: 'Focus',
            activeFilterLabel: 'Work',
            onClearActiveFilter: () {},
            showInlineFilterOnCompact: false,
          ),
          surfaceSize: const Size(390, 800),
        );
        expect(find.text('Work'), findsNothing);

        await pumpUiWidget(
          tester,
          UiPageHeader(
            title: 'Search',
            activeFilterLabel: 'Work',
            onClearActiveFilter: () {},
            showInlineFilterOnCompact: true,
          ),
          surfaceSize: const Size(390, 800),
        );
        expect(find.text('Work'), findsOneWidget);
      },
    );

    testWidgets(
      'wraps long titles with count pill on compact 390px viewports without overflow',
      (tester) async {
        await pumpUiWidget(
          tester,
          const UiPageHeader(
            title: 'Long Localized Section Title',
            countLabel: '17 / 17 WCAG AA',
          ),
          surfaceSize: const Size(390, 800),
        );
        expect(find.text('Long Localized Section Title'), findsOneWidget);
        expect(find.text('17 / 17 WCAG AA'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
