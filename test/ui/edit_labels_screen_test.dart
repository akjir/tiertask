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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiertask/main.dart';
import 'package:tiertask/models/webdav_config.dart';
import 'package:tiertask/providers/task_providers.dart';
import 'package:tiertask/repositories/settings_repository.dart';

import 'test_helpers.dart';

void main() {
  testWidgets(
    'Side panel removes tier items, displays Google Keep style Labels with Edit at top, task counts, label filtering, and Create new label opening EditLabelsScreen',
    (WidgetTester tester) async {
      const labelsTdf = '''
tdf 0.2.0

label home {
  name "Home"
  color "#00E5FF"
}
label business {
  name "Business"
  color "#EB06FF"
}
task t001 {
  name "Prepare quarterly report"
  created 2026-11-01 08:00
  queued 2026-11-01 08:00
  labels business home
}
task t002 {
  name "Water garden plants"
  created 2026-11-01 08:30
  queued 2026-11-01 08:30
  labels home
}
''';
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              InMemorySettingsRepository(
                const WebDavConfig(language: AppLanguage.english),
              ),
            ),
            localFileRepositoryProvider.overrideWith(
              (ref) => FakeLocalFileRepository(
                config: const WebDavConfig(language: AppLanguage.english),
                initialTdf: labelsTdf,
              ),
            ),
            clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1)),
          ],
          child: const TierTaskApp(),
        ),
      );

      await tester.pumpAndSettle();

      expect(
        find.text('Prepare quarterly report'),
        findsOneWidget,
        reason: 'Focus task must render on the landing page',
      );
      expect(
        find.text('Water garden plants'),
        findsOneWidget,
        reason: 'Second Focus task must render on the landing page',
      );
      expect(
        find.text('LABELS'),
        findsNothing,
        reason: 'Labels section must not appear directly on the landing page',
      );

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      for (final tierLabel in [
        'Focus',
        'Ready',
        'Planned',
        'Blocked',
        'Someday',
        'Completed',
      ]) {
        expect(
          find.descendant(
            of: find.byType(Drawer),
            matching: find.text(tierLabel),
          ),
          findsNothing,
          reason: 'Side panel must not contain tier item $tierLabel',
        );
      }

      expect(
        find.text('Labels'),
        findsOneWidget,
        reason: 'Side panel must display the Labels section header',
      );
      final editButtonFinder = find.byKey(
        const ValueKey('drawer_edit_labels_button'),
      );
      expect(
        editButtonFinder,
        findsOneWidget,
        reason: 'Side panel must display the Edit button at the top of Labels',
      );
      expect(find.text('Edit'), findsOneWidget);

      final homeTileFinder = find.byKey(
        const ValueKey('drawer_label_tile_home'),
      );
      final businessTileFinder = find.byKey(
        const ValueKey('drawer_label_tile_business'),
      );
      final createLabelTileFinder = find.byKey(
        const ValueKey('drawer_create_label_tile'),
      );
      expect(homeTileFinder, findsOneWidget);
      expect(businessTileFinder, findsOneWidget);
      expect(createLabelTileFinder, findsOneWidget);
      expect(find.text('Create new label'), findsOneWidget);

      expect(
        find.descendant(of: homeTileFinder, matching: find.text('2')),
        findsOneWidget,
        reason: 'Home label tile in drawer must display task count 2',
      );
      expect(
        find.descendant(of: businessTileFinder, matching: find.text('1')),
        findsOneWidget,
        reason: 'Business label tile in drawer must display task count 1',
      );

      await tester.tap(businessTileFinder);
      await tester.pumpAndSettle();

      expect(
        find.text('Prepare quarterly report'),
        findsOneWidget,
        reason: 'Selecting Business label in drawer must show Business tasks',
      );
      expect(
        find.text('Water garden plants'),
        findsNothing,
        reason: 'Selecting Business label in drawer must filter out Home-only tasks',
      );

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      await tester.tap(businessTileFinder);
      await tester.pumpAndSettle();

      expect(
        find.text('Water garden plants'),
        findsOneWidget,
        reason: 'Tapping the active label again in the drawer must clear the filter',
      );

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      await tester.tap(editButtonFinder);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('edit_labels_screen')),
        findsOneWidget,
        reason: 'Clicking Edit at the top of the Labels section must open EditLabelsScreen',
      );
      expect(find.text('Edit labels'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('edit_label_row_home')),
          matching: find.text('2'),
        ),
        findsOneWidget,
        reason: 'EditLabelsScreen must keep the task count on Home label',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('edit_label_row_business')),
          matching: find.text('1'),
        ),
        findsOneWidget,
        reason: 'EditLabelsScreen must keep the task count on Business label',
      );

      await tester.enterText(
        find.byKey(const ValueKey('create_label_input')),
        'Camping',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('create_label_submit_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('edit_label_row_l_camping')),
        findsOneWidget,
        reason:
            'Creating a new label in EditLabelsScreen must add it to the list',
      );
      expect(find.text('Camping'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('rename_label_button_l_camping')),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('rename_label_input_l_camping')),
        'Outdoor Camping',
      );
      await tester.tap(
        find.byKey(const ValueKey('rename_label_button_l_camping')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Outdoor Camping'),
        findsOneWidget,
        reason:
            'Renaming a label in EditLabelsScreen must update its display name',
      );

      await tester.tap(
        find.byKey(const ValueKey('delete_label_button_l_camping')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Outdoor Camping'),
        findsNothing,
        reason:
            'Deleting a label in EditLabelsScreen must remove it from the list',
      );

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      await tester.tap(createLabelTileFinder);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('edit_labels_screen')),
        findsOneWidget,
        reason: 'Clicking Create new label in the drawer must also open EditLabelsScreen',
      );
    },
  );
}
